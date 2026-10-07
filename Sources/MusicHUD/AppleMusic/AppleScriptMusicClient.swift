import AppKit
import Foundation
import MusicHUDCore

/// Reads Music.app over **public Apple Events**, using `NSAppleScript`.
///
/// ## Why AppleScript and not the alternatives
///
/// * `MPNowPlayingInfoCenter` cannot help. It reports only the *calling* app's
///   own now-playing session; there is no public API to read another app's.
/// * MediaRemote would work but is a private framework and is explicitly out of
///   scope for this project.
/// * Scripting Music.app is the supported, documented route, and every property
///   used here exists in the app's own scripting dictionary.
///
/// The dictionary was dumped from the installed app rather than assumed:
/// `sdef /System/Applications/Music.app` confirms `player state` (`ePlS`),
/// `current track`, `player position`, and the `track` properties `name`,
/// `artist`, `album`, `duration`, `persistent ID`; the `artwork` class exposes
/// `data` as a `picture`. The transport commands `playpause`, `next track` and
/// `previous track` are all present.
///
/// ## Why `NSAppleScript` and not `osascript`
///
/// Spawning an `osascript` process per poll would burn CPU, add latency and
/// churn process table entries. `NSAppleScript` runs in-process, and because
/// the script is compiled **once** and reused, a metadata poll measures at
/// well under a millisecond of scripting overhead after the first call.
///
/// ## Threading
///
/// `NSAppleScript` is not thread-safe: one instance must not be used from two
/// threads at once, and a slow Music.app must not be allowed to stall the main
/// thread. All execution is therefore confined to a single serial queue. The
/// public methods are safe to call from anywhere — off-queue calls are
/// forwarded with `queue.sync`, though the provider always calls on-queue so
/// the synchronous path never actually blocks in practice.
/// `@unchecked Sendable`: every mutable member — the cached `NSAppleScript`
/// instances — is confined to `queue`, and `onScriptingQueue` enforces that on
/// every entry point. The compiler cannot see that invariant, so it is
/// asserted here rather than left implicit.
final class AppleScriptMusicClient: MusicClient, @unchecked Sendable {

    static let musicBundleIdentifier = "com.apple.Music"

    /// Marker used inside the scripts when Music.app is not running, so the
    /// script can bail out without launching it.
    private static let notRunningSentinel = "__MUSIC_NOT_RUNNING__"

    /// Serial queue that owns every `NSAppleScript` instance.
    let queue = DispatchQueue(label: "com.musichud.music.scripting", qos: .utility)

    private static let queueKey = DispatchSpecificKey<UInt8>()
    private static let queueKeyValue: UInt8 = 1

    // Compiled once, reused. Compilation is the expensive part of the first
    // call (~170 ms); steady-state execution is sub-millisecond.
    private var metadataScript: NSAppleScript?
    private var artworkScript: NSAppleScript?
    private var transportScripts: [MusicTransportCommand: NSAppleScript] = [:]

    init() {
        queue.setSpecific(key: Self.queueKey, value: Self.queueKeyValue)
    }

    // MARK: - Queue plumbing

    /// Runs `work` on the scripting queue, hopping over only when needed.
    private func onScriptingQueue<T>(_ work: () throws -> T) rethrows -> T {
        if DispatchQueue.getSpecific(key: Self.queueKey) != nil {
            return try work()
        }
        return try queue.sync(execute: work)
    }

    // MARK: - MusicClient

    /// Cheap, permission-free, and — importantly — does **not** launch Music.app.
    ///
    /// `tell application "Music"` would start Music.app as a side effect, so the
    /// running check must never be done with an Apple Event. `NSRunningApplication`
    /// is public AppKit API and answers without contacting the app at all.
    func isMusicAppRunning() -> Bool {
        !NSRunningApplication
            .runningApplications(withBundleIdentifier: Self.musicBundleIdentifier)
            .isEmpty
    }

    func fetchSnapshot() throws -> MusicRawSnapshot {
        try onScriptingQueue {
            // Primary guard. The script repeats the check internally to close
            // the race where Music.app quits between this line and the event.
            guard isMusicAppRunning() else { throw MusicClientError.musicAppNotRunning }

            let script = try compiledMetadataScript()
            var error: NSDictionary?
            let result = script.executeAndReturnError(&error)
            if let error {
                throw MusicClientError.fromAppleScriptError(error)
            }
            return try AppleEventDecoding.decodeSnapshot(
                result,
                notRunningSentinel: Self.notRunningSentinel
            )
        }
    }

    func fetchArtworkData() throws -> Data? {
        try onScriptingQueue {
            guard isMusicAppRunning() else { throw MusicClientError.musicAppNotRunning }

            let script = try compiledArtworkScript()
            var error: NSDictionary?
            let result = script.executeAndReturnError(&error)
            if let error {
                throw MusicClientError.fromAppleScriptError(error)
            }

            // An empty or `missing value` descriptor means "this track has no
            // artwork". Distinguishing that from an error lets the caller cache
            // the absence instead of re-asking every poll.
            guard result.descriptorType != AppleEventDecoding.OSType.missing else { return nil }
            let data = result.data
            return data.isEmpty ? nil : data
        }
    }

    func send(_ command: MusicTransportCommand) throws {
        try onScriptingQueue {
            guard isMusicAppRunning() else { throw MusicClientError.musicAppNotRunning }

            let script = try compiledTransportScript(for: command)
            var error: NSDictionary?
            _ = script.executeAndReturnError(&error)
            if let error {
                throw MusicClientError.fromAppleScriptError(error)
            }
        }
    }

    // MARK: - Scripts

    private func compiledMetadataScript() throws -> NSAppleScript {
        if let metadataScript { return metadataScript }
        let script = try compile(Self.metadataSource, label: "metadata")
        metadataScript = script
        return script
    }

    private func compiledArtworkScript() throws -> NSAppleScript {
        if let artworkScript { return artworkScript }
        let script = try compile(Self.artworkSource, label: "artwork")
        artworkScript = script
        return script
    }

    private func compiledTransportScript(for command: MusicTransportCommand) throws -> NSAppleScript {
        if let existing = transportScripts[command] { return existing }

        let source = """
        if application "Music" is not running then return "\(Self.notRunningSentinel)"
        tell application "Music" to \(command.appleScriptStatement)
        return "ok"
        """
        let script = try compile(source, label: "transport:\(command.rawValue)")
        transportScripts[command] = script
        return script
    }

    private func compile(_ source: String, label: String) throws -> NSAppleScript {
        guard let script = NSAppleScript(source: source) else {
            throw MusicClientError.unexpectedResult("failed to compile \(label) script")
        }
        return script
    }

    /// One Apple Event round trip returning every metadata field.
    ///
    /// Written defensively: every property read sits in its own `try`, because
    /// Music.app legitimately returns `missing value` for fields such as
    /// `artist` on some media kinds, and one missing field must not lose the
    /// whole reading.
    private static let metadataSource = """
    if application "Music" is not running then return {"\(notRunningSentinel)", false, "", "", "", 0, 0, "", 0}
    tell application "Music"
        set stateText to "stopped"
        try
            set stateText to (player state as text)
        end try

        set hasTrack to false
        set theTitle to ""
        set theArtist to ""
        set theAlbum to ""
        set theDuration to 0
        set theID to ""
        set artworkCount to 0

        try
            set theTrack to current track
            if theTrack is not missing value then
                set hasTrack to true
                try
                    set theTitle to (name of theTrack)
                end try
                try
                    set theArtist to (artist of theTrack)
                end try
                try
                    set theAlbum to (album of theTrack)
                end try
                try
                    set theDuration to (duration of theTrack)
                end try
                try
                    set theID to (persistent ID of theTrack)
                end try
                try
                    set artworkCount to (count of artworks of theTrack)
                end try
            end if
        end try

        set thePosition to 0
        try
            set thePosition to (player position)
        end try

        return {stateText, hasTrack, theTitle, theArtist, theAlbum, theDuration, thePosition, theID, artworkCount}
    end tell
    """

    private static let artworkSource = """
    if application "Music" is not running then return missing value
    tell application "Music"
        try
            set theTrack to current track
            if theTrack is missing value then return missing value
            if (count of artworks of theTrack) is 0 then return missing value
            return data of artwork 1 of theTrack
        on error
            return missing value
        end try
    end tell
    """

    // MARK: - Decoding

}
