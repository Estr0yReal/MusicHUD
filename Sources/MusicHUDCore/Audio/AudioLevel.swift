import Foundation

/// One measurement of the audio arriving from the capture backend.
///
/// Deliberately free of CoreAudio and SwiftUI types so it can be produced from
/// a real-time thread, carried across threads, and asserted on in tests.
public struct AudioLevel: Equatable, Sendable {
    /// Root mean square amplitude of the window, `0...1`.
    public let rms: Float
    /// Largest absolute sample in the window, `0...1`.
    public let peak: Float
    /// Source sample rate in Hz. `0` when unknown.
    public let sampleRate: Double
    /// Channel count of the source. `0` when unknown.
    public let channelCount: Int
    /// Frames covered by this measurement. `0` when unknown.
    public let frameCount: Int
    /// When the measurement was taken.
    public let timestamp: ContinuousClock.Instant

    public init(
        rms: Float,
        peak: Float,
        sampleRate: Double,
        channelCount: Int,
        frameCount: Int,
        timestamp: ContinuousClock.Instant
    ) {
        self.rms = rms
        self.peak = peak
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.frameCount = frameCount
        self.timestamp = timestamp
    }

    /// RMS expressed in dBFS, floored at `DecibelScale.floor`.
    public var rmsDecibels: Float { DecibelScale.decibels(fromAmplitude: rms) }

    /// Peak expressed in dBFS, floored at `DecibelScale.floor`.
    public var peakDecibels: Float { DecibelScale.decibels(fromAmplitude: peak) }

    /// `true` when every sample in the window was exactly zero.
    public var isSilent: Bool { peak == 0 }
}

/// What the capture backend produced for one reporting interval.
///
/// The distinction between `.noData` and `.silence` is the one the brief insists
/// on, and live measurement confirms both really occur and are different:
///
/// * Music.app idle → the tap produces **no callbacks at all** (`.noData`).
/// * Music.app paused mid-track → callbacks keep arriving at full rate with
///   an all-zero payload (`.silence`).
///
/// Collapsing those into one "not working" state would be wrong in both
/// directions: the first means nothing is flowing, the second means capture is
/// working perfectly and the music is simply quiet.
public enum AudioCaptureResult: Equatable, Sendable {
    /// No audio buffers arrived in this interval.
    case noData
    /// Buffers arrived but every sample was zero.
    case silence(AudioLevel)
    /// Buffers arrived with real signal.
    case audio(AudioLevel)

    public var level: AudioLevel? {
        switch self {
        case .noData: return nil
        case .silence(let level), .audio(let level): return level
        }
    }

    /// The state this result implies.
    public var state: AudioCaptureState {
        switch self {
        case .noData: return .idle
        case .silence: return .silent
        case .audio: return .receiving
        }
    }
}

/// Lifecycle of the capture pipeline.
public enum AudioCaptureState: String, Sendable, CaseIterable {
    /// Nothing has been started yet.
    case idle
    /// Creating the tap and starting the device.
    case starting
    /// Real, non-silent PCM is arriving.
    case receiving
    /// PCM is arriving but is entirely silent.
    case silent
    /// macOS refused the audio capture permission.
    case permissionDenied
    /// This machine or OS cannot do process taps.
    case unsupported
    /// Something went wrong; the associated message is shown verbatim.
    case failed
    /// Explicitly stopped by the user.
    case stopped

    public var isActive: Bool {
        self == .receiving || self == .silent
    }

    /// Stable key for the app's localisation tables.
    ///
    /// Core stays free of display text: it names the state, the app decides how
    /// to say it. `localizedName` remains for non-localised diagnostics use.
    public var localizationKey: String {
        switch self {
        case .idle: return "state.idle"
        case .starting: return "state.starting"
        case .receiving: return "state.receiving"
        case .silent: return "state.silent"
        case .permissionDenied: return "state.permissionDenied"
        case .unsupported: return "availability.unsupported"
        case .failed: return "state.failed"
        case .stopped: return "state.idle"
        }
    }

    public var localizedName: String {
        switch self {
        case .idle: return "空闲"
        case .starting: return "启动中"
        case .receiving: return "接收音频中"
        case .silent: return "静音"
        case .permissionDenied: return "权限被拒绝"
        case .unsupported: return "不支持"
        case .failed: return "失败"
        case .stopped: return "已停止"
        }
    }

    /// Short uppercase badge, matching the retro HUD style.
    public var badgeText: String {
        switch self {
        case .idle: return "IDLE"
        case .starting: return "STARTING"
        case .receiving: return "RECEIVING AUDIO"
        case .silent: return "SILENT"
        case .permissionDenied: return "PERMISSION DENIED"
        case .unsupported: return "UNSUPPORTED"
        case .failed: return "FAILED"
        case .stopped: return "STOPPED"
        }
    }
}

/// Audio stream description, for the diagnostics panel.
public struct AudioStreamFormatInfo: Equatable, Sendable {
    public let sampleRate: Double
    public let channelCount: Int
    /// Bytes per frame, as reported by the tap's `AudioStreamBasicDescription`.
    public let bytesPerFrame: Int
    /// Four-character format ID, e.g. `lpcm`.
    public let formatID: String
    public let isFloat: Bool
    public let isInterleaved: Bool

    public init(
        sampleRate: Double,
        channelCount: Int,
        bytesPerFrame: Int,
        formatID: String,
        isFloat: Bool,
        isInterleaved: Bool
    ) {
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.bytesPerFrame = bytesPerFrame
        self.formatID = formatID
        self.isFloat = isFloat
        self.isInterleaved = isInterleaved
    }
}
