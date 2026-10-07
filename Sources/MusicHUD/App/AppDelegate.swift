import AppKit
import Combine
import MusicHUDCore
import SwiftUI

/// Application lifecycle and the status-bar menu.
///
/// The menu is not decoration: with `.accessory` activation policy there is no
/// Dock icon, and the HUD has no title bar, so this is the only way to quit,
/// hide the panel, change its layering or escape click-through mode.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {

    private var state: AppState!
    private var hudController: HUDWindowController!
    private var statusItem: NSStatusItem!
    private var settingsWindow: NSWindow?
    private var diagnosticsWindow: NSWindow?
    /// Retained only while a development trace is running.
    private var tracer: StateTracer?
    private var audioSourceSink: AnyCancellable?

    // MARK: Audio
    //
    // The capture + analysis pipeline lives in `AppState` so the HUD, the
    // settings panel and the diagnostics panel all read the same thing. It is
    // started when the HUD is shown, because from Phase 4 the spectrum is a real
    // feature of the card rather than a diagnostics-only experiment.
    private var audioService: AudioCaptureService { state.audio }

    func applicationDidFinishLaunching(_ notification: Notification) {
        state = AppState()
        hudController = HUDWindowController(state: state)
        setUpStatusItem()

        if state.settings.showOnLaunch {
            hudController.showHUD()
        }

        // Start the spectrum pipeline. Deferred to the next run loop turn so the
        // first frame renders before the Core Audio round trip begins.
        DispatchQueue.main.async { [weak self] in
            self?.state.startAudioCapture()
        }

        // Persist the chosen audio source as it changes.
        audioSourceSink = state.audio.$source
            .dropFirst()
            .sink { [weak self] source in
                self?.state.settings.audioCaptureSource = source
            }

        applySnapshotClockModeIfRequested()

        scheduleSnapshotIfRequested()
        scheduleTraceIfRequested()
        scheduleAudioDiagnosticsCaptureIfRequested()
    }

    // MARK: - Audio diagnostics capture (development)

    /// `MUSICHUD_AUDIO_DIAGNOSTICS=<path>` opens the diagnostics panel, waits
    /// for real audio to be flowing, renders it to a PNG, and exits.
    ///
    /// The wait is deliberate: a snapshot taken immediately would show an empty
    /// meter and prove nothing about whether capture works.
    private func scheduleAudioDiagnosticsCaptureIfRequested() {
        guard let path = ProcessInfo.processInfo.environment["MUSICHUD_AUDIO_DIAGNOSTICS"],
              !path.isEmpty else { return }

        let wait = TimeInterval(ProcessInfo.processInfo.environment["MUSICHUD_AUDIO_DIAGNOSTICS_WAIT"] ?? "")
            ?? 6

        // Deferred for the same reason as above: keep the launch notification
        // short and let the first frame render before doing capture work.
        DispatchQueue.main.async { [weak self] in
            self?.openAudioDiagnostics()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + wait) { [weak self] in
            guard let self, let window = self.diagnosticsWindow,
                  let view = window.contentView else {
                self?.report("audio diagnostics snapshot failed: no window")
                NSApp.terminate(nil)
                return
            }
            window.display()
            self.report(ViewSnapshotter.writeSnapshot(of: view, to: path))
            self.audioService.stop()
            NSApp.terminate(nil)
        }
    }

    // MARK: - Development trace

    /// Records live state to a file for the duration, then exits.
    ///
    /// See `StateTracer` for why a screenshot is not enough to verify the
    /// pausing and resuming behaviour.
    private func scheduleTraceIfRequested() {
        guard let path = StateTracer.requestedOutputPath else { return }
        let duration = StateTracer.requestedDuration
        let tracer = StateTracer(path: path)
        self.tracer = tracer
        tracer.start(state: state, duration: duration) {
            NSApp.terminate(nil)
        }
    }

    // MARK: - Development snapshot

    /// If `MUSICHUD_SNAPSHOT` is set, render the card to that path and exit.
    /// `MUSICHUD_SNAPSHOT_SETTINGS` additionally renders the settings window.
    ///
    /// This exists because screen capture is not always available or
    /// trustworthy — see `ViewSnapshotter` for the details. It is a developer
    /// tool and has no effect during normal use.
    private func scheduleSnapshotIfRequested() {
        guard let path = ViewSnapshotter.requestedOutputPath else { return }
        let settingsPath = ViewSnapshotter.requestedSettingsPath

        // Wait long enough for the first layout pass, and — since Phase 4 —
        // for the process tap to start and real FFT frames to arrive. Snapping
        // at 1.2 s would capture an empty spectrum and prove nothing.
        let snapshotDelay = TimeInterval(
            ProcessInfo.processInfo.environment["MUSICHUD_SNAPSHOT_WAIT"] ?? ""
        ) ?? 6

        // `MUSICHUD_SNAPSHOT_ON_AUDIO=1` waits for real FFT data instead of a
        // fixed delay. Tap start-up varies from 0.07 s to tens of seconds
        // depending on coreaudiod, so a fixed delay would sometimes capture an
        // empty spectrum and prove nothing.
        let waitForAudio = ProcessInfo.processInfo.environment["MUSICHUD_SNAPSHOT_ON_AUDIO"] == "1"
        var delay = snapshotDelay
        if waitForAudio {
            let deadline = Date().addingTimeInterval(snapshotDelay)
            while Date() < deadline, self.state.captureState != .receiving {
                RunLoop.current.run(until: Date().addingTimeInterval(0.1))
            }
            // A short settle once audio is flowing, not the whole timeout: the
            // point is to let a few FFT frames land so the bars are not empty.
            delay = 0.8
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, let hudWindow = self.hudController.window,
                  let view = hudWindow.contentView else {
                self?.report("snapshot failed: no content view")
                NSApp.terminate(nil)
                return
            }

            // Force a synchronous display first. Without this, text layers can
            // still be pending their first rasterisation and come out blank —
            // which looks exactly like a broken layout and is very misleading.
            hudWindow.display()
            self.report(ViewSnapshotter.writeSnapshot(of: view, to: path, backdrop: true))

            guard let settingsPath else {
                NSApp.terminate(nil)
                return
            }

            self.openSettings()

            // The settings window needs its own turn to lay out and draw.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                guard let self else { return }
                if let settingsWindow = self.settingsWindow,
                   let settingsView = settingsWindow.contentView {
                    // Text layers in a freshly created SwiftUI window can still
                    // be pending their first rasterisation. A single `display()`
                    // captures whatever has been committed so far, which is
                    // intermittently an empty page — every label missing while the
                    // controls are present. Forcing layout, then spinning the run
                    // loop so the layer commits, then displaying again makes the
                    // capture deterministic.
                    for _ in 0..<3 {
                        settingsWindow.layoutIfNeeded()
                        settingsView.layoutSubtreeIfNeeded()
                        settingsWindow.displayIfNeeded()
                        RunLoop.current.run(until: Date().addingTimeInterval(0.25))
                    }
                    settingsWindow.display()
                    self.report(ViewSnapshotter.writeSnapshot(of: settingsView, to: settingsPath))
                } else {
                    self.report("snapshot failed: no settings window")
                }
                NSApp.terminate(nil)
            }
        }
    }

    /// Snapshot-only: pins the large display to one mode so each clock state
    /// can be captured without a human clicking through the rotation.
    ///
    /// Accepts `track`, `tokyo`, `london`, `new-york`, `los-angeles`, or any
    /// IANA identifier such as `Asia/Tokyo`.
    private func applySnapshotClockModeIfRequested() {
        guard let raw = ProcessInfo.processInfo.environment["MUSICHUD_SNAPSHOT_CLOCK"],
              !raw.isEmpty else { return }

        if raw == "track" {
            state.setClockDisplayModeForSnapshot(.track)
            return
        }

        let normalised = raw.lowercased()
        let slugged = state.worldClockCities.first { city in
            city.displayName.lowercased().replacingOccurrences(of: " ", with: "-") == normalised
                || city.timeZoneIdentifier.lowercased() == normalised
        }
        if let city = slugged {
            state.setClockDisplayModeForSnapshot(.worldClock(city))
            return
        }

        report("snapshot: unknown clock mode \(raw)")
    }

    private func report(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    /// Click-through mode can be turned off from the menu, so closing the panel
    /// must not quit the app.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    // MARK: - Status item

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Music HUD")
            image?.isTemplate = true
            button.image = image
            button.toolTip = "Music HUD"
        }

        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        // Re-read Music.app whenever the user comes back to the app. Opening
        // the menu is the moment they are most likely to want current data, and
        // it costs one Apple Event.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidBecomeActive),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    @objc private func applicationDidBecomeActive() {
        state?.refreshNowPlaying()
    }

    /// Rebuilt every time the menu opens so the check marks are never stale.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        menu.addItem(menuItem(
            title: L(state, hudController.isVisible ? "menu.hide" : "menu.show"),
            action: #selector(toggleVisibility)
        ))

        menu.addItem(.separator())

        let levelHeader = NSMenuItem(title: L(state, "menu.windowLevel"), action: nil, keyEquivalent: "")
        levelHeader.isEnabled = false
        menu.addItem(levelHeader)

        for mode in WindowLevelMode.allCases {
            let item = menuItem(title: "  " + L(state, mode.localizationKey), action: #selector(setWindowLevel(_:)))
            item.representedObject = mode.rawValue
            item.state = state.settings.windowLevelMode == mode ? .on : .off
            menu.addItem(item)
        }

        menu.addItem(.separator())

        let clickThrough = menuItem(title: L(state, "menu.clickThrough"), action: #selector(toggleClickThrough))
        clickThrough.state = state.settings.clickThrough ? .on : .off
        menu.addItem(clickThrough)

        menu.addItem(menuItem(title: L(state, "menu.resetPosition"), action: #selector(resetPosition)))

        menu.addItem(.separator())

        menu.addItem(menuItem(title: L(state, "menu.settings"), action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(menuItem(title: L(state, "menu.diagnostics"), action: #selector(openAudioDiagnostics), keyEquivalent: "d"))

        menu.addItem(.separator())

        let sourceItem = NSMenuItem(
            title: String(format: L(state, "menu.source"), L(state, state.snapshot.source.localizationKey)),
            action: nil,
            keyEquivalent: ""
        )
        sourceItem.isEnabled = false
        menu.addItem(sourceItem)

        // Built from the version in Info.plist rather than a literal, so it
        // cannot go stale again — the previous text still claimed "Phase 1 ·
        // 静态 UI 原型" six phases later.
        let versionItem = NSMenuItem(
            title: String(format: L(state, "menu.version"), AppInfo.displayVersion),
            action: nil,
            keyEquivalent: ""
        )
        versionItem.isEnabled = false
        menu.addItem(versionItem)

        menu.addItem(.separator())

        menu.addItem(menuItem(title: L(state, "menu.quit"), action: #selector(quit), keyEquivalent: "q"))
    }

    private func menuItem(title: String, action: Selector, keyEquivalent: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        return item
    }

    // MARK: - Menu actions

    @objc private func toggleVisibility() {
        hudController.toggleVisibility()
    }

    @objc private func setWindowLevel(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let mode = WindowLevelMode(rawValue: raw) else { return }
        state.settings.windowLevelMode = mode

        // The desktop layer sits below the Finder's desktop window, so warn the
        // user rather than leaving them with an unclickable panel.
        if mode == .desktop {
            let alert = NSAlert()
            alert.messageText = L(state, "menu.level.desktopAlertTitle")
            alert.informativeText = """
            面板现在位于壁纸之上、桌面图标之下。

            这是通过公开 API CGWindowLevelForKey(.desktopWindow) 实现的，并非私有 API，但 Finder 的桌面窗口位于其上，因此：
            · 面板可能收不到鼠标点击，按钮与拖动可能失效；
            · 仍会随 Mission Control / 显示桌面移动。

            随时可以从该菜单切回「始终置顶（浮层）」。
            """
            alert.alertStyle = .informational
            alert.addButton(withTitle: L(state, "common.ok"))
            alert.runModal()
        }
    }

    @objc private func toggleClickThrough() {
        state.toggleClickThrough()
    }

    @objc private func resetPosition() {
        hudController.resetPosition()
        hudController.bringToFrontWithoutActivating()
    }

    /// Opens the Phase 3 diagnostics panel. Capture starts here and stops when
    /// the window closes, so the permission is only exercised on demand.
    @objc private func openAudioDiagnostics() {
        if diagnosticsWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 580, height: 660),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Music HUD · Audio Diagnostics"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: AudioDiagnosticsView(service: audioService))
            window.center()
            diagnosticsWindow = window
        }

        audioService.source = state.settings.audioCaptureSource

        NSApp.activate(ignoringOtherApps: true)
        diagnosticsWindow?.makeKeyAndOrderFront(nil)

        // Capture is already running for the HUD; the panel just observes it.
        // Closing the panel must not stop the spectrum.
        DispatchQueue.main.async { [weak self] in
            self?.state.startAudioCapture()
        }
    }

    @objc private func openSettings() {
        if settingsWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 520, height: 470),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = L(state, "settings.windowTitle")
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: SettingsView(app: state))
            window.center()
            settingsWindow = window
        }

        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
