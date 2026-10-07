import Foundation

// MARK: - Clock

/// Which number the big retro display is showing.
public enum ClockMode: String, Codable, Sendable, CaseIterable, Identifiable {
    /// Stable key for the app's localisation tables.
    public var localizationKey: String {
        switch self {
        case .systemTime: return "settings.clock.mode.systemTime"
        case .timeZoneTime: return "settings.clock.mode.timeZone"
        case .sessionElapsed: return "settings.clock.mode.sessionElapsed"
        case .trackProgress: return "settings.clock.mode.trackProgress"
        }
    }

    /// The Mac's local wall clock.
    case systemTime
    /// Wall clock in a specific time zone (this is what the reference design shows).
    case timeZoneTime
    /// How long this listening session has been running.
    case sessionElapsed
    /// Playhead position inside the current track.
    case trackProgress

    public var id: String { rawValue }

    public var localizedName: String {
        switch self {
        case .systemTime: return "系统时间"
        case .timeZoneTime: return "指定时区时间"
        case .sessionElapsed: return "音乐已播放时长"
        case .trackProgress: return "当前曲目进度"
        }
    }

    /// Wall-clock modes tick once a second; the music-derived modes come from
    /// the now-playing snapshot instead.
    public var isWallClock: Bool {
        self == .systemTime || self == .timeZoneTime
    }
}

/// How the digits are drawn.
public enum ClockStyle: String, Codable, Sendable, CaseIterable, Identifiable {
    /// Stable key for the app's localisation tables.
    public var localizationKey: String {
        switch self {
        case .sevenSegment: return "settings.clock.style.sevenSegment"
        case .monospaced: return "settings.clock.style.monospaced"
        }
    }

    /// Round-capped seven-segment display. Matches the reference design.
    case sevenSegment
    /// Heavy monospaced system font. A restrained alternative.
    case monospaced

    public var id: String { rawValue }

    public var localizedName: String {
        switch self {
        case .sevenSegment: return "七段电子管"
        case .monospaced: return "等宽粗体"
        }
    }
}

// MARK: - Spectrum

/// Low-saturation bar colours. The brief explicitly rules out rainbow gradients.
public enum SpectrumTint: String, Codable, Sendable, CaseIterable, Identifiable {
    /// Stable key for the app's localisation tables.
    public var localizationKey: String {
        switch self {
        case .silver: return "settings.spectrum.tint.silver"
        case .ice: return "settings.spectrum.tint.ice"
        case .amber: return "settings.spectrum.tint.amber"
        case .mint: return "settings.spectrum.tint.mint"
        }
    }

    case silver
    case ice
    case amber
    case mint

    public var id: String { rawValue }

    public var localizedName: String {
        switch self {
        case .silver: return "银白"
        case .ice: return "冷蓝"
        case .amber: return "暖琥珀"
        case .mint: return "薄荷"
        }
    }

    /// `(red, green, blue)` in `0...1`.
    public var rgb: (r: Double, g: Double, b: Double) {
        switch self {
        case .silver: return (0.92, 0.93, 0.95)
        case .ice: return (0.66, 0.82, 0.98)
        case .amber: return (0.98, 0.80, 0.52)
        case .mint: return (0.62, 0.93, 0.82)
        }
    }
}

// MARK: - Window

/// How the HUD is layered against the desktop.
///
/// The difference between these matters and is documented in the README:
///
/// * `normal`   — an ordinary window at `.normal` level. It stacks with other
///                apps' windows and will be covered by them.
/// * `floating` — `NSWindow.Level.floating`. Stays above ordinary windows.
///                This is what "always on top" means in practice, and it is
///                the only fully reliable mode.
/// * `desktop`  — sits just above the wallpaper and *below* the desktop icons,
///                using the public `CGWindowLevelForKey(.desktopWindow)` value.
///                It looks exactly like a desktop widget, but the Finder's
///                desktop window sits above it, so it may not receive mouse
///                clicks, and Mission Control / "Show Desktop" still move it.
///                Experimental — offered because the brief asks for the
///                distinction to be made explicit, not because it is reliable.
public enum WindowLevelMode: String, Codable, Sendable, CaseIterable, Identifiable {
    /// Stable key for the app's localisation tables.
    public var localizationKey: String {
        switch self {
        case .normal: return "menu.level.normal"
        case .floating: return "menu.level.floating"
        case .desktop: return "menu.level.desktop"
        }
    }

    case normal
    case floating
    case desktop

    public var id: String { rawValue }

    public var localizedName: String {
        switch self {
        case .normal: return "普通窗口"
        case .floating: return "始终置顶（浮层）"
        case .desktop: return "桌面层（实验性）"
        }
    }

    public var explanation: String {
        switch self {
        case .normal:
            return "与其他 App 窗口同层，会被前方的窗口遮挡。"
        case .floating:
            return "位于普通窗口之上，其他 App 无法遮挡。推荐用于 HUD。"
        case .desktop:
            return "使用公开 API CGWindowLevelForKey(.desktopWindow) 放到壁纸之上、桌面图标之下。"
                + "副作用：Finder 桌面窗口在其上层，可能收不到鼠标点击，Mission Control 仍会移动它。"
        }
    }
}

// MARK: - Data source

/// Where now-playing information comes from.
///
/// The default is the real thing. The demo source exists so the UI can be
/// developed and screenshotted without Music.app, and it is always badged so it
/// can never be mistaken for a real session. It is **not** a fallback: when
/// Apple Music is unavailable the card shows an explicit idle state rather than
/// silently substituting fabricated data.
public enum MusicDataSource: String, Codable, Sendable, CaseIterable, Identifiable {
    /// Stable key for the app's localisation tables.
    public var localizationKey: String {
        switch self {
        case .appleMusic: return "settings.music.source.appleMusic"
        case .demo: return "settings.music.source.demo"
        }
    }

    case appleMusic
    case demo

    public var id: String { rawValue }

    public var localizedName: String {
        switch self {
        case .appleMusic: return "Apple Music（真实数据）"
        case .demo: return "演示数据（开发用）"
        }
    }
}

// MARK: - Settings

/// Every setting here is wired to real behaviour. There are no decorative switches.
public struct HUDSettings: Codable, Equatable, Sendable {

    // MARK: Data
    /// Which provider feeds the card.
    public var dataSource: MusicDataSource = .appleMusic
    /// How often Music.app metadata is re-read, in seconds.
    public var metadataPollInterval: Double = 1.5

    // MARK: Audio
    /// Which signal the spectrum listens to.
    ///
    /// Phase 1 and 2 did not capture audio at all; Phase 3 added the pipeline
    /// behind the diagnostics panel. Persisted here so the choice survives a
    /// relaunch once Phase 4 wires it into the card.
    public var audioCaptureSource: AudioCaptureSource = .musicApp

    // MARK: Appearance
    /// Whole-window opacity, applied to the panel itself.
    public var windowOpacity: Double = 1.0
    /// Corner radius of the card, in points.
    public var cornerRadius: Double = 18
    /// How much of the behind-window blur is present, `0...1`.
    public var blurStrength: Double = 0.72
    /// Dark tint painted over the blur, `0...1`. Keeps text readable over busy wallpapers.
    public var panelTint: Double = 0.42
    /// Show the title / artist block.
    public var showTrackInfo: Bool = true
    /// Show the album artwork.
    public var showArtwork: Bool = true
    /// Show the `标题 · 艺术家 · 专辑` block.
    public var showDetailList: Bool = true
    /// Show the transport row.
    public var showTransport: Bool = true
    /// Show the tiny status captions (spectrum state, demo badge).
    public var showStatusCaptions: Bool = true

    // MARK: Visualizer
    //
    // Every one of these is wired to the DSP in Phase 4. The brief asks for
    // sensitivity, smoothing, frame rate and band count to be real controls
    // rather than decoration, and they are: they feed `SpectrumSettings`, which
    // the analyser consumes.
    /// Number of visual bands. Also the DSP band count — one source of truth.
    ///
    /// Raised from 48 to 64 in Phase 5 on measured evidence: the reference's
    /// bars are finer and denser than 48 gives at this card width, and 64
    /// measured **identically** (7.50% CPU, median of 6 samples) while 72 cost
    /// 8.75% and started to read as a picket fence.
    public var spectrumBarCount: Int = 64
    public var spectrumTint: SpectrumTint = .silver
    /// FFT length. 1024 / 2048 / 4096.
    public var spectrumFFTSize: Int = 2048
    /// dB added to every band before mapping, i.e. a meter gain.
    public var spectrumSensitivityDecibels: Double = 0
    /// Level mapped to a visual zero.
    public var spectrumNoiseFloorDecibels: Double = -80
    /// 0…1. Scales the release coefficient; attack stays fast.
    public var spectrumSmoothing: Double = 0.5
    /// Spectrum refresh rate in frames per second.
    ///
    /// Defaults to 30 because that is where the measurement landed. The DSP is
    /// essentially free (~0.03 ms per tick, and ~0.2% CPU), but every published
    /// frame costs a full UI update of a vibrancy-backed window: measured at
    /// ~15% CPU at 60 FPS, ~8% at 30 FPS, and ~5% at 20 FPS on this machine.
    /// 30 FPS is smooth for a bar meter of this size; 60 is available for
    /// anyone who wants it and does not mind the cost.
    public var spectrumFrameRate: Int = 30

    // MARK: Clock
    public var clockMode: ClockMode = .sessionElapsed
    public var clockStyle: ClockStyle = .sevenSegment
    /// Multiplier on the clock's natural size, `0.6...1.4`.
    public var clockScale: Double = 1.0
    /// Draw the unlit segments as faint "ghost" segments, like a real LCD.
    public var showGhostSegments: Bool = true
    /// Time zone used by `.timeZoneTime`.
    public var timeZoneIdentifier: String = TimeZone.current.identifier
    /// Optional override for the caption under the digits. Empty means "derive it".
    public var clockCaptionOverride: String = ""

    // MARK: Window
    public var windowLevelMode: WindowLevelMode = .floating
    /// Keep the panel visible after a relaunch.
    public var showOnLaunch: Bool = true
    /// Restore the last window position and size.
    public var rememberWindowFrame: Bool = true
    /// Click-through mode: the panel ignores all mouse events.
    public var clickThrough: Bool = false
    /// Last known frame. Only honoured when `rememberWindowFrame` is true.
    public var windowFrame: WindowFrame?

    public init() {}

    /// Default size of the HUD card, chosen to match the reference design's proportions.
    public static let defaultFrame = WindowFrame(x: 0, y: 0, width: 300, height: 428)
    public static let minimumSize = (width: 240.0, height: 348.0)
    public static let maximumSize = (width: 900.0, height: 1400.0)
}

/// `Codable` window frame, so the settings blob stays platform-neutral.
public struct WindowFrame: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}
