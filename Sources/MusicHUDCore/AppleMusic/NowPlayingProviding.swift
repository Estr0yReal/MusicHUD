import Foundation

/// A source of "what is playing right now".
///
/// Two implementations exist:
///
/// * `AppleMusicNowPlayingService` (in the app target) — the real one, reading
///   Music.app over public Apple Events.
/// * `MockNowPlayingService` (below) — built-in demo content, used for UI work
///   and by the test suite, and always reported as `.demo` so it can never be
///   mistaken for a real music session.
///
/// The protocol exposes three read-only properties plus a single change
/// notification. That keeps the surface small: adding artwork and availability
/// in Phase 2 did not require any new plumbing, only new properties.
///
/// The whole protocol is main-actor isolated. Every provider publishes into
/// `AppState`, which is itself main-actor, and the Apple Music provider hops to
/// the main queue before mutating anything — so stating the isolation here
/// documents the invariant rather than restricting anything.
@MainActor
public protocol NowPlayingProviding: AnyObject {

    /// The most recent snapshot. Always safe to read.
    var snapshot: NowPlayingSnapshot { get }

    /// Whether Music.app is reachable, and if not, why.
    var availability: MusicAvailability { get }

    /// Raw artwork bytes for the current track, or `nil`.
    ///
    /// Empty `Data` means "this track has no artwork", which is different from
    /// `nil` ("not known yet").
    var artworkData: Data? { get }

    /// How long music has actually been playing this session, in seconds.
    ///
    /// Only the time spent playing counts; pausing stops it.
    var sessionElapsed: TimeInterval { get }

    /// Fired on the main thread whenever any of the properties above changes.
    var onChange: (() -> Void)? { get set }

    /// Begin observing. Idempotent.
    func start()

    /// Stop observing and release resources. Idempotent.
    func stop()

    // Transport. Implementations that cannot control playback should no-op.
    func playPause()
    func next()
    func previous()

    /// Forces an immediate refresh, bypassing the poll interval.
    func refreshNow()
}

public extension NowPlayingProviding {
    func refreshNow() {}
}

/// Transport-only capability probe, so the UI can visually disable controls
/// that the current provider cannot honour.
@MainActor
public protocol NowPlayingTransportControlling: AnyObject {
    var canControlTransport: Bool { get }
}

// MARK: - Demo library

/// Hard-coded demo content.
///
/// Everything here is fabricated. It exists so the UI can be developed and the
/// automated tests can run without Music.app, and it is always reported as
/// `.demo` so the card shows a `DEMO DATA` badge. It is **never** used as a
/// silent fallback when Apple Music is unavailable — an unavailable Apple Music
/// shows an explicit idle state instead.
public enum DemoLibrary {
    public static let tracks: [TrackMetadata] = [
        TrackMetadata(
            title: "TID-PACIFIC",
            artist: "3WA",
            album: "Project Locus — [Digital Edition]",
            duration: 3 * 60 + 47,
            artworkSeed: 0,
            subtitle: "圣迭戈 Pacific"
        ),
        TrackMetadata(
            title: "NIGHT DRIVE PROTOCOL",
            artist: "Aurora Vector",
            album: "Signal Bloom",
            duration: 4 * 60 + 12,
            artworkSeed: 1,
            subtitle: "Low Orbit"
        ),
        TrackMetadata(
            title: "ANALOG SUNRISE",
            artist: "Mira Solace",
            album: "Paper Circuits",
            duration: 2 * 60 + 58,
            artworkSeed: 2,
            subtitle: "Terrace Session"
        ),
    ]

    /// Playhead position used by the demo snapshot (1:23 into a 3:47 track).
    public static let demoPosition: TimeInterval = 83

    /// "Session elapsed" value chosen to echo the reference design's `00:42:55`.
    public static let demoSessionElapsed: TimeInterval = 42 * 60 + 55

    /// The session-elapsed value for a given track index, so the clock changes
    /// meaningfully when the user steps through the demo tracks.
    public static func sessionElapsed(forTrackAt index: Int) -> TimeInterval {
        let base = demoSessionElapsed
        return base + Double(max(index, 0)) * 201
    }
}

// MARK: - Mock service

/// Serves `DemoLibrary` and lets the transport buttons move through the demo
/// playlist so the layout can be exercised with different text lengths.
///
/// It never touches Apple Music or the audio system. Used by the test suite and
/// by the settings panel's demo-data mode.
@MainActor
public final class MockNowPlayingService: NowPlayingProviding, NowPlayingTransportControlling {
    public private(set) var snapshot: NowPlayingSnapshot
    public var onChange: (() -> Void)?

    public private(set) var availability: MusicAvailability = .ready
    public private(set) var artworkData: Data?

    private var index: Int

    public var canControlTransport: Bool { true }

    /// - Parameter index: which demo track to start on.
    public init(index: Int = 0) {
        self.index = min(max(index, 0), DemoLibrary.tracks.count - 1)
        self.snapshot = Self.makeSnapshot(index: self.index, state: .playing)
    }

    public func start() {
        availability = .ready
        publish()
    }

    public func stop() {
        // Nothing to tear down.
    }

    public func playPause() {
        switch snapshot.state {
        case .playing:
            snapshot.state = .paused
            availability = .ready
        case .paused, .stopped:
            snapshot.state = .playing
            availability = .ready
        }
        publish()
    }

    public func next() {
        index = (index + 1) % DemoLibrary.tracks.count
        snapshot = Self.makeSnapshot(index: index, state: .playing)
        availability = .ready
        publish()
    }

    public func previous() {
        index = (index - 1 + DemoLibrary.tracks.count) % DemoLibrary.tracks.count
        snapshot = Self.makeSnapshot(index: index, state: .playing)
        availability = .ready
        publish()
    }

    /// Current demo track index, exposed for tests.
    public var currentIndex: Int { index }

    /// Demo mode keeps Phase 1's fixed session value, because everything else
    /// on the card is demo data too and it is always badged as such.
    public var sessionElapsed: TimeInterval {
        DemoLibrary.sessionElapsed(forTrackAt: index)
    }

    // MARK: Helpers

    private static func makeSnapshot(index: Int, state: PlaybackState) -> NowPlayingSnapshot {
        NowPlayingSnapshot(
            metadata: DemoLibrary.tracks[index],
            state: state,
            position: DemoLibrary.demoPosition,
            source: .demo
        )
    }

    private func publish() {
        onChange?()
    }
}
