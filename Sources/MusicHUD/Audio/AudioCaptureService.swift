import AppKit
import Foundation
import MusicHUDCore

/// Owns the audio capture pipeline and the FFT analysis, and publishes the result.
///
/// THREADING — this is the whole point of the class:
///
///     audio thread     ->  engine.ingest(...)          mix to mono, push, return
///     analysis queue   ->  engine.processAvailable()   pull hops, run FFTs, smooth
///     main actor       ->  publish(frame)              store the newest frame
///     SwiftUI          ->  reads `spectrum`            draws it
///
/// The audio thread never runs an FFT, never allocates and never touches an
/// `@Published` property. The analysis queue runs the DSP. The main actor only
/// receives finished frames, and SwiftUI re-renders at the display rate from the
/// most recent one — so the ~94 Hz FFT rate never becomes a ~94 Hz UI rate.
@MainActor
final class AudioCaptureService: ObservableObject {

    // MARK: Published - diagnostics

    @Published private(set) var state: AudioCaptureState = .idle
    @Published private(set) var level: AudioLevel?
    @Published private(set) var peakHold: Float = 0
    @Published private(set) var format: AudioStreamFormatInfo?
    @Published private(set) var targetLabel = "Music"
    @Published private(set) var statusDetail = ""
    @Published private(set) var logLines: [String] = []
    @Published private(set) var framesPerSecond: Double = 0

    // MARK: Spectrum output
    //
    // Deliberately NOT @Published on this object. This class publishes a dozen
    // diagnostics values; if the renderer observed the class it would redraw the
    // spectrum every time a counter moved. `SpectrumDisplay` carries only the
    // frame, and only when the drawn values change.
    let spectrumDisplay: SpectrumDisplay

    /// The newest analysed frame, for diagnostics and tests.
    var spectrum: SpectrumFrame { spectrumDisplay.frame }

    // MARK: Published - FFT diagnostics

    @Published private(set) var fftMilliseconds: Double = 0
    @Published private(set) var displayFramesPerSecond: Double = 0
    @Published private(set) var overflowCount: Int = 0
    @Published private(set) var analysisSettings: SpectrumSettings

    /// Which signal to listen to.
    @Published var source: AudioCaptureSource = .musicApp {
        didSet {
            guard oldValue != source else { return }
            restart()
        }
    }

    // MARK: Cadence

    private static let supervisorInterval: TimeInterval = 1.0
    /// Peak-hold decay time constant, so the hold is frame-rate independent.
    private static let peakHoldDecayTau: TimeInterval = 1.2
    /// How long without a callback before the state is considered not-active.
    private static let callbackSilenceGrace: TimeInterval = 0.4
    private static let tapRetryInterval: TimeInterval = 1.5
    private static let maximumLogLines = 200

    private let musicBundleID = "com.apple.Music"

    // MARK: Internals

    private let engine: AudioAnalysisEngine
    private let counter = TapCallbackCounter()
    private let analysisQueue = DispatchQueue(label: "com.musichud.audio.analysis", qos: .userInitiated)
    /// Tap creation runs here, never on the main thread.
    ///
    /// MEASURED REASON: `AudioHardwareCreateProcessTap` and aggregate-device
    /// creation can block for tens of seconds while coreaudiod waits for the
    /// IO context to become ready — the system log shows
    /// "Starting tap after waiting for writers" between registration and start,
    /// observed at 23.9 s and 36.7 s in different runs. Doing that inline froze
    /// the whole HUD. The setup is therefore asynchronous and the UI stays live.
    private let tapSetupQueue = DispatchQueue(label: "com.musichud.audio.tap-setup", qos: .userInitiated)
    /// Incremented on every attempt so a slow setup that finishes late is
    /// discarded instead of resurrecting a tap the user already moved past.
    private var tapGeneration = 0
    /// True while a tap is being built off the main thread, so the supervisor
    /// does not start a second one on top of it.
    private var isSettingUpTap = false

    private var analysisTimer: DispatchSourceTimer?
    private var supervisorTimer: DispatchSourceTimer?
    private var capture: CoreAudioTapCapture?

    private var isRunning = false
    private var deviceStarted = false
    /// Set when `AudioDeviceStart` actually returns, whatever the result.
    ///
    /// Distinguished from `deviceStarted` because the two mean different things:
    /// a start that never returns is the signature of a blocked permission
    /// prompt (measured at ~90 s in Phase 3), whereas a start that returns but
    /// yields no buffers just means the tapped app is not producing audio yet.
    /// Conflating them produced a false "PERMISSION DENIED" badge on a perfectly
    /// authorised system while coreaudiod was "waiting for writers".
    private var deviceStartReturned = false
    private var deviceStartDeadline: Date?
    private var lastTapAttemptAt: Date?
    private var lastCallbackAt: Date?
    private var everReceivedPCM = false

    /// Consecutive taps that started but never delivered a single buffer.
    ///
    /// Phase 7 finding: a tap can register with coreaudiod, have
    /// `AudioDeviceStart` return, and then simply never deliver audio, while the
    /// source is demonstrably playing. Because `attemptTapIfDue` is guarded by
    /// `capture == nil`, the app used to sit in `.idle` for ever when that
    /// happened. A bounded, backed-off rebuild is the minimal recovery.
    private var silentTapAttempts = 0
    /// When the current tap's device finished starting. `nil` until then.
    private var deviceStartedAt: Date?

    private var framesSinceSupervisor = 0
    private var framesPublishedSinceSecond = 0
    private var lastSupervisorAt: Date?
    private var lastPeakHoldUpdateAt: Date?
    private var frameRate: Int = 60
    private var startedAt: Date?

    // MARK: - Init

    init(settings: SpectrumSettings = SpectrumSettings(), frameRate: Int = 60) {
        self.analysisSettings = settings
        self.frameRate = frameRate
        self.engine = AudioAnalysisEngine(settings: settings)
        self.spectrumDisplay = SpectrumDisplay(
            initial: SpectrumFrame.silent(
                bandCount: settings.bandCount,
                sampleRate: 48000,
                fftSize: settings.fftSize
            )
        )
    }

    // MARK: - Settings

    /// Applies new DSP settings, rebuilding the analyser only when something
    /// that affects it actually changed.
    func apply(spectrumSettings: SpectrumSettings, frameRate: Int) {
        let settings = spectrumSettings.sanitized()
        let rate = min(max(frameRate, 15), 120)
        let rateChanged = rate != self.frameRate

        if settings != analysisSettings {
            analysisSettings = settings
            engine.reconfigure(settings: settings)
            spectrumDisplay.replace(
                with: SpectrumFrame.silent(
                    bandCount: settings.bandCount,
                    sampleRate: engine.sampleRate,
                    fftSize: settings.fftSize
                )
            )
            append("Spectrum reconfigured - FFT \(settings.fftSize), hop \(settings.hopSize), "
                   + "\(settings.bandCount) bands")
        }

        if rateChanged {
            self.frameRate = rate
            append("Display frame rate set to \(rate) FPS")
            if isRunning {
                analysisTimer?.cancel()
                startAnalysisTimer()
            }
        }
    }

    // MARK: - Lifecycle

    func start() {
        guard !isRunning else { return }
        isRunning = true
        startedAt = Date()
        append("Starting capture (source: \(source.rawValue))")
        beginTap()
        startAnalysisTimer()
        startSupervisorTimer()
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        analysisTimer?.cancel(); analysisTimer = nil
        supervisorTimer?.cancel(); supervisorTimer = nil
        capture?.stop()
        capture = nil
        deviceStarted = false
        deviceStartDeadline = nil
        lastCallbackAt = nil
        framesPerSecond = 0
        framesSinceSupervisor = 0
        framesPublishedSinceSecond = 0
        lastSupervisorAt = nil
        state = .stopped
        level = nil
        peakHold = 0
        format = nil
        engine.reset()
        spectrumDisplay.replace(
            with: SpectrumFrame.silent(
                bandCount: analysisSettings.bandCount,
                sampleRate: engine.sampleRate,
                fftSize: analysisSettings.fftSize
            )
        )
        append("Stopped")
    }

    func restart() {
        guard isRunning else { return }
        stop()
        start()
    }

    // MARK: - Tap management

    private func beginTap() {
        if source == .musicApp, !isMusicAppRunning() {
            state = .idle
            statusDetail = "Music.app 未运行，启动后将自动连接"
            append("Waiting: Music.app is not running")
            return
        }

        guard CoreAudioTapCapture.isSupported else {
            state = .unsupported
            statusDetail = "本系统不支持 Core Audio Process Tap（需要 macOS 14.2 或更新版本）"
            append("Process tap unsupported on this OS version")
            return
        }

        state = .starting
        statusDetail = "正在创建 Process Tap…"
        deviceStarted = false
        deviceStartReturned = false
        lastTapAttemptAt = Date()
        deviceStartDeadline = Date().addingTimeInterval(CoreAudioTapCapture.startTimeout)

        tapGeneration += 1
        let generation = tapGeneration
        let engine = self.engine
        let counter = self.counter
        let source = self.source
        let bundleID = musicBundleID

        // Off the main thread: see `tapSetupQueue` for the measured reason.
        isSettingUpTap = true
        tapSetupQueue.async { [weak self] in
            let newCapture = CoreAudioTapCapture(engine: engine, counter: counter)
            // Must be installed BEFORE start(): start() dispatches the device
            // start asynchronously and captures this closure at that moment.
            newCapture.onDeviceStarted = { result in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { self?.handleDeviceStarted(result) }
                }
            }

            let outcome: Result<AudioStreamFormatInfo?, Error>
            do {
                try newCapture.start(source: source, musicBundleID: bundleID)
                outcome = .success(newCapture.format)
            } catch {
                outcome = .failure(error)
            }

            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.finishBeginTap(newCapture, outcome: outcome, generation: generation)
                }
            }
        }
    }

    /// Applies the result of an asynchronous tap setup. MAIN ACTOR.
    private func finishBeginTap(
        _ created: CoreAudioTapCapture,
        outcome: Result<AudioStreamFormatInfo?, Error>,
        generation: Int
    ) {
        isSettingUpTap = false

        // A newer attempt, or a stop, superseded this one.
        guard generation == tapGeneration, isRunning else {
            created.stop()
            return
        }

        switch outcome {
        case .success(let info):
            capture = created
            format = info
            targetLabel = created.targetLabel
            statusDetail = "等待 PCM…"

            if let info {
                append("Tap created - \(Int(info.sampleRate)) Hz, \(info.channelCount) ch, "
                       + "\(info.bytesPerFrame) B/frame, \(info.formatID)")
                if abs(engine.sampleRate - info.sampleRate) > 1 {
                    engine.reconfigure(settings: analysisSettings, sampleRate: info.sampleRate)
                }
            } else {
                append("Tap created (format unavailable)")
            }
            // Re-arm the device-start watchdog from the moment setup finished.
            deviceStartDeadline = Date().addingTimeInterval(CoreAudioTapCapture.startTimeout)

        case .failure(let error):
            capture = nil
            format = nil
            state = .failed
            statusDetail = "\(error)"
            append("Process tap failed: \(error)")
        }
    }

    private func handleDeviceStarted(_ outcome: Result<TimeInterval, CoreAudioTapCapture.CaptureError>) {
        switch outcome {
        case .success(let elapsed):
            deviceStarted = true
            deviceStartReturned = true
            deviceStartedAt = Date()
            deviceStartDeadline = nil
            append(String(format: "Device started (%.2fs)", elapsed))
            if state == .permissionDenied {
                state = .starting
                statusDetail = "已启动，等待 PCM…"
            }
        case .failure(let error):
            deviceStarted = false
            deviceStartReturned = true
            state = .failed
            statusDetail = "\(error)"
            append("Device start failed: \(error)")
        }
    }

    private func teardownForMissingTarget() {
        capture?.stop()
        capture = nil
        deviceStarted = false
        deviceStartReturned = false
        deviceStartedAt = nil
        deviceStartDeadline = nil
        everReceivedPCM = false
        lastCallbackAt = nil
        format = nil
        level = nil
        peakHold = 0
        engine.reset()
        state = .idle
        statusDetail = "Music.app 未运行，启动后将自动连接"
        append("Music.app went away - tap torn down")
    }

    /// How long a started tap may deliver nothing before it is replaced.
    private static let silentTapTimeout: TimeInterval = 8
    /// Maximum consecutive silent taps before the app stops rebuilding and
    /// simply reports the condition. Prevents a runaway retry loop.
    private static let maximumSilentTapAttempts = 3

    /// The single place that decides whether to build a tap. Both timers call
    /// it, so they cannot race each other into back-to-back tap creations.
    private func attemptTapIfDue() {
        guard isRunning, !isSettingUpTap, isMusicAppRunning() else { return }

        // Recovery path: a tap exists and its device is running, but nothing has
        // ever arrived. The policy lives in `TapRecoveryDecision` so it can be
        // tested; this only carries it out.
        switch TapRecoveryDecision.action(
            tapExists: capture != nil,
            deviceStarted: deviceStarted,
            everReceivedPCM: everReceivedPCM,
            startedAt: deviceStartedAt,
            now: Date(),
            timeout: Self.silentTapTimeout,
            attempts: silentTapAttempts,
            maximumAttempts: Self.maximumSilentTapAttempts
        ) {
        case .wait:
            break
        case .rebuild:
            silentTapAttempts += 1
            append("Tap started but delivered no PCM after "
                   + String(format: "%.0fs", Self.silentTapTimeout)
                   + " - rebuilding (attempt \(silentTapAttempts)/\(Self.maximumSilentTapAttempts))")
            teardownForMissingTarget()
            lastTapAttemptAt = nil
            return
        case .giveUp:
            if state != .idle {
                // Say so plainly rather than retrying for ever.
                state = .idle
                statusDetail = "音频设备已就绪，但音源未提供数据（已重试 "
                    + "\(Self.maximumSilentTapAttempts) 次）"
            }
            return
        }

        guard capture == nil else { return }
        if let last = lastTapAttemptAt, Date().timeIntervalSince(last) < Self.tapRetryInterval {
            return
        }
        append("Music.app is running again - creating tap")
        beginTap()
    }

    private func isMusicAppRunning() -> Bool {
        !NSWorkspace.shared.runningApplications
            .filter { $0.bundleIdentifier == musicBundleID }
            .isEmpty
    }

    // MARK: - Analysis loop

    private func startAnalysisTimer() {
        let rate = frameRate
        let engine = self.engine
        let counter = self.counter

        var lastAnalysisAt: UInt64?
        let timer = DispatchSource.makeTimerSource(queue: analysisQueue)
        timer.schedule(
            deadline: .now(),
            repeating: 1.0 / Double(rate),
            leeway: .milliseconds(2)
        )
        timer.setEventHandler { [weak self] in
            // ANALYSIS THREAD
            let callbacks = counter.drain()

            let started = DispatchTime.now()
            let now = started.uptimeNanoseconds
            let dt = lastAnalysisAt == nil
                ? 1.0 / Double(rate)
                : Double(now - lastAnalysisAt!) / 1_000_000_000
            lastAnalysisAt = now
            let fftsRun = engine.processAvailable(maximumFFTs: 4, deltaTime: dt)
            // Decay only when nothing arrived *and* nothing is buffered: a tick
            // that merely fell between hops must not dip the display.
            if fftsRun == 0, engine.bufferedSampleCount == 0 {
                engine.decay(deltaTime: dt)
            }
            let elapsed = Double(DispatchTime.now().uptimeNanoseconds - started.uptimeNanoseconds) / 1_000_000

            let frame = engine.makeFrame(isReceivingAudio: callbacks.callbacks > 0)
            let overflow = engine.overflowCount

            self?.publish(frame: frame, callbacks: callbacks, milliseconds: elapsed, overflow: overflow)
        }
        timer.resume()
        analysisTimer = timer
    }

    private func startSupervisorTimer() {
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(
            deadline: .now() + Self.supervisorInterval,
            repeating: Self.supervisorInterval,
            leeway: .milliseconds(100)
        )
        timer.setEventHandler { [weak self] in self?.supervisorTick() }
        timer.resume()
        supervisorTimer = timer
    }

    /// Runs on the analysis queue, then hops to the main actor to publish.
    private nonisolated func publish(
        frame: SpectrumFrame,
        callbacks: TapCallbackCounter.Drain,
        milliseconds: Double,
        overflow: Int
    ) {
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                self?.apply(
                    frame: frame,
                    callbacks: callbacks,
                    milliseconds: milliseconds,
                    overflow: overflow
                )
            }
        }
    }

    // MARK: - Main actor: apply a finished frame

    private func apply(
        frame: SpectrumFrame,
        callbacks: TapCallbackCounter.Drain,
        milliseconds: Double,
        overflow: Int
    ) {
        let now = Date()

        // `spectrumDisplay.update` publishes only when the *drawn* values change.
        //
        // Phase 4.5 audit finding: `makeFrame` stamps every frame with
        // `timestamp: .now`, so two frames were never equal and the publish fired
        // on every tick — 30 times a second, forever, even with no audio arriving
        // and no window showing the result. Instruments measured that alone at
        // ~6.6% CPU on an invisible window with no tap created at all.
        if spectrumDisplay.update(frame) {
            framesPublishedSinceSecond += 1
        }

        // Diagnostics-only values, guarded for the same reason: the panels that
        // read them are usually closed, and republishing identical numbers is
        // pure overhead.
        if abs(milliseconds - fftMilliseconds) > 0.005 { fftMilliseconds = milliseconds }
        if overflow != overflowCount { overflowCount = overflow }

        let dt = lastPeakHoldUpdateAt.map { now.timeIntervalSince($0) } ?? (1.0 / Double(frameRate))
        lastPeakHoldUpdateAt = now

        if callbacks.callbacks > 0 {
            lastCallbackAt = now
            everReceivedPCM = true
            // A tap that delivers is a good tap: clear the back-off so a later
            // failure gets a full set of attempts again.
            silentTapAttempts = 0
            framesSinceSupervisor += callbacks.frames

            let level = AudioLevel(
                rms: frame.rms,
                peak: frame.peak,
                sampleRate: format?.sampleRate ?? frame.sampleRate,
                channelCount: format?.channelCount ?? 2,
                frameCount: callbacks.frames,
                timestamp: frame.timestamp
            )
            // Republish only when the reading moves. `AudioLevel` embeds a
            // timestamp, so comparing whole values would always differ.
            if self.level?.rms != level.rms || self.level?.peak != level.peak {
                self.level = level
            }

            // Assigned only on a real transition.
            //
            // Same defect class as the spectrum publish: these are `@Published`,
            // and they are mirrored into `AppState.captureState`, which the whole
            // HUD observes. Writing `.silent` thirty times a second while it was
            // already `.silent` re-rendered the entire card — Instruments showed
            // ~3.5% CPU in SwiftUI's AttributeGraph with the window hidden and
            // the music paused.
            let nextState: AudioCaptureState = frame.peak > 0 ? .receiving : .silent
            let nextDetail = frame.peak > 0
                ? ""
                : "已收到 PCM，但全部为 0（音源静音）"
            if state != nextState { state = nextState }
            if statusDetail != nextDetail { statusDetail = nextDetail }
        } else if let last = lastCallbackAt,
                  now.timeIntervalSince(last) > Self.callbackSilenceGrace {
            lastCallbackAt = nil
            level = nil
            if deviceStarted {
                state = .idle
                statusDetail = everReceivedPCM
                    ? "当前没有音频数据（音源已停止或未播放）"
                    : "尚未收到 PCM"
            }
        }

        if let deadline = deviceStartDeadline, !deviceStartReturned, now >= deadline {
            // `AudioDeviceStart` has not come back yet.
            //
            // It is tempting to call this "permission denied", and an earlier
            // version did — which produced a scary false badge on a fully
            // authorised system. Both a blocked permission prompt and
            // coreaudiod "waiting for writers" block this same call, and there
            // is no in-process signal that separates them: the tap is created
            // successfully in both cases, with no OSStatus error. So the state
            // stays `.starting` and the message names both possibilities
            // instead of asserting one.
            deviceStartDeadline = nil
            statusDetail = "音频设备启动较慢。可能是系统音频录制权限未授予，"
                + "或音源当前没有输出音频。可在「系统设置 → 隐私与安全性」中确认权限。"
            append("AudioDeviceStart has not returned after "
                   + String(format: "%.0fs", CoreAudioTapCapture.startTimeout)
                   + " - still starting (permission, or a busy audio device)")
        } else if deviceStartReturned, !deviceStarted {
            // Start returned, so this is not a permission problem.
            state = .failed
        } else if deviceStarted, callbacks.callbacks == 0,
                  lastCallbackAt == nil,
                  now.timeIntervalSince(lastTapAttemptAt ?? now) > CoreAudioTapCapture.startTimeout {
            // The device is running but the tapped app is not producing audio.
            // This is the "waiting for writers" case, not a permission problem.
            state = .idle
            statusDetail = "音频设备已就绪，正在等待音源输出"
        }

        // Frame-rate independent peak-hold decay, republished only on a visible
        // change (0.001 of full scale is far below one pixel of meter travel).
        let decay = exp(-dt / Self.peakHoldDecayTau)
        let nextPeakHold = max(spectrum.peak, peakHold * Float(decay))
        if abs(nextPeakHold - peakHold) > 0.001 { peakHold = nextPeakHold }
    }

    // MARK: - Supervisor

    private func supervisorTick() {
        let now = Date()

        if source == .musicApp {
            if !isMusicAppRunning(), capture != nil {
                teardownForMissingTarget()
            } else {
                attemptTapIfDue()
            }
        }

        if let last = lastSupervisorAt {
            let elapsed = now.timeIntervalSince(last)
            if elapsed > 0.1 {
                framesPerSecond = Double(framesSinceSupervisor) / elapsed
                displayFramesPerSecond = Double(framesPublishedSinceSecond) / elapsed
            }
        }
        lastSupervisorAt = now
        framesSinceSupervisor = 0
        framesPublishedSinceSecond = 0

        // One summary per second, never per callback.
        if let level, state.isActive {
            append(String(
                format: "[%@] rms=%.4f (%.1f dBFS) peak=%.4f (%.1f dBFS) topBand=%.3f fft=%.2fms",
                state.badgeText,
                level.rms, level.rmsDecibels,
                level.peak, level.peakDecibels,
                spectrum.bands.max() ?? 0,
                fftMilliseconds
            ))
        } else {
            append("[\(state.badgeText)] no active PCM - \(statusDetail.isEmpty ? "waiting" : statusDetail)")
        }
    }

    // MARK: - Diagnostics log

    private static let logFileHandle: FileHandle? = {
        guard let path = ProcessInfo.processInfo.environment["MUSICHUD_AUDIO_LOG"],
              !path.isEmpty else { return nil }
        FileManager.default.createFile(atPath: path, contents: nil)
        return FileHandle(forWritingAtPath: path)
    }()

    private func append(_ message: String) {
        if startedAt == nil { startedAt = Date() }
        let elapsed = startedAt.map { Date().timeIntervalSince($0) } ?? 0
        let line = String(format: "[%6.2fs] %@", elapsed, message)

        print("[AUDIO] \(line)")
        fflush(stdout)

        if let handle = Self.logFileHandle {
            handle.write(Data(("[AUDIO] " + line + "\n").utf8))
        }

        logLines.append(line)
        if logLines.count > Self.maximumLogLines {
            logLines.removeFirst(logLines.count - Self.maximumLogLines)
        }
    }

    func clearLog() {
        logLines.removeAll()
    }
}
