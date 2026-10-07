import Foundation

/// The real now-playing provider: Music.app over public Apple Events.
///
/// ## Polling design
///
/// Two independent cadences, because metadata and the playhead have very
/// different costs:
///
/// * **Metadata** is re-read from Music.app every `pollInterval` (1.5 s by
///   default). One Apple Event round trip returns every field at once.
/// * **The playhead** is *not* re-read on a fast timer. It is interpolated
///   locally from the last anchored value, and the interpolation is gated on
///   `PlaybackState` by `PositionEstimator`: it advances only while playing,
///   freezes while paused, and resets on a track change.
///
/// The fast timer therefore performs no scripting at all — it only re-renders
/// from values already in memory — which is what keeps the cost of a 0.5 s
/// display refresh negligible.
///
/// ## Lifecycle
///
/// Everything is driven from the main thread except the Apple Event calls,
/// which happen on the client's serial scripting queue. Nothing here blocks the
/// main thread, so a slow or unresponsive Music.app degrades the update rate
/// rather than freezing the HUD.
@MainActor
public final class AppleMusicNowPlayingService: NowPlayingProviding {

    // MARK: Cadence

    /// How often Music.app is consulted.
    private var pollInterval: TimeInterval = 1.5
    /// How often the interpolated playhead is published while playing.
    private static let playbackTickInterval: TimeInterval = 0.5
    /// Delay before re-reading after a transport command, to give Music.app
    /// time to apply it before we look.
    private static let postCommandRefreshDelay: TimeInterval = 0.35
    /// How many polls to keep asking for a cover that has not appeared yet.
    /// Streamed tracks often gain their artwork a second or two after starting.
    private static let maxArtworkFetchAttempts = 4

    // MARK: Collaborators

    private let client: MusicClient
    private let artworkCache: ArtworkCache

    // MARK: Published state

    public private(set) var snapshot: NowPlayingSnapshot = .idle {
        didSet { if snapshot != oldValue { needsNotify = true } }
    }
    public private(set) var availability: MusicAvailability = .unknown {
        didSet { if availability != oldValue { needsNotify = true } }
    }
    public private(set) var artworkData: Data? {
        didSet { if artworkData != oldValue { needsNotify = true } }
    }

    public var onChange: (() -> Void)?

    // MARK: Internal state

    private var estimator = PositionEstimator()
    private var sessionClock = SessionClock()
    private var currentTrackKey = ""
    private var pollTimer: DispatchSourceTimer?
    private var tickTimer: DispatchSourceTimer?
    private var isRefreshing = false
    private var isRunning = false
    private var needsNotify = false
    /// How many times we have asked for the current track's artwork. Reset on
    /// every track change.
    private var artworkFetchAttempts = 0
    private var isFetchingArtwork = false

    /// No convenience `init()` on purpose: the concrete scripting client lives
    /// in the app target, so the composition root (`AppState`) is what pairs
    /// them up. That is the seam that lets the test suite drive this class with
    /// `MockMusicClient` and never touch Music.app.
    public init(client: MusicClient, artworkCache: ArtworkCache = ArtworkCache()) {
        self.client = client
        self.artworkCache = artworkCache
    }

    deinit {
        pollTimer?.cancel()
        tickTimer?.cancel()
    }

    /// Playing time accumulated this session, in seconds.
    public var sessionElapsed: TimeInterval {
        sessionClock.elapsed(at: MonotonicClock.now)
    }

    // MARK: - Lifecycle

    public func start() {
        guard !isRunning else { return }
        isRunning = true
        startPollTimer()
        refresh()
    }

    public func stop() {
        isRunning = false
        pollTimer?.cancel()
        pollTimer = nil
        tickTimer?.cancel()
        tickTimer = nil
    }

    public func setPollInterval(_ interval: TimeInterval) {
        let clamped = min(max(interval, 0.5), 10)
        guard abs(clamped - pollInterval) > 0.01 else { return }
        pollInterval = clamped
        guard isRunning else { return }
        pollTimer?.cancel()
        startPollTimer()
    }

    public func refreshNow() {
        refresh()
    }

    // MARK: - Transport

    public func playPause() { send(.playPause) }
    public func next() { send(.nextTrack) }
    public func previous() { send(.previousTrack) }

    private func send(_ command: MusicTransportCommand) {
        // Never launch Music.app as a side effect of a transport button; if it
        // is not running there is nothing to control.
        guard client.isMusicAppRunning() else { return }

        // Capture what the background closure needs *before* leaving the main
        // actor, so nothing main-actor-isolated is touched off it.
        let client = self.client
        let delay = Self.postCommandRefreshDelay

        client.queue.async { [weak self] in
            try? client.send(command)
            self?.onMainActor(after: delay) { [weak self] in
                self?.refresh()
            }
        }
    }

    // MARK: - Actor hopping

    /// Runs `work` on the main actor.
    ///
    /// `assumeIsolated` is accurate here rather than a shortcut: these are only
    /// ever called from `DispatchQueue.main`, so the main actor's executor
    /// really is the current one.
    nonisolated private func onMainActor(_ work: @escaping @MainActor @Sendable () -> Void) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated { work() }
        }
    }

    nonisolated private func onMainActor(
        after delay: TimeInterval,
        _ work: @escaping @MainActor @Sendable () -> Void
    ) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            MainActor.assumeIsolated { work() }
        }
    }

    // MARK: - Polling

    private func startPollTimer() {
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(
            deadline: .now() + pollInterval,
            repeating: pollInterval,
            leeway: .milliseconds(250)
        )
        timer.setEventHandler { [weak self] in
            self?.refresh()
        }
        timer.resume()
        pollTimer = timer
    }

    /// Starts or stops the smooth-playhead timer.
    ///
    /// It only runs while the transport is playing. When paused there is
    /// nothing to interpolate, so the timer is cancelled rather than left
    /// spinning — a paused HUD should cost nothing.
    private func updateTickTimer() {
        let shouldTick = snapshot.state == .playing

        if shouldTick, tickTimer == nil {
            let timer = DispatchSource.makeTimerSource(queue: .main)
            timer.schedule(
                deadline: .now(),
                repeating: Self.playbackTickInterval,
                leeway: .milliseconds(100)
            )
            timer.setEventHandler { [weak self] in
                self?.publishInterpolatedPosition()
            }
            timer.resume()
            tickTimer = timer
        } else if !shouldTick, tickTimer != nil {
            tickTimer?.cancel()
            tickTimer = nil
        }
    }

    /// Re-renders from values already in memory. Sends no Apple Events.
    private func publishInterpolatedPosition() {
        guard snapshot.state == .playing else { return }

        let now = MonotonicClock.now
        sessionClock.update(isPlaying: true, now: now)

        // Nothing to interpolate from, so there is nothing safe to publish.
        //
        // Without this guard the tick reports 0 and stomps the real position a
        // poll just wrote, producing a reading that alternates between correct
        // and zero. A live trace caught exactly that: `38.83 → 0.00 → 40.05`.
        // `estimate()` returns 0 when unanchored, and 0 is a perfectly valid
        // playhead position, so the damage is silent.
        guard estimator.isAnchored else { return }

        let position = estimator.estimate(at: now)

        // Only touch the published value when the whole-second readout or the
        // progress bar would actually change, so SwiftUI is not invalidated
        // five times a second for nothing.
        guard abs(position - snapshot.position) >= 0.25 else { return }
        snapshot.position = position
        notifyIfNeeded()
    }

    // MARK: - Refresh

    private func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true

        let client = self.client

        client.queue.async { [weak self] in
            let outcome: Result<MusicRawSnapshot, MusicClientError>
            do {
                outcome = .success(try client.fetchSnapshot())
            } catch let error as MusicClientError {
                outcome = .failure(error)
            } catch {
                outcome = .failure(.scriptingFailure(code: 0, message: String(describing: error)))
            }

            self?.onMainActor { [weak self] in
                guard let self else { return }
                self.isRefreshing = false
                self.apply(outcome)
            }
        }
    }

    private func apply(_ outcome: Result<MusicRawSnapshot, MusicClientError>) {
        switch outcome {
        case .failure(let error):
            applyFailure(error)
        case .success(let raw):
            apply(raw)
        }

        updateTickTimer()
        notifyIfNeeded()
    }

    private func apply(_ raw: MusicRawSnapshot) {
        let (metadata, state) = raw.interpret()
        let now = MonotonicClock.now

        if raw.isDisplayable, let metadata {
            let key = ArtworkCache.key(for: metadata)
            let trackChanged = key != currentTrackKey

            if trackChanged {
                // A new track resets the playhead anchor along with the artwork.
                currentTrackKey = key
                estimator.reset()
            }

            // Runs on every poll, not just on a track change: it is what lets a
            // late-arriving cover be picked up, and it returns immediately once
            // the artwork is known.
            updateArtwork(for: metadata, key: key, trackChanged: trackChanged)

            estimator.synchronise(
                trackID: key,
                position: raw.position,
                duration: metadata.duration,
                state: state,
                now: now
            )
            sessionClock.update(isPlaying: state == .playing, now: now)

            snapshot = NowPlayingSnapshot(
                metadata: metadata,
                state: state,
                position: estimator.estimate(at: now),
                source: .appleMusic
            )
            availability = .ready

        } else {
            // Music.app is running but there is nothing to show. Any previously
            // displayed track must be cleared rather than left frozen on screen
            // looking like it is still current.
            clearTrack()
            snapshot = NowPlayingSnapshot(
                metadata: raw.hasTrack && !raw.title.isEmpty
                    ? TrackMetadata(
                        title: raw.title,
                        artist: raw.artist,
                        album: raw.album,
                        duration: raw.duration,
                        persistentID: raw.persistentID
                    )
                    : nil,
                state: state,
                // No displayable track means no meaningful playhead; reporting
                // a leftover position here would be a number the UI has no
                // context for.
                position: 0,
                source: .none
            )
            availability = .noTrack
        }
    }

    private func applyFailure(_ error: MusicClientError) {
        clearTrack()
        snapshot = .idle

        switch error {
        case .musicAppNotRunning:
            availability = .musicAppNotRunning
        case .accessRequired:
            availability = .accessRequired
        case .noCurrentTrack:
            availability = .noTrack
        case .scriptingFailure(let code, let message):
            availability = .failed("\(message)（\(code)）")
        case .unexpectedResult(let detail):
            availability = .failed(detail)
        }
    }

    /// Drops all per-track state. Keeps `sessionClock` running: it measures the
    /// session, not the track, so switching songs must not reset it.
    private func clearTrack() {
        currentTrackKey = ""
        estimator.reset()
        artworkData = nil
        artworkFetchAttempts = 0
        sessionClock.update(isPlaying: false, now: MonotonicClock.now)
    }

    // MARK: - Artwork

    /// Decides whether to fetch artwork for the current reading.
    ///
    /// Two things happen here, and both matter:
    ///
    /// * Covers are cached by track, so skipping back and forth does not re-read
    ///   a 340 KB JPEG each time.
    /// * A missing cover is retried a few times. Music.app frequently has no
    ///   artwork yet for a track that has only just started streaming, and it
    ///   arrives a second or two later. Treating the first `nil` as final would
    ///   leave that track permanently blank, so we look again for a few polls
    ///   and then stop rather than asking forever.
    private func updateArtwork(for metadata: TrackMetadata, key: String, trackChanged: Bool) {
        if trackChanged {
            artworkFetchAttempts = 0
            if let cached = artworkCache.data(for: key) {
                artworkData = cached
                return          // already have it; nothing more to do for this track
            }
            // Clear the previous track's cover rather than showing a stale one.
            artworkData = nil
        }

        guard artworkData == nil, !isFetchingArtwork else { return }
        guard artworkFetchAttempts < Self.maxArtworkFetchAttempts else { return }

        artworkFetchAttempts += 1
        fetchArtwork(key: key)
    }

    private func fetchArtwork(key: String) {
        isFetchingArtwork = true
        let client = self.client

        client.queue.async { [weak self] in
            let data = try? client.fetchArtworkData()

            self?.onMainActor { [weak self] in
                guard let self else { return }
                self.isFetchingArtwork = false

                // The track may have changed while the fetch was in flight.
                guard self.currentTrackKey == key else { return }

                guard let data, !data.isEmpty else { return }   // retried later

                self.artworkCache.store(data, for: key)
                self.artworkData = data
                self.notifyIfNeeded()
            }
        }
    }

    // MARK: - Notification

    private func notifyIfNeeded() {
        guard needsNotify else { return }
        needsNotify = false
        onChange?()
    }
}
