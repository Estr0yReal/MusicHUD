import Foundation

/// Where the spectrum should listen.
///
/// The brief is explicit that tapping Music.app is preferred over capturing the
/// whole system, because a HUD for Apple Music has no business visualising
/// Chrome, Discord, system alert sounds or games. Both are offered because
/// system-wide capture is the fallback when a per-process tap cannot be built.
public enum AudioCaptureSource: String, Codable, Sendable, CaseIterable, Identifiable {
    /// Tap only Music.app's own output.
    case musicApp
    /// Tap everything the system is playing, excluding this app.
    case systemOutput

    public var id: String { rawValue }

    public var localizedName: String {
        switch self {
        case .musicApp: return "Music.app 进程"
        case .systemOutput: return "系统输出（全部）"
        }
    }

    public var explanation: String {
        switch self {
        case .musicApp:
            return "只捕获「音乐」App 的输出，不会把浏览器、通知音或其他 App 的声音画进频谱。"
        case .systemOutput:
            return "捕获系统全部输出（排除本应用）。若无法针对 Music.app 建立 tap，可用此项兜底。"
        }
    }
}
