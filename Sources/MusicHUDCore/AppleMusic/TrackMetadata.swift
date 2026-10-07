import Foundation

/// Metadata describing one track, independent of where it came from.
public struct TrackMetadata: Equatable, Sendable {
    public var title: String
    public var artist: String
    public var album: String
    /// Total duration in seconds. `0` means "unknown".
    public var duration: TimeInterval
    /// A stable seed used to derive procedural placeholder artwork (demo mode only).
    public var artworkSeed: Int
    /// Optional secondary line shown under the title, e.g. a city or label.
    public var subtitle: String
    /// Music.app's stable `persistent ID`, e.g. `ABC3A5D15B7A488C`.
    ///
    /// Empty for demo data and for any source that does not supply one. Used as
    /// the artwork cache key, which is why it is preferred over artist/album/title.
    public var persistentID: String

    public init(
        title: String,
        artist: String,
        album: String,
        duration: TimeInterval,
        artworkSeed: Int = 0,
        subtitle: String = "",
        persistentID: String = ""
    ) {
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.artworkSeed = artworkSeed
        self.subtitle = subtitle
        self.persistentID = persistentID
    }

    public static let unknown = TrackMetadata(
        title: "未知曲目",
        artist: "未知艺术家",
        album: "",
        duration: 0
    )

    /// True when there is nothing meaningful to show.
    public var isEmpty: Bool {
        title.trimmingCharacters(in: .whitespaces).isEmpty
    }
}

/// Playback transport state.
public enum PlaybackState: String, Codable, Sendable, CaseIterable {
    case stopped
    case playing
    case paused

    /// `true` for anything other than `stopped`.
    public var isActive: Bool { self != .stopped }

    public var isPlaying: Bool { self == .playing }

    /// Stable key for the app's localisation tables.
    public var localizationKey: String {
        switch self {
        case .playing: return "settings.status.playing"
        case .paused: return "settings.status.paused"
        case .stopped: return "settings.status.stopped"
        }
    }

    public var localizedName: String {
        switch self {
        case .stopped: return "已停止"
        case .playing: return "播放中"
        case .paused: return "已暂停"
        }
    }
}

/// Where the current snapshot came from. Used to keep demo data honestly labelled
/// so it can never be mistaken for a real Apple Music session.
public enum PlaybackSource: String, Codable, Sendable {
    /// Stable key for the app's localisation tables.
    public var localizationKey: String {
        switch self {
        case .none: return "settings.music.source.none"
        case .appleMusic: return "settings.music.source.appleMusic"
        case .demo: return "settings.music.source.demo"
        }
    }

    /// No provider is producing data.
    case none
    /// Hard-coded demo data shipped with the Phase 1 prototype.
    case demo
    /// Live data read from Music.app (Phase 2).
    case appleMusic

    public var isDemo: Bool { self == .demo }

    public var localizedName: String {
        switch self {
        case .none: return "未连接"
        case .demo: return "演示数据"
        case .appleMusic: return "Apple Music"
        }
    }
}

/// An immutable snapshot of "what is playing right now".
public struct NowPlayingSnapshot: Equatable, Sendable {
    public var metadata: TrackMetadata?
    public var state: PlaybackState
    /// Playhead position inside the current track, in seconds.
    public var position: TimeInterval
    public var source: PlaybackSource

    public init(
        metadata: TrackMetadata? = nil,
        state: PlaybackState = .stopped,
        position: TimeInterval = 0,
        source: PlaybackSource = .none
    ) {
        self.metadata = metadata
        self.state = state
        self.position = position
        self.source = source
    }

    /// The idle state shown when nothing is playing.
    public static let idle = NowPlayingSnapshot()

    /// Playback progress in `0...1`, or `nil` when the duration is unknown.
    public var progress: Double? {
        guard let metadata, metadata.duration > 0 else { return nil }
        return min(max(position / metadata.duration, 0), 1)
    }

    /// Remaining time in the current track, or `nil` when the duration is unknown.
    public var remaining: TimeInterval? {
        guard let metadata, metadata.duration > 0 else { return nil }
        return max(metadata.duration - position, 0)
    }

    /// `true` when there is a track and it is not stopped.
    public var hasTrack: Bool {
        guard let metadata else { return false }
        return !metadata.isEmpty
    }
}
