import Foundation

/// Whether Music.app is reachable, and if not, why.
///
/// The brief requires three distinct failure states to be told apart, because
/// they need three different responses from the user: launch Music.app, start
/// playing something, or grant Automation permission. Collapsing them into one
/// "unavailable" state would be much less useful.
public enum MusicAvailability: Equatable, Sendable {
    /// No poll has completed yet.
    case unknown
    /// Music.app is not running.
    case musicAppNotRunning
    /// macOS refused the Apple Event; the user must grant Automation access.
    case accessRequired
    /// Music.app is running but has nothing playing.
    case noTrack
    /// A track is loaded and should be displayed.
    case ready
    /// Something unexpected went wrong.
    case failed(String)

    /// Headline shown in place of the track title. `nil` while a track is up.
    public var headline: String? {
        switch self {
        case .unknown, .ready:
            return nil
        case .musicAppNotRunning:
            return "Music is not running"
        case .accessRequired:
            return "Music access required"
        case .noTrack:
            return "No music playing"
        case .failed:
            return "Music unavailable"
        }
    }

    /// Second line: what the user can actually do about it.
    public var detail: String {
        switch self {
        case .unknown:
            return "正在读取 Music.app…"
        case .musicAppNotRunning:
            return "打开 Music.app 后会自动连接"
        case .accessRequired:
            return "需要在「隐私与安全性 → 自动化」中允许 Music HUD 控制 Music"
        case .noTrack:
            return "在 Music.app 中播放任意歌曲即可"
        case .ready:
            return ""
        case .failed(let message):
            return message
        }
    }

    /// Only the permission failure gets an action button, because it is the
    /// only one the user has to fix in System Settings.
    /// Localisation key for the headline shown in place of the track title.
    public var headlineKey: String? {
        switch self {
        case .unknown, .ready: return nil
        case .musicAppNotRunning: return "musicState.notRunning.headline"
        case .accessRequired: return "musicState.accessRequired.headline"
        case .noTrack: return "musicState.noTrack.headline"
        case .failed: return "musicState.failed.headline"
        }
    }

    /// Localisation key for the second line.
    public var detailKey: String {
        switch self {
        case .unknown: return "musicState.unknown.detail"
        case .ready: return ""
        case .musicAppNotRunning: return "musicState.notRunning.detail"
        case .accessRequired: return "musicState.accessRequired.detail"
        case .noTrack: return "musicState.noTrack.detail"
        case .failed: return ""
        }
    }

    /// Stable key for the app's localisation tables.
    public var localizationKey: String {
        switch self {
        case .unknown: return "status.reading"
        case .ready: return "status.ready"
        case .noTrack: return "status.noTrack"
        case .musicAppNotRunning: return "hud.musicNotRunning"
        case .accessRequired: return "availability.accessRequired"
        case .failed: return "availability.failed"
        }
    }

    /// Whether the state means "working".
    public var isAvailable: Bool {
        if case .ready = self { return true }
        return false
    }

    public var offersSettingsButton: Bool {
        self == .accessRequired
    }

    public var isReady: Bool {
        self == .ready
    }

    /// Whether the transport buttons have anything they can act on.
    ///
    /// Only true when Music.app is running *and* we are allowed to talk to it.
    /// Pressing a button must never launch Music.app as a side effect.
    public var allowsTransportControl: Bool {
        switch self {
        case .ready, .noTrack:
            return true
        case .unknown, .musicAppNotRunning, .accessRequired, .failed:
            return false
        }
    }

    /// Whether the card should render an idle state instead of track info.
    public var showsIdleState: Bool {
        headline != nil
    }
}
