import AppKit
import MusicHUDCore
import SwiftUI

/// The settings panel.
///
/// Kept out of the way of the HUD itself. Every control here is wired to real
/// behaviour — the settings object is the same one the live panel reads from,
/// and each change is applied to the window immediately.
///
/// Anything that cannot work yet is simply absent rather than shown greyed out
/// and inert. The 状态 tab records what is implemented, what is verified and
/// what is still pending.
///
/// The tab strip is a plain segmented `Picker` rather than a `TabView`. On
/// macOS, `TabView` promotes its tab bar into the hosting window's toolbar,
/// which lands outside the content view and away from the layout this view
/// controls. A `Picker` keeps the navigation inside the view, so it is always
/// visible and always where the layout says it is.
struct SettingsView: View {
    @ObservedObject var app: AppState

    @State private var tab: SettingsTab = SettingsTab.initialFromEnvironment

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                ForEach(SettingsTab.allCases) { tab in
                    Text(L(app, tab.localizationKey)).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, 12)

            Divider()

            // Each tab supplies its own ScrollView and padding.
            Group {
                switch tab {
                case .general:
                    GeneralTab(app: app)
                case .music:
                    MusicTab(app: app)
                case .appearance:
                    AppearanceTab(settings: $app.settings)
                case .visualizer:
                    VisualizerTab(settings: $app.settings)
                case .clock:
                    ClockTab(settings: $app.settings, app: app)
                case .window:
                    WindowTab(app: app)
                case .status:
                    StatusTab(app: app)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            // Several tab views hold only a settings binding, not the app state,
            // so they would not otherwise re-evaluate when the language changes.
            // Tying identity to the language rebuilds the page once.
            .id(app.language)
        }
        .frame(width: 520, height: 470)
    }
}

/// The settings sections, as a plain enum so the strip is fully in our control.
enum SettingsTab: String, CaseIterable, Identifiable {
    case general
    case music
    case appearance
    case visualizer
    case clock
    case window
    case status

    var id: String { rawValue }

    /// Localisation key; the view resolves it so the language setting applies.
    var localizationKey: String {
        switch self {
        case .general: return "settings.general.title"
        case .music: return "settings.tab.music"
        case .appearance: return "settings.tab.appearance"
        case .visualizer: return "settings.tab.spectrum"
        case .clock: return "settings.tab.clock"
        case .window: return "settings.tab.window"
        case .status: return "settings.tab.status"
        }
    }

    /// Lets the snapshot tool render a specific tab. Development aid only.
    static var initialFromEnvironment: SettingsTab {
        guard let raw = ProcessInfo.processInfo.environment["MUSICHUD_SNAPSHOT_TAB"],
              let tab = SettingsTab(rawValue: raw)
        else { return .general }
        return tab
    }
}

// MARK: - Music

/// The Music tab: where now-playing data comes from, and whether it is
/// actually arriving.
private struct MusicTab: View {
    @ObservedObject var app: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SettingsSection(title: L("settings.music.dataSource")) {
                    HStack(spacing: 10) {
                        Text(L("settings.status.source"))
                            .frame(width: 108, alignment: .leading)
                        Picker("", selection: $app.settings.dataSource) {
                            ForEach(MusicDataSource.allCases) { source in
                                Text(L(source.localizationKey)).tag(source)
                            }
                        }
                        .labelsHidden()
                    }

                    Text(L("settings.music.appleMusicDetail2"))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                SettingsSection(title: L("settings.music.pollInterval")) {
                    SliderRow(
                        title: L("settings.music.pollGroup"),
                        value: $app.settings.metadataPollInterval,
                        range: 0.5...5.0,
                        format: { String(format: "%.1f s", $0) }
                    )

                    Text(L("settings.music.interpolationNote"))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                SettingsSection(title: L(app, "settings.status.nowPlaying")) {
                    StatusLine(
                        label: L(app, "settings.status.music"),
                        value: L(app, app.availability.localizationKey)
                    )
                    StatusLine(
                        label: L(app, "settings.status.nowPlaying"),
                        value: musicStateText(app)
                    )
                }
            }
            .padding(18)
        }
    }

    private func availabilityText(_ app: AppState) -> String {
        switch app.availability {
        case .unknown: return L(app, "status.reading")
        case .ready: return L(app, "status.ready")
        case .noTrack: return L(app, "status.noTrack")
        case .musicAppNotRunning: return L(app, "hud.musicNotRunning")
        case .accessRequired: return L(app, "availability.accessRequired")
        case .failed: return L(app, "availability.failed")
        }
    }

}

// MARK: - Appearance

private struct AppearanceTab: View {
    @Binding var settings: HUDSettings

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SettingsSection(title: L("settings.appearance.glass")) {
                    SliderRow(title: L("settings.window.opacity"), value: $settings.windowOpacity, range: 0.2...1.0)
                    SliderRow(title: L("settings.appearance.blur"), value: $settings.blurStrength, range: 0...1)
                    SliderRow(title: L("settings.appearance.tint"), value: $settings.panelTint, range: 0...0.8)
                    SliderRow(title: L("settings.appearance.cornerRadius"), value: $settings.cornerRadius, range: 0...44, format: { String(format: "%.0f pt", $0) })
                }

                SettingsSection(title: L("settings.clock.displayGroup")) {
                    ToggleRow(title: L("settings.appearance.artwork"), isOn: $settings.showArtwork)
                    ToggleRow(title: L("settings.appearance.trackInfo"), isOn: $settings.showTrackInfo)
                    ToggleRow(title: L("settings.appearance.detailList"), isOn: $settings.showDetailList)
                    ToggleRow(title: L("settings.appearance.transport"), isOn: $settings.showTransport)
                    ToggleRow(title: L("settings.appearance.badges"), isOn: $settings.showStatusCaptions)
                }
            }
            .padding(18)
        }
    }
}

// MARK: - Visualizer

private struct VisualizerTab: View {
    @Binding var settings: HUDSettings

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SettingsSection(title: L("settings.spectrum.title")) {
                    HStack(spacing: 10) {
                        Text(L("settings.spectrum.fftSize"))
                            .frame(width: 108, alignment: .leading)
                        Picker("", selection: $settings.spectrumFFTSize) {
                            ForEach(SpectrumSettings.allowedFFTSizes, id: \.self) { size in
                                Text("\(size)").tag(size)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                    }

                    SliderRow(
                        title: L("settings.spectrum.bandCount"),
                        value: Binding(
                            get: { Double(settings.spectrumBarCount) },
                            set: { settings.spectrumBarCount = Int($0.rounded()) }
                        ),
                        range: 16...96,
                        format: { String(format: "%.0f", $0) }
                    )

                    Text(L("settings.spectrum.binningNote"))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                SettingsSection(title: L("settings.spectrum.sensitivityGroup")) {
                    SliderRow(
                        title: L("settings.spectrum.sensitivity"),
                        value: $settings.spectrumSensitivityDecibels,
                        range: -20...20,
                        format: { String(format: "%+.1f dB", $0) }
                    )
                    SliderRow(
                        title: L("settings.spectrum.noiseFloor"),
                        value: $settings.spectrumNoiseFloorDecibels,
                        range: -110...(-30),
                        format: { String(format: "%.0f dB", $0) }
                    )
                    SliderRow(title: L("settings.spectrum.smoothing"), value: $settings.spectrumSmoothing, range: 0...1)

                    Text(L("settings.spectrum.smoothingNote"))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                SettingsSection(title: L("settings.spectrum.appearanceGroup")) {
                    HStack(spacing: 10) {
                        Text(L("settings.spectrum.tint"))
                            .frame(width: 108, alignment: .leading)
                        Picker("", selection: $settings.spectrumTint) {
                            ForEach(SpectrumTint.allCases) { tint in
                                Text(L(tint.localizationKey)).tag(tint)
                            }
                        }
                        .labelsHidden()
                    }

                    HStack(spacing: 10) {
                        Text(L("settings.spectrum.frameRate"))
                            .frame(width: 108, alignment: .leading)
                        Picker("", selection: $settings.spectrumFrameRate) {
                            Text("20 FPS").tag(20)
                            Text("30 FPS").tag(30)
                            Text("60 FPS").tag(60)
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                    }

                    Text(L("settings.spectrum.frameRateNote"))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(18)
        }
    }
}

// MARK: - Clock

private struct ClockTab: View {
    @Binding var settings: HUDSettings
    @ObservedObject var app: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SettingsSection(title: L("settings.clock.displayGroup")) {
                    HStack(spacing: 10) {
                        Text(L("settings.clock.displayMode"))
                            .frame(width: 108, alignment: .leading)
                        Picker("", selection: $settings.clockMode) {
                            ForEach(ClockMode.allCases) { mode in
                                Text(L(mode.localizationKey)).tag(mode)
                            }
                        }
                        .labelsHidden()
                    }

                    if settings.clockMode == .timeZoneTime {
                        HStack(spacing: 10) {
                            Text(L("settings.clock.timeZone"))
                                .frame(width: 108, alignment: .leading)
                            Picker("", selection: $settings.timeZoneIdentifier) {
                                ForEach(Self.timeZoneChoices, id: \.identifier) { zone in
                                    Text(zone.label).tag(zone.identifier)
                                }
                            }
                            .labelsHidden()
                        }
                    }
                }

                SettingsSection(title: L("settings.clock.worldClock")) {
                    Text(L("settings.clock.worldClockNote"))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    ForEach(Array(app.worldClockCities.enumerated()), id: \.element.id) { index, city in
                        HStack(spacing: 8) {
                            Toggle("", isOn: Binding(
                                get: { city.isEnabled },
                                set: { newValue in
                                    var cities = app.worldClockCities
                                    cities[index].isEnabled = newValue
                                    app.setWorldClockCities(cities)
                                }
                            ))
                            .labelsHidden()
                            .toggleStyle(.checkbox)

                            Text(city.displayName)
                                .font(.system(size: 11, design: .monospaced))
                                .frame(width: 104, alignment: .leading)

                            Text(city.shortTimeZoneName(at: Date()))
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(width: 46, alignment: .leading)

                            Text(city.timeString(at: Date()))
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)

                            Spacer()

                            Button {
                                move(in: index, by: -1)
                            } label: { Image(systemName: "arrow.up") }
                                .buttonStyle(.borderless)
                                .disabled(index == 0)

                            Button {
                                move(in: index, by: 1)
                            } label: { Image(systemName: "arrow.down") }
                                .buttonStyle(.borderless)
                                .disabled(index == app.worldClockCities.count - 1)

                            Button {
                                var cities = app.worldClockCities
                                cities.remove(at: index)
                                app.setWorldClockCities(cities)
                            } label: { Image(systemName: "minus.circle") }
                                .buttonStyle(.borderless)
                        }
                    }

                    HStack(spacing: 8) {
                        Menu(L("settings.clock.addCity")) {
                            ForEach(availableToAdd, id: \.timeZoneIdentifier) { city in
                                Button("\(city.displayName) · \(city.shortTimeZoneName(at: Date()))") {
                                    app.setWorldClockCities(app.worldClockCities + [city])
                                }
                            }
                        }
                        .frame(width: 150)

                        Spacer()

                        Button(L("settings.clock.restoreDefaults")) {
                            app.setWorldClockCities(WorldClockCatalogue.defaults)
                        }
                    }
                }

                SettingsSection(title: L("settings.clock.digitStyle")) {
                    HStack(spacing: 10) {
                        Text(L("settings.clock.fontStyle"))
                            .frame(width: 108, alignment: .leading)
                        Picker("", selection: $settings.clockStyle) {
                            ForEach(ClockStyle.allCases) { style in
                                Text(L(style.localizationKey)).tag(style)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                    }

                    SliderRow(title: L("settings.clock.digitSize"), value: $settings.clockScale, range: 0.6...1.4)

                    ToggleRow(title: L("settings.clock.ghostSegments"), isOn: $settings.showGhostSegments)

                    HStack(spacing: 10) {
                        Text(L("settings.clock.customCaption"))
                            .frame(width: 108, alignment: .leading)
                        TextField(L("settings.clock.customCaptionPlaceholder"), text: $settings.clockCaptionOverride)
                            .textFieldStyle(.roundedBorder)
                    }
                }
            }
            .padding(18)
        }
    }

    /// Cities not yet in the list, so the menu cannot offer duplicates.
    private var availableToAdd: [WorldClockCity] {
        let configured = Set(app.worldClockCities.map(\.timeZoneIdentifier))
        return WorldClockCatalogue.all.filter { !configured.contains($0.timeZoneIdentifier) }
    }

    /// Moves one entry, clamping at the ends.
    private func move(in index: Int, by offset: Int) {
        var cities = app.worldClockCities
        let target = index + offset
        guard cities.indices.contains(index), cities.indices.contains(target) else { return }
        cities.swapAt(index, target)
        app.setWorldClockCities(cities)
    }

    /// A short, practical list rather than every zone on the planet.
    private static let timeZoneChoices: [(identifier: String, label: String)] = [
        (TimeZone.current.identifier, String(format: L("settings.clock.autoTimeZone"), HUDTimeFormatter.timeZoneName(TimeZone.current.identifier))),
        ("America/Los_Angeles", L("city.losAngeles")),
        ("America/New_York", L("city.newYork")),
        ("Europe/London", L("city.london")),
        ("Europe/Berlin", L("city.berlin")),
        ("Asia/Shanghai", L("city.shanghai")),
        ("Asia/Tokyo", L("city.tokyo")),
        ("UTC", "UTC"),
    ]
}

// MARK: - Window

private struct WindowTab: View {
    @ObservedObject var app: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SettingsSection(title: L("settings.window.levelGroup")) {
                    Picker("", selection: $app.settings.windowLevelMode) {
                        ForEach(WindowLevelMode.allCases) { mode in
                            Text(L(mode.localizationKey)).tag(mode)
                        }
                    }
                    .labelsHidden()

                    Text(app.settings.windowLevelMode.explanation)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                SettingsSection(title: L("settings.window.behaviour")) {
                    ToggleRow(title: L("settings.window.showOnLaunch"), isOn: $app.settings.showOnLaunch)
                    ToggleRow(title: L("settings.window.rememberFrame"), isOn: $app.settings.rememberWindowFrame)
                    ToggleRow(
                        title: L("settings.window.clickThrough"),
                        isOn: Binding(
                            get: { app.settings.clickThrough },
                            set: { app.setClickThrough($0) }
                        )
                    )

                    Text(L("settings.window.clickThroughNote"))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                SettingsSection(title: L("settings.window.position")) {
                    HStack {
                        Button(L("settings.window.resetToCorner")) {
                            app.resetWindowPosition()
                        }
                        Spacer()
                        Button(L("settings.window.resetDefaults")) {
                            app.restoreDefaultSettings()
                        }
                    }

                    Text(L("settings.window.resetNote"))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(18)
        }
    }
}

// MARK: - Status

private struct StatusTab: View {
    @ObservedObject var app: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SettingsSection(title: L(app, "settings.status.nowPlaying")) {
                    StatusLine(label: L(app, "settings.status.music"),
                               value: musicStateText(app))
                    StatusLine(label: L(app, "settings.status.audioCapture"),
                               value: L(app, app.captureState.localizationKey))
                    StatusLine(label: L(app, "settings.status.source"),
                               value: L(app, app.snapshot.source.localizationKey))
                }

                SettingsSection(title: L(app, "settings.tab.spectrum")) {
                    StatusLine(
                        label: L(app, "settings.status.fft"),
                        value: String(
                            format: L(app, "settings.status.fftFormat"),
                            app.audio.analysisSettings.fftSize,
                            app.audio.analysisSettings.hopSize
                        )
                    )
                    StatusLine(label: L(app, "settings.status.bands"),
                               value: "\(app.audio.analysisSettings.bandCount)")
                    StatusLine(label: L(app, "settings.status.sampleRate"),
                               value: String(format: "%.0f Hz", app.audio.spectrum.sampleRate))
                    StatusLine(label: L(app, "settings.status.fftTime"),
                               value: String(format: "%.2f ms", app.audio.fftMilliseconds))
                    StatusLine(label: L(app, "settings.status.uiFps"),
                               value: String(format: "%.0f FPS", app.audio.displayFramesPerSecond))
                    StatusLine(label: L(app, "settings.status.overflow"),
                               value: "\(app.audio.overflowCount)")
                }

                SettingsSection(title: L(app, "settings.tab.music")) {
                    if !app.availability.isAvailable {
                        Text(L(app, "settings.status.permissionHelp"))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        if app.availability.offersSettingsButton {
                            Button(L(app, "hud.transport.openSettings")) {
                                app.openAutomationSettings()
                            }
                        }
                    } else {
                        Text(L(app, "settings.status.permissionGranted"))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

            }
            .padding(18)
        }
    }


private func availabilityTextLegacy(_ availability: MusicAvailability) -> String {
        switch availability {
        case .unknown: return L("status.reading")
        case .ready: return L("status.ready")
        case .noTrack: return L("status.noTrack")
        case .musicAppNotRunning: return L("hud.musicNotRunning")
        case .accessRequired: return L("availability.accessRequired")
        case .failed(let message): return String(format: L("availability.failed"), message)
        }
    }
}

// MARK: - Reusable rows

// MARK: - General

/// Language and launch-at-login.
///
/// Both are app-wide rather than per-HUD, which is why they get their own page
/// instead of being buried in 外观 or 窗口.
private struct GeneralTab: View {
    @ObservedObject var app: AppState

    /// Live status read from macOS, refreshed whenever the page appears and
    /// after every change. Never a cached bool — the user can flip the login
    /// item in System Settings behind the app's back.
    @State private var loginStatus: LaunchAtLogin.Status = LaunchAtLogin.status

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SettingsSection(title: L(app, "settings.language.title")) {
                    Picker("", selection: Binding(
                        get: { app.language },
                        set: { app.setLanguage($0) }
                    )) {
                        ForEach(AppLanguage.allCases) { language in
                            Text(language.endonym).tag(language)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    Text(L(app, "settings.language.restartHint"))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                SettingsSection(title: L(app, "settings.launchAtLogin.title")) {
                    Toggle(L(app, "settings.launchAtLogin.title"), isOn: Binding(
                        get: { loginStatus.isOn },
                        set: { desired in
                            loginStatus = LaunchAtLogin.setEnabled(desired)
                        }
                    ))

                    Text(L(app, "settings.launchAtLogin.detail"))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    StatusLine(
                        label: L(app, "settings.launchAtLogin.title"),
                        value: loginStatusText
                    )

                    // macOS sometimes accepts the registration but still wants
                    // the user to confirm it. Say so, and give them a way there.
                    if loginStatus == .requiresApproval {
                        Text(L(app, "settings.launchAtLogin.approvalHint"))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if loginStatus == .requiresApproval || loginStatus == .notFound {
                        Button(L(app, "settings.launchAtLogin.openSystemSettings")) {
                            LaunchAtLogin.openSystemSettings()
                        }
                    }
                }
            }
            .padding(18)
        }
        .onAppear { loginStatus = LaunchAtLogin.status }
    }

    private var loginStatusText: String {
        switch loginStatus {
        case .enabled: return L(app, "settings.launchAtLogin.registered")
        case .disabled: return L(app, "settings.launchAtLogin.notRegistered")
        case .requiresApproval: return L(app, "settings.launchAtLogin.requiresApproval")
        case .notFound: return L(app, "settings.launchAtLogin.notFound")
        case .failed(let message):
            return String(format: L(app, "settings.launchAtLogin.failed"), message)
        }
    }
}

/// Playback state as a localised string. Shared by the Music and Status tabs,
/// which both report it.
@MainActor
private func musicStateText(_ app: AppState) -> String {
    switch app.snapshot.state {
    case .playing: return L(app, "settings.status.playing")
    case .paused: return L(app, "settings.status.paused")
    case .stopped: return L(app, "settings.status.stopped")
    }
}

private struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var format: (Double) -> String = { String(format: "%.2f", $0) }

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .frame(width: 108, alignment: .leading)
            Slider(value: $value, in: range)
            Text(format(value))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 54, alignment: .trailing)
        }
    }
}

private struct ToggleRow: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(title, isOn: $isOn)
            .toggleStyle(.switch)
            .controlSize(.small)
    }
}

private struct StatusLine: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 11, design: .monospaced))
        }
        .font(.system(size: 11))
    }
}
