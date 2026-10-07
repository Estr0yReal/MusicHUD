import Foundation

/// One reading of Music.app's state, exactly as the scripting layer returns it.
///
/// This is deliberately a dumb data carrier with no interpretation: mapping it
/// onto the app's own model is `MusicRawSnapshot.interpret()` and is unit
/// tested, while the part that actually talks to Music.app stays tiny.
public struct MusicRawSnapshot: Equatable, Sendable {
    /// Raw `player state` text. Verified values on macOS 15.5:
    /// `stopped`, `playing`, `paused`, `fast forwarding`, `rewinding`.
    public var playerStateText: String
    /// `false` when `current track` is `missing value`.
    public var hasTrack: Bool
    public var title: String
    public var artist: String
    public var album: String
    /// Seconds. `0` when unavailable.
    public var duration: TimeInterval
    /// Seconds.
    public var position: TimeInterval
    /// Music.app's stable `persistent ID`, e.g. `ABC3A5D15B7A488C`.
    /// Used as the artwork cache key.
    public var persistentID: String

    public init(
        playerStateText: String = "stopped",
        hasTrack: Bool = false,
        title: String = "",
        artist: String = "",
        album: String = "",
        duration: TimeInterval = 0,
        position: TimeInterval = 0,
        persistentID: String = ""
    ) {
        self.playerStateText = playerStateText
        self.hasTrack = hasTrack
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.position = position
        self.persistentID = persistentID
    }
}

/// Music.app's player state, as reported by the `ePlS` enumeration.
public enum MusicPlayerState: String, Sendable, CaseIterable {
    case stopped
    case playing
    case paused
    case fastForwarding = "fast forwarding"
    case rewinding
    case unknown

    /// Parses the raw string. Matching is case-insensitive and tolerant of
    /// surrounding whitespace, because the value crosses a language boundary.
    public init(scriptText: String) {
        let normalised = scriptText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        self = MusicPlayerState(rawValue: normalised) ?? .unknown
    }

    /// The app's own transport state.
    public var playbackState: PlaybackState {
        switch self {
        case .playing, .fastForwarding, .rewinding:
            return .playing
        case .paused:
            return .paused
        case .stopped, .unknown:
            return .stopped
        }
    }

    /// `true` when the playhead should be moving.
    public var advancesPlayhead: Bool {
        playbackState == .playing
    }
}

public extension MusicRawSnapshot {
    var playerState: MusicPlayerState {
        MusicPlayerState(scriptText: playerStateText)
    }

    /// `true` when there is a usable track to display.
    ///
    /// A track that is merely *loaded* while the transport is stopped does not
    /// count: the brief is explicit that a stopped player shows the idle state
    /// rather than a track that looks like it is playing.
    var isDisplayable: Bool {
        hasTrack && playerState != .stopped && !title.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Converts this reading into the app's model.
    func interpret() -> (metadata: TrackMetadata?, state: PlaybackState) {
        let state = playerState.playbackState
        guard hasTrack else { return (nil, state) }

        let metadata = TrackMetadata(
            title: title,
            artist: artist,
            album: album,
            duration: duration,
            artworkSeed: 0,
            subtitle: "",
            persistentID: persistentID
        )
        return (metadata, state)
    }
}

// MARK: - Transport

/// Transport commands the scripting layer can send. All are documented
/// commands in Music.app's scripting dictionary.
public enum MusicTransportCommand: String, Sendable, CaseIterable {
    case playPause
    case nextTrack
    case previousTrack

    /// The AppleScript statement (without the `tell` wrapper).
    ///
    /// Public because the scripting client lives in the app target while the
    /// command list lives here.
    public var appleScriptStatement: String {
        switch self {
        case .playPause: return "playpause"
        case .nextTrack: return "next track"
        case .previousTrack: return "previous track"
        }
    }
}

// MARK: - Errors

/// Everything that can go wrong reading Music.app.
public enum MusicClientError: Error, Equatable, Sendable {
    /// Music.app is not running. Detected *without* Apple Events, so checking
    /// this never launches Music.app as a side effect.
    case musicAppNotRunning
    /// macOS refused the Apple Event. `errAEEventNotPermitted` (-1743) or
    /// `errAEPrivilegeError` (-10004): the user has not granted Automation
    /// access for this app to control Music.
    case accessRequired
    /// Music.app has no current track.
    case noCurrentTrack
    /// Any other AppleScript failure, with the raw code and message preserved
    /// so the UI can show something truthful rather than a generic error.
    case scriptingFailure(code: Int, message: String)
    /// The script ran but returned something we could not read.
    case unexpectedResult(String)

    /// Maps an `NSAppleScript` error dictionary onto this type.
    public static func fromAppleScriptError(_ error: NSDictionary?) -> MusicClientError {
        guard let error else { return .scriptingFailure(code: 0, message: "unknown") }

        let code = (error[NSAppleScript.errorNumber] as? Int) ?? 0
        let message = (error[NSAppleScript.errorMessage] as? String) ?? "unknown"

        switch code {
        case -1743, -10004:
            // -1743 errAEEventNotPermitted, -10004 errAEPrivilegeError.
            return .accessRequired
        case -600:
            // procNotFound
            return .musicAppNotRunning
        case -1728:
            // errAENoSuchObject — typically no current track.
            return .noCurrentTrack
        default:
            return .scriptingFailure(code: code, message: message)
        }
    }
}

// MARK: - Client

/// The narrow seam between Music.app and everything else.
///
/// Keeping this to four methods is what makes the provider testable without
/// Music.app installed or running: `MockMusicClient` implements the same
/// protocol and no test ever launches a real Apple Event.
///
/// Implementations are responsible for being cheap to call repeatedly; see
/// `AppleScriptMusicClient`, which compiles its scripts once and reuses them.
///
/// `Sendable` on purpose: a client is a handle that may be passed across
/// concurrency domains, and the `queue` requirement states exactly how it must
/// be used once it gets there. Without this, callers cannot schedule the
/// client's work off the main actor without tripping Sendable diagnostics that
/// describe a real design decision rather than a defect.
public protocol MusicClient: AnyObject, Sendable {

    /// The queue this client must be used on.
    ///
    /// Apple Event work must never run on the main thread, and `NSAppleScript`
    /// additionally requires a single serial queue because it is not
    /// thread-safe. Exposing the queue lets callers schedule work themselves
    /// instead of the client having to be internally thread-safe, which keeps
    /// the implementation honest about how it is actually used.
    var queue: DispatchQueue { get }

    /// `true` when Music.app is running.
    ///
    /// Must be implemented **without** sending an Apple Event, because
    /// `tell application "Music"` launches Music.app if it is not already
    /// running. A naive implementation would therefore make Music.app start up
    /// just because the HUD is on screen.
    ///
    /// Verified on macOS 15.5: `application "Music" is running` does not launch
    /// the app, so the scripting layer uses that as its in-script race guard,
    /// while the cheap out-of-process check uses `NSRunningApplication`.
    func isMusicAppRunning() -> Bool

    /// One round trip returning every metadata field.
    ///
    /// Deliberately a single call: six separate scripts would mean six Apple
    /// Event round trips per poll.
    func fetchSnapshot() throws -> MusicRawSnapshot

    /// Raw artwork bytes for the current track, or `nil` when there is none.
    /// Expensive relative to `fetchSnapshot`, so callers must only invoke it
    /// when the track actually changes.
    func fetchArtworkData() throws -> Data?

    /// Sends a transport command.
    func send(_ command: MusicTransportCommand) throws
}
