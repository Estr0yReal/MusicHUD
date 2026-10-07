import AppKit
import Combine
import MusicHUDCore

/// A weak handle on the HUD panel so SwiftUI views can drive window behaviour
/// (dragging, resizing) without owning it.
///
/// Deliberately *not* `@Published`: storing an `NSWindow` in a published
/// property invites retain cycles and needless invalidations. Views only need
/// to read it at event time.
final class WindowBridge {
    weak var window: NSWindow?
}

/// The single source of truth for the running app.
///
/// It owns the settings blob, the current now-playing snapshot, the provider
/// that produces it, and the window handle. Views observe it; they never talk
/// to Music.app, the audio system or the window server directly.
@MainActor
final class AppState: ObservableObject {

    /// Persisted configuration. Mutating this saves and applies immediately,
    /// which is what makes every switch in the settings panel real.
    @Published var settings: HUDSettings {
        didSet {
            // Re-assigning inside `didSet` re-enters once; the nested call then
            // sees an already-clean value and does the real work, so the
            // side effects below still run exactly once.
            let sanitized = settings.sanitized()
            if sanitized != settings {
                settings = sanitized
                return
            }
            guard settings != oldValue else { return }
            store.save(settings)
            applyHandler?(settings)
            syncProvider()
            audio.apply(
                spectrumSettings: SpectrumSettings(hud: settings),
                frameRate: settings.spectrumFrameRate
            )
        }
    }

    /// What is playing right now.
    @Published private(set) var snapshot: NowPlayingSnapshot

    /// Whether Music.app is reachable, and if not, why.
    @Published private(set) var availability: MusicAvailability

    /// Decoded cover art for the current track.
    ///
    /// Held as an `NSImage` rather than raw bytes so the 1200×1200 JPEG is
    /// decoded once per track change instead of on every render.
    @Published private(set) var artworkImage: NSImage?

    /// How long music has been playing this session.
    @Published private(set) var sessionElapsed: TimeInterval = 0

    /// State of the audio capture pipeline, mirrored from the service.
    @Published private(set) var captureState: AudioCaptureState = .idle

    /// The capture + analysis pipeline. Owned here so both the HUD and the
    /// diagnostics panel read exactly the same thing.
    let audio: AudioCaptureService

    // MARK: World clock

    /// Configured cities, in rotation order. Persisted separately from
    /// `HUDSettings` so that adding this feature could not invalidate an
    /// existing settings blob.
    @Published var worldClockCities: [WorldClockCity] {
        didSet {
            guard worldClockCities != oldValue else { return }
            worldClockStore.save(worldClockCities)
            cycle.update(cities: worldClockCities)
        }
    }

    /// What the large display is showing right now.
    ///
    /// Published because the clock view observes it, but it changes only on a
    /// click — never per frame — so it cannot affect the spectrum's render path.
    @Published private(set) var clockDisplayMode: ClockDisplayMode = .track

    private var cycle = WorldClockCycle()
    private let worldClockStore: WorldClockStore

    /// Current language and string lookup. Published through `Localization`,
    /// which every view that needs a non-SwiftUI string observes.
    let localization: Localization

    private let languageStore: LanguageStore

    /// The user's language choice, or `nil` when they have never made one.
    var language: AppLanguage { localization.language }

    /// Switches language immediately — no restart needed.
    func setLanguage(_ language: AppLanguage) {
        guard language != localization.language else { return }
        localization.setLanguage(language)
        AppLocalization.shared.setLanguage(language)
        languageStore.save(language)
        // The status menu is rebuilt whenever it opens, so it needs no nudge;
        // SwiftUI views re-render because they observe `localization`.
        objectWillChange.send()
    }

    let windowBridge = WindowBridge()

    /// Set by `HUDWindowController` so settings changes reach the panel.
    var applyHandler: ((HUDSettings) -> Void)?

    /// Set by `HUDWindowController` so the settings panel can move the HUD
    /// without knowing anything about windows.
    var resetPositionHandler: (() -> Void)?

    /// Snapshot-only metadata override.
    ///
    /// TEST INSTRUMENTATION, not a product feature: it is inert unless
    /// `MUSICHUD_SNAPSHOT_TITLE` is set, and nothing in the app reads it
    /// otherwise. It exists because the long-title / Japanese / Chinese layout
    /// cases the Phase 5 brief requires as snapshots cannot be produced on
    /// demand from a real Music.app library, and a layout guarantee that is
    /// never rendered is not a guarantee. It replaces *display text only* — it
    /// cannot affect audio, FFT or transport.
    private let snapshotMetadataOverride: TrackMetadata?

    private var audioSinks = Set<AnyCancellable>()
    private let store: HUDSettingsStore
    private var provider: NowPlayingProviding
    private var factory: (MusicDataSource) -> NowPlayingProviding
    /// Raw bytes kept alongside the decoded image so a redraw does not
    /// re-decode, and so we can tell when the artwork actually changed.
    private var artworkData: Data?

    init(
        store: HUDSettingsStore = HUDSettingsStore(),
        providerFactory: ((MusicDataSource) -> NowPlayingProviding)? = nil,
        audioService: AudioCaptureService? = nil,
        worldClockStore: WorldClockStore = WorldClockStore(),
        languageStore: LanguageStore = LanguageStore()
    ) {
        self.worldClockStore = worldClockStore
        self.languageStore = languageStore
        self.localization = Localization(stored: languageStore.load())
        AppLocalization.shared.setLanguage(localization.language)
        let factory = providerFactory ?? AppState.defaultProvider(for:)
        self.factory = factory
        self.store = store

        let loaded = store.load()
        self.settings = loaded
        self.snapshotMetadataOverride = AppState.makeSnapshotOverride()

        let cities = worldClockStore.load()
        self.worldClockCities = cities
        self.cycle = WorldClockCycle(cities: cities)

        let audio = audioService ?? AudioCaptureService(
            settings: SpectrumSettings(hud: loaded),
            frameRate: loaded.spectrumFrameRate
        )
        self.audio = audio
        self.captureState = audio.state

        let provider = factory(loaded.dataSource)
        self.provider = provider
        self.snapshot = provider.snapshot
        self.availability = provider.availability

        provider.onChange = { [weak self] in
            self?.providerDidUpdate()
        }
        provider.start()

        // Only the capture *state* is mirrored here, because it changes rarely.
        //
        // The spectrum frame is deliberately NOT published from AppState: at
        // 60 Hz it would invalidate every view observing AppState, i.e. the
        // whole card. `SpectrumView` observes the capture service directly, so
        // a spectrum update redraws one Canvas and nothing else. Measured
        // before the change: ~16% CPU for the HUD alone.
        audio.$state
            .sink { [weak self] state in
                guard let self, self.captureState != state else { return }
                self.captureState = state
            }
            .store(in: &audioSinks)
    }

    /// Advances the large display: Track → city 1 → … → city n → Track.
    func advanceClockDisplay() {
        cycle.update(cities: worldClockCities)
        cycle.advance()
        clockDisplayMode = cycle.mode
        // Diagnostic: makes the click-versus-drag boundary observable from
        // outside the process, which is how Phase 6.1's interaction fix was
        // validated. One line per *click*, not per frame.
        switch clockDisplayMode {
        case .track:
            print("[CLOCK] mode -> TRACK")
        case .worldClock(let city):
            print("[CLOCK] mode -> \(city.displayName)")
        }
        fflush(stdout)
    }

    /// Replaces the city list from Settings, keeping the current selection when
    /// it still exists.
    func setWorldClockCities(_ cities: [WorldClockCity]) {
        worldClockCities = WorldClockStore.sanitized(cities)
        clockDisplayMode = cycle.mode
    }

    /// Snapshot-only: forces a display mode so each clock state can be captured.
    func setClockDisplayModeForSnapshot(_ mode: ClockDisplayMode) {
        clockDisplayMode = mode
    }

    /// Starts the capture pipeline. Called when the HUD becomes visible, so the
    /// system-audio permission is only exercised when the spectrum is on screen.
    func startAudioCapture() {
        audio.apply(
            spectrumSettings: SpectrumSettings(hud: settings),
            frameRate: settings.spectrumFrameRate
        )
        audio.start()
    }

    func stopAudioCapture() {
        audio.stop()
    }

    /// The real provider by default; demo data only when explicitly selected.
    ///
    /// This is the composition root: the scripting client lives in the app
    /// target and the provider lives in the logic target, and they are only
    /// ever wired together here.
    static func defaultProvider(for source: MusicDataSource) -> NowPlayingProviding {
        switch source {
        case .appleMusic:
            return AppleMusicNowPlayingService(client: AppleScriptMusicClient())
        case .demo:
            return MockNowPlayingService()
        }
    }

    // MARK: - Provider plumbing

    /// Reads the snapshot-only override from the environment, if present.
    private static func makeSnapshotOverride() -> TrackMetadata? {
        let environment = ProcessInfo.processInfo.environment
        guard let title = environment["MUSICHUD_SNAPSHOT_TITLE"], !title.isEmpty else { return nil }
        return TrackMetadata(
            title: title,
            artist: environment["MUSICHUD_SNAPSHOT_ARTIST"] ?? "Artist",
            album: environment["MUSICHUD_SNAPSHOT_ALBUM"] ?? "Album",
            duration: 227,
            artworkSeed: 0,
            subtitle: ""
        )
    }

    /// Applies the snapshot override to a snapshot, if one is configured.
    private func applyingSnapshotOverride(to snapshot: NowPlayingSnapshot) -> NowPlayingSnapshot {
        guard let override = snapshotMetadataOverride else { return snapshot }
        return NowPlayingSnapshot(
            metadata: override,
            state: snapshot.state,
            position: snapshot.position,
            source: snapshot.source
        )
    }

    private func providerDidUpdate() {
        // Guarded assignments: these are `@Published`, and `HUDView` observes
        // this object, so an unconditional write re-renders the whole card even
        // when nothing changed. The music provider fires these several times a
        // second regardless of whether the values moved.
        let incoming = applyingSnapshotOverride(to: provider.snapshot)
        if snapshot != incoming { snapshot = incoming }
        if availability != provider.availability { availability = provider.availability }
        if sessionElapsed != provider.sessionElapsed { sessionElapsed = provider.sessionElapsed }

        let data = provider.artworkData
        if data != artworkData {
            artworkData = data
            // Decoding is the expensive part, so it happens only when the bytes
            // actually change — not on every poll or playhead tick.
            artworkImage = data.flatMap { $0.isEmpty ? nil : NSImage(data: $0) }
        }
    }

    /// Rebuilds the provider when the data source setting changes.
    private func syncProvider() {
        let needsSwap: Bool
        switch settings.dataSource {
        case .appleMusic:
            needsSwap = !(provider is AppleMusicNowPlayingService)
        case .demo:
            needsSwap = !(provider is MockNowPlayingService)
        }

        if needsSwap {
            provider.stop()
            let replacement = factory(settings.dataSource)
            provider = replacement
            artworkData = nil
            artworkImage = nil
            replacement.onChange = { [weak self] in
                self?.providerDidUpdate()
            }
            replacement.start()
        }

        if let apple = provider as? AppleMusicNowPlayingService {
            apple.setPollInterval(settings.metadataPollInterval)
        }
    }

    /// Asks the provider to re-read immediately, e.g. when the app is activated.
    func refreshNowPlaying() {
        provider.refreshNow()
    }

    // MARK: - Transport

    /// `false` when the buttons have nothing they can act on — Music.app is not
    /// running, or Automation access has not been granted.
    var canControlTransport: Bool {
        availability.allowsTransportControl
    }

    func playPause() {
        guard canControlTransport else { return }
        provider.playPause()
    }

    func nextTrack() {
        guard canControlTransport else { return }
        provider.next()
    }

    func previousTrack() {
        guard canControlTransport else { return }
        provider.previous()
    }

    // MARK: - Window plumbing

    /// The user finished dragging or resizing; remember where the panel ended up.
    func persistWindowFrame() {
        guard settings.rememberWindowFrame, let window = windowBridge.window else { return }
        let frame = window.frame
        settings.windowFrame = WindowFrame(
            x: frame.origin.x,
            y: frame.origin.y,
            width: frame.width,
            height: frame.height
        )
    }

    func setClickThrough(_ enabled: Bool) {
        settings.clickThrough = enabled
    }

    func toggleClickThrough() {
        settings.clickThrough.toggle()
    }

    func restoreDefaultSettings() {
        settings = HUDSettings()
    }

    /// Moves the panel back to the top-right of the primary display.
    func resetWindowPosition() {
        resetPositionHandler?()
    }

    // MARK: - Music access

    /// Opens System Settings at Privacy & Security → Automation.
    ///
    /// The `x-apple.systempreferences` scheme with the `Privacy_Automation`
    /// anchor is the documented deep link and is verified to be registered by
    /// System Settings on this system. If macOS ever changes the anchor the
    /// call still opens System Settings, just not the exact pane, so the
    /// settings panel also spells out the manual path.
    func openAutomationSettings() {
        let deepLink = "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation"
        if let url = URL(string: deepLink), NSWorkspace.shared.open(url) {
            return
        }
        if let fallback = URL(string: "x-apple.systempreferences:") {
            NSWorkspace.shared.open(fallback)
        }
    }
}
