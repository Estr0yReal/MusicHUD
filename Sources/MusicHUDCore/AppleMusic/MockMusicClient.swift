import Foundation

/// A scriptable `MusicClient` for tests and previews.
///
/// This is what lets `swift test` run in an environment with no Music.app, no
/// Automation permission and no Apple Events at all: the provider is exercised
/// against this instead of the real scripting client, so the tests assert on
/// the provider's logic rather than on macOS.
/// `@unchecked Sendable`: the mutable configuration properties are written by
/// the test before the provider reads them and never mutated concurrently. The
/// conformance exists to satisfy `MusicClient`, not to promise thread safety
/// beyond that.
public final class MockMusicClient: MusicClient, @unchecked Sendable {

    /// Executes `work` inline. There is no real scripting here, so there is no
    /// reason to hop queues; `queue` exists only to satisfy the protocol.
    public let queue = DispatchQueue(label: "com.musichud.music.mock")

    // MARK: Configuration

    /// What `isMusicAppRunning()` reports.
    public var isRunning: Bool = true

    /// The next snapshot `fetchSnapshot()` returns.
    public var rawSnapshot = MusicRawSnapshot(
        playerStateText: "playing",
        hasTrack: true,
        title: "Test Title",
        artist: "Test Artist",
        album: "Test Album",
        duration: 240,
        position: 10,
        persistentID: "TEST-TRACK-1"
    )

    /// The next artwork blob. `nil` means "no artwork".
    public var artwork: Data? = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x01, 0x02, 0x03])

    /// When set, the next call throws this instead of returning.
    public var errorToThrow: MusicClientError?

    // MARK: Observation

    public private(set) var fetchSnapshotCallCount = 0
    public private(set) var fetchArtworkCallCount = 0
    public private(set) var sentCommands: [MusicTransportCommand] = []

    public init() {}

    // MARK: MusicClient

    public func isMusicAppRunning() -> Bool { isRunning }

    // The real client refuses to do anything when Music.app is not running, and
    // these methods mirror that so a test cannot accidentally assert against
    // behaviour the real thing would never produce.

    public func fetchSnapshot() throws -> MusicRawSnapshot {
        fetchSnapshotCallCount += 1
        guard isRunning else { throw MusicClientError.musicAppNotRunning }
        if let errorToThrow { throw errorToThrow }
        return rawSnapshot
    }

    public func fetchArtworkData() throws -> Data? {
        fetchArtworkCallCount += 1
        guard isRunning else { throw MusicClientError.musicAppNotRunning }
        if let errorToThrow { throw errorToThrow }
        return artwork
    }

    public func send(_ command: MusicTransportCommand) throws {
        guard isRunning else { throw MusicClientError.musicAppNotRunning }
        if let errorToThrow { throw errorToThrow }
        sentCommands.append(command)
    }

    // MARK: Test helpers

    /// Convenience for driving a sequence of states in a test.
    public func setState(
        _ state: MusicPlayerState,
        title: String = "Test Title",
        artist: String = "Test Artist",
        album: String = "Test Album",
        duration: TimeInterval = 240,
        position: TimeInterval = 0,
        persistentID: String = "TEST-TRACK-1"
    ) {
        rawSnapshot = MusicRawSnapshot(
            playerStateText: state.rawValue,
            hasTrack: state != .stopped,
            title: title,
            artist: artist,
            album: album,
            duration: duration,
            position: position,
            persistentID: persistentID
        )
    }

    public func resetCallCounts() {
        fetchSnapshotCallCount = 0
        fetchArtworkCallCount = 0
        sentCommands.removeAll()
    }
}
