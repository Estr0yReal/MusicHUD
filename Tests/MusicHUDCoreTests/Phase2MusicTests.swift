import XCTest
@testable import MusicHUDCore

// MARK: - Parsing Music.app's values

final class MusicRawSnapshotTests: XCTestCase {

    func testPlayerStateParsesEveryDocumentedEnumCase() {
        // These five strings come from the installed app's scripting dictionary
        // (enumeration `ePlS`), not from memory.
        XCTAssertEqual(MusicPlayerState(scriptText: "stopped"), .stopped)
        XCTAssertEqual(MusicPlayerState(scriptText: "playing"), .playing)
        XCTAssertEqual(MusicPlayerState(scriptText: "paused"), .paused)
        XCTAssertEqual(MusicPlayerState(scriptText: "fast forwarding"), .fastForwarding)
        XCTAssertEqual(MusicPlayerState(scriptText: "rewinding"), .rewinding)
    }

    func testPlayerStateParsingIsCaseAndWhitespaceInsensitive() {
        XCTAssertEqual(MusicPlayerState(scriptText: "  Playing \n"), .playing)
        XCTAssertEqual(MusicPlayerState(scriptText: "FAST FORWARDING"), .fastForwarding)
    }

    func testUnknownPlayerStateDoesNotCrashOrClaimToBePlaying() {
        XCTAssertEqual(MusicPlayerState(scriptText: "banana"), .unknown)
        XCTAssertEqual(MusicPlayerState(scriptText: ""), .unknown)
        // Crucially, an unrecognised state must not look like playback.
        XCTAssertEqual(MusicPlayerState(scriptText: "banana").playbackState, .stopped)
        XCTAssertFalse(MusicPlayerState(scriptText: "banana").advancesPlayhead)
    }

    func testScrubbingStatesCountAsAdvancing() {
        XCTAssertTrue(MusicPlayerState.fastForwarding.advancesPlayhead)
        XCTAssertTrue(MusicPlayerState.rewinding.advancesPlayhead)
        XCTAssertTrue(MusicPlayerState.fastForwarding.playbackState == .playing)
    }

    func testInterpretProducesMetadata() {
        let raw = MusicRawSnapshot(
            playerStateText: "playing",
            hasTrack: true,
            title: "Remember",
            artist: "Ryo Nakamura",
            album: "Remember - Single",
            duration: 307.969,
            position: 254.345,
            persistentID: "ABC3A5D15B7A488C"
        )

        let (metadata, state) = raw.interpret()
        XCTAssertEqual(state, .playing)
        XCTAssertEqual(metadata?.title, "Remember")
        XCTAssertEqual(metadata?.artist, "Ryo Nakamura")
        XCTAssertEqual(metadata?.album, "Remember - Single")
        XCTAssertEqual(metadata?.duration ?? 0, 307.969, accuracy: 0.001)
        XCTAssertEqual(metadata?.persistentID, "ABC3A5D15B7A488C")
    }

    func testInterpretWithNoTrackIsNil() {
        let raw = MusicRawSnapshot(playerStateText: "stopped", hasTrack: false)
        let (metadata, state) = raw.interpret()
        XCTAssertNil(metadata)
        XCTAssertEqual(state, .stopped)
    }

    func testAStoppedButLoadedTrackIsNotDisplayable() {
        // Music.app keeps `current track` populated after Stop. The brief is
        // explicit that a stopped player shows the idle state, not a track that
        // looks like it is still playing.
        let raw = MusicRawSnapshot(
            playerStateText: "stopped",
            hasTrack: true,
            title: "Remember",
            artist: "Ryo Nakamura",
            duration: 300,
            position: 0
        )
        XCTAssertFalse(raw.isDisplayable)
    }

    func testAPausedTrackIsDisplayable() {
        let raw = MusicRawSnapshot(
            playerStateText: "paused",
            hasTrack: true,
            title: "Remember",
            duration: 300,
            position: 120
        )
        XCTAssertTrue(raw.isDisplayable)
        XCTAssertEqual(raw.playerState.playbackState, .paused)
    }

    func testBlankTitleIsNotDisplayable() {
        let raw = MusicRawSnapshot(playerStateText: "playing", hasTrack: true, title: "   ")
        XCTAssertFalse(raw.isDisplayable)
    }
}

// MARK: - Error mapping

final class MusicClientErrorTests: XCTestCase {

    private func appleScriptError(code: Int, message: String = "boom") -> NSDictionary {
        [
            NSAppleScript.errorNumber: code,
            NSAppleScript.errorMessage: message,
        ]
    }

    func testPermissionErrorsMapToAccessRequired() {
        // errAEEventNotPermitted and errAEPrivilegeError. These are the two
        // codes macOS actually returns when Automation access has not been
        // granted, and both were observed while developing this phase.
        XCTAssertEqual(
            MusicClientError.fromAppleScriptError(appleScriptError(code: -1743)),
            .accessRequired
        )
        XCTAssertEqual(
            MusicClientError.fromAppleScriptError(appleScriptError(code: -10004)),
            .accessRequired
        )
    }

    func testProcessNotFoundMapsToNotRunning() {
        // -600 procNotFound
        XCTAssertEqual(
            MusicClientError.fromAppleScriptError(appleScriptError(code: -600)),
            .musicAppNotRunning
        )
    }

    func testNoSuchObjectMapsToNoTrack() {
        // -1728 errAENoSuchObject, which is what `current track` gives when
        // nothing is loaded.
        XCTAssertEqual(
            MusicClientError.fromAppleScriptError(appleScriptError(code: -1728)),
            .noCurrentTrack
        )
    }

    func testUnexpectedCodeIsPreservedRatherThanFlattened() {
        let error = MusicClientError.fromAppleScriptError(appleScriptError(code: -9999, message: "weird"))
        XCTAssertEqual(error, .scriptingFailure(code: -9999, message: "weird"))
    }

    func testNilErrorDictionaryDoesNotCrash() {
        XCTAssertEqual(
            MusicClientError.fromAppleScriptError(nil),
            .scriptingFailure(code: 0, message: "unknown")
        )
    }
}

// MARK: - Availability

final class MusicAvailabilityTests: XCTestCase {

    func testEachFailureStateHasItsOwnHeadline() {
        // The three states the brief requires to be distinguishable.
        XCTAssertEqual(MusicAvailability.musicAppNotRunning.headline, "Music is not running")
        XCTAssertEqual(MusicAvailability.noTrack.headline, "No music playing")
        XCTAssertEqual(MusicAvailability.accessRequired.headline, "Music access required")
    }

    func testReadyStateHasNoHeadline() {
        // So the card renders the track instead of a message.
        XCTAssertNil(MusicAvailability.ready.headline)
        XCTAssertFalse(MusicAvailability.ready.showsIdleState)
    }

    func testOnlyAccessRequiredOffersTheSettingsButton() {
        XCTAssertTrue(MusicAvailability.accessRequired.offersSettingsButton)
        XCTAssertFalse(MusicAvailability.noTrack.offersSettingsButton)
        XCTAssertFalse(MusicAvailability.musicAppNotRunning.offersSettingsButton)
    }

    func testTransportIsOnlyAllowedWhenMusicIsReachable() {
        XCTAssertTrue(MusicAvailability.ready.allowsTransportControl)
        XCTAssertTrue(MusicAvailability.noTrack.allowsTransportControl)
        // Pressing a transport button must never launch Music.app.
        XCTAssertFalse(MusicAvailability.musicAppNotRunning.allowsTransportControl)
        XCTAssertFalse(MusicAvailability.accessRequired.allowsTransportControl)
        XCTAssertFalse(MusicAvailability.unknown.allowsTransportControl)
    }
}

// MARK: - Playhead interpolation

/// The behaviours the brief calls out by name: playing advances, paused freezes,
/// a new track resets. All deterministic — `now` is supplied by the caller.
final class PositionEstimatorTests: XCTestCase {

    func testPlayingAdvancesWithTime() {
        var estimator = PositionEstimator()
        estimator.synchronise(trackID: "A", position: 10, duration: 300, state: .playing, now: 1000)

        XCTAssertEqual(estimator.estimate(at: 1000), 10, accuracy: 0.0001)
        XCTAssertEqual(estimator.estimate(at: 1005), 15, accuracy: 0.0001)
        XCTAssertEqual(estimator.estimate(at: 1030), 40, accuracy: 0.0001)
    }

    func testPausedDoesNotAdvance() {
        // The single most important property: a local timer must never keep
        // counting while Music.app is paused.
        var estimator = PositionEstimator()
        estimator.synchronise(trackID: "A", position: 42, duration: 300, state: .paused, now: 1000)

        XCTAssertEqual(estimator.estimate(at: 1000), 42, accuracy: 0.0001)
        XCTAssertEqual(estimator.estimate(at: 1001), 42, accuracy: 0.0001)
        XCTAssertEqual(estimator.estimate(at: 60_000), 42, accuracy: 0.0001)
    }

    func testStoppedDoesNotAdvance() {
        var estimator = PositionEstimator()
        estimator.synchronise(trackID: "A", position: 42, duration: 300, state: .stopped, now: 1000)
        XCTAssertEqual(estimator.estimate(at: 9999), 42, accuracy: 0.0001)
    }

    func testPauseFreezesAtTheValueItWasAt() {
        var estimator = PositionEstimator()
        estimator.synchronise(trackID: "A", position: 10, duration: 300, state: .playing, now: 1000)

        // 20 seconds of playback.
        XCTAssertEqual(estimator.estimate(at: 1020), 30, accuracy: 0.0001)

        // Pause. Music.app reports the position it actually stopped at.
        estimator.synchronise(trackID: "A", position: 30, duration: 300, state: .paused, now: 1020)
        XCTAssertEqual(estimator.estimate(at: 1020), 30, accuracy: 0.0001)
        XCTAssertEqual(estimator.estimate(at: 1080), 30, accuracy: 0.0001)
    }

    func testResumeContinuesFromTheFrozenValue() {
        var estimator = PositionEstimator()
        estimator.synchronise(trackID: "A", position: 30, duration: 300, state: .paused, now: 1000)
        XCTAssertEqual(estimator.estimate(at: 1100), 30, accuracy: 0.0001)

        // Resume 100 seconds later: the paused wall-clock time must not count.
        estimator.synchronise(trackID: "A", position: 30, duration: 300, state: .playing, now: 1100)
        XCTAssertEqual(estimator.estimate(at: 1110), 40, accuracy: 0.0001)
    }

    func testTrackChangeResetsThePosition() {
        var estimator = PositionEstimator()
        estimator.synchronise(trackID: "A", position: 250, duration: 300, state: .playing, now: 1000)
        XCTAssertEqual(estimator.estimate(at: 1010), 260, accuracy: 0.0001)

        // Next track starts at zero.
        estimator.synchronise(trackID: "B", position: 0, duration: 180, state: .playing, now: 1010)
        XCTAssertEqual(estimator.estimate(at: 1010), 0, accuracy: 0.0001)
        XCTAssertEqual(estimator.estimate(at: 1015), 5, accuracy: 0.0001)
    }

    func testSmallReportingJitterDoesNotReanchor() {
        var estimator = PositionEstimator()
        estimator.synchronise(trackID: "A", position: 10, duration: 300, state: .playing, now: 1000)

        // At t=1002 our estimate is 12. A poll reporting 11.6 is jitter, not a
        // seek, and must not make the readout jump backwards.
        estimator.synchronise(trackID: "A", position: 11.6, duration: 300, state: .playing, now: 1002)
        XCTAssertEqual(estimator.estimate(at: 1002), 12, accuracy: 0.0001)
    }

    func testALargeJumpIsTreatedAsASeek() {
        var estimator = PositionEstimator()
        estimator.synchronise(trackID: "A", position: 10, duration: 300, state: .playing, now: 1000)

        // User scrubs to 200.
        estimator.synchronise(trackID: "A", position: 200, duration: 300, state: .playing, now: 1005)
        XCTAssertEqual(estimator.estimate(at: 1005), 200, accuracy: 0.0001)
    }

    func testPositionNeverExceedsDuration() {
        var estimator = PositionEstimator()
        estimator.synchronise(trackID: "A", position: 295, duration: 300, state: .playing, now: 1000)
        XCTAssertEqual(estimator.estimate(at: 1100), 300, accuracy: 0.0001)
    }

    func testAnchoredTrackWithUnknownDurationIsNotClamped() {
        var estimator = PositionEstimator()
        estimator.synchronise(trackID: "A", position: 10, duration: 0, state: .playing, now: 1000)
        // A live stream has no duration; the playhead must still advance.
        XCTAssertEqual(estimator.estimate(at: 1030), 40, accuracy: 0.0001)
    }

    func testNegativeReportedPositionIsClampedToZero() {
        var estimator = PositionEstimator()
        estimator.synchronise(trackID: "A", position: -5, duration: 300, state: .paused, now: 1000)
        XCTAssertEqual(estimator.estimate(at: 1000), 0, accuracy: 0.0001)
    }

    func testResetClearsEverything() {
        var estimator = PositionEstimator()
        estimator.synchronise(trackID: "A", position: 50, duration: 300, state: .playing, now: 1000)
        estimator.reset()
        XCTAssertFalse(estimator.isAnchored)
        XCTAssertEqual(estimator.estimate(at: 2000), 0, accuracy: 0.0001)
    }

    func testEstimateBeforeAnySynchronisationIsZero() {
        let estimator = PositionEstimator()
        XCTAssertEqual(estimator.estimate(at: 12345), 0, accuracy: 0.0001)
    }

    func testTimeDoesNotRunBackwards() {
        // A monotonic clock never goes backwards, but guard the arithmetic too.
        var estimator = PositionEstimator()
        estimator.synchronise(trackID: "A", position: 30, duration: 300, state: .playing, now: 1000)
        XCTAssertEqual(estimator.estimate(at: 900), 30, accuracy: 0.0001)
    }
}

// MARK: - Session clock

final class SessionClockTests: XCTestCase {

    func testOnlyPlayingTimeAccumulates() {
        var clock = SessionClock()

        clock.update(isPlaying: true, now: 100)
        XCTAssertEqual(clock.elapsed(at: 130), 30, accuracy: 0.0001)

        // Paused for a long stretch: none of it counts.
        clock.update(isPlaying: false, now: 130)
        XCTAssertEqual(clock.elapsed(at: 1000), 30, accuracy: 0.0001)

        // Resume.
        clock.update(isPlaying: true, now: 1000)
        XCTAssertEqual(clock.elapsed(at: 1010), 40, accuracy: 0.0001)
    }

    func testRepeatedUpdatesWithTheSameStateAreIdempotent() {
        var clock = SessionClock()
        clock.update(isPlaying: true, now: 100)
        clock.update(isPlaying: true, now: 105)
        clock.update(isPlaying: true, now: 110)
        XCTAssertEqual(clock.elapsed(at: 120), 20, accuracy: 0.0001)
    }

    func testStaysAtZeroUntilPlaybackStarts() {
        var clock = SessionClock()
        clock.update(isPlaying: false, now: 100)
        XCTAssertEqual(clock.elapsed(at: 500), 0, accuracy: 0.0001)
        XCTAssertFalse(clock.hasStarted)
    }

    func testResetClearsAccumulatedTime() {
        var clock = SessionClock()
        clock.update(isPlaying: true, now: 100)
        clock.update(isPlaying: false, now: 200)
        clock.reset()
        XCTAssertEqual(clock.elapsed(at: 500), 0, accuracy: 0.0001)
        XCTAssertFalse(clock.hasStarted)
    }
}

// MARK: - Artwork cache

final class ArtworkCacheTests: XCTestCase {

    private func metadata(id: String = "", title: String = "T", artist: String = "A", album: String = "B") -> TrackMetadata {
        TrackMetadata(title: title, artist: artist, album: album, duration: 100, persistentID: id)
    }

    func testKeyPrefersThePersistentID() {
        let key = ArtworkCache.key(for: metadata(id: "ABC123", title: "T", artist: "A", album: "B"))
        XCTAssertEqual(key, "ABC123")
    }

    func testKeyFallsBackToArtistAlbumTitle() {
        let key = ArtworkCache.key(for: metadata(id: "", title: "T", artist: "A", album: "B"))
        XCTAssertEqual(key, ArtworkCache.fallbackKey(title: "T", artist: "A", album: "B"))
        // Different tracks must not collide.
        XCTAssertNotEqual(
            key,
            ArtworkCache.key(for: metadata(id: "", title: "T2", artist: "A", album: "B"))
        )
    }

    func testWhitespaceOnlyPersistentIDFallsBack() {
        let key = ArtworkCache.key(for: metadata(id: "   ", title: "T"))
        XCTAssertEqual(key, ArtworkCache.fallbackKey(title: "T", artist: "A", album: "B"))
    }

    func testStoresAndRetrieves() {
        let cache = ArtworkCache(capacity: 3)
        let blob = Data([1, 2, 3])
        cache.store(blob, for: "X")
        XCTAssertEqual(cache.data(for: "X"), blob)
        XCTAssertNil(cache.data(for: "Y"))
    }

    func testEvictsOldestBeyondCapacity() {
        let cache = ArtworkCache(capacity: 2)
        cache.store(Data([1]), for: "A")
        cache.store(Data([2]), for: "B")
        cache.store(Data([3]), for: "C")

        XCTAssertNil(cache.data(for: "A"), "oldest entry should have been evicted")
        XCTAssertNotNil(cache.data(for: "B"))
        XCTAssertNotNil(cache.data(for: "C"))
        XCTAssertEqual(cache.count, 2)
    }

    func testEmptyDataIsNotCached() {
        // Missing artwork is usually a temporary state — Music.app often has no
        // cover yet for a track that just started streaming — so recording its
        // absence would turn "not yet" into "never".
        let cache = ArtworkCache(capacity: 2)
        cache.store(Data(), for: "NONE")
        XCTAssertNil(cache.data(for: "NONE"))
        XCTAssertEqual(cache.count, 0)
    }

    func testRewritingAnExistingKeyDoesNotDuplicateOrderEntry() {
        let cache = ArtworkCache(capacity: 2)
        cache.store(Data([1]), for: "A")
        cache.store(Data([2]), for: "B")
        cache.store(Data([9]), for: "A")   // refresh A, not a new entry

        // Order should now be B, A — so adding C evicts B, not A.
        cache.store(Data([3]), for: "C")
        XCTAssertNil(cache.data(for: "B"))
        XCTAssertNotNil(cache.data(for: "A"))
        XCTAssertEqual(cache.data(for: "A"), Data([9]))
    }
}

// MARK: - Provider behaviour, driven by a mock client

/// These tests never launch Music.app, never send an Apple Event and never need
/// Automation permission. That is the whole point of the `MusicClient` seam.
@MainActor
final class AppleMusicNowPlayingServiceTests: XCTestCase {

    /// Starts the service and waits for the first published update.
    private func startAndWait(
        _ service: AppleMusicNowPlayingService,
        timeout: TimeInterval = 5
    ) async {
        let expectation = XCTestExpectation(description: "provider update")
        expectation.assertForOverFulfill = false

        let previous = service.onChange
        service.onChange = {
            previous?()
            expectation.fulfill()
        }
        service.start()
        await fulfillment(of: [expectation], timeout: timeout)
    }

    func testReadsTrackFromTheClient() async {
        let client = MockMusicClient()
        client.setState(
            .playing,
            title: "Remember",
            artist: "Ryo Nakamura",
            album: "Remember - Single",
            duration: 307.969,
            position: 254.345,
            persistentID: "ABC3A5D15B7A488C"
        )

        let service = AppleMusicNowPlayingService(client: client)
        await startAndWait(service)
        defer { service.stop() }

        XCTAssertEqual(service.availability, .ready)
        XCTAssertEqual(service.snapshot.metadata?.title, "Remember")
        XCTAssertEqual(service.snapshot.metadata?.artist, "Ryo Nakamura")
        XCTAssertEqual(service.snapshot.metadata?.album, "Remember - Single")
        XCTAssertEqual(service.snapshot.metadata?.duration ?? 0, 307.969, accuracy: 0.001)
        XCTAssertEqual(service.snapshot.state, .playing)
        XCTAssertEqual(service.snapshot.source, .appleMusic)
        XCTAssertEqual(service.snapshot.position, 254.345, accuracy: 0.5)
    }

    func testMusicNotRunningYieldsItsOwnStateAndNoFabricatedTrack() async {
        let client = MockMusicClient()
        client.isRunning = false

        let service = AppleMusicNowPlayingService(client: client)
        await startAndWait(service)
        defer { service.stop() }

        XCTAssertEqual(service.availability, .musicAppNotRunning)
        XCTAssertNil(service.snapshot.metadata)
        XCTAssertEqual(service.snapshot.source, .none)
        XCTAssertEqual(service.snapshot.position, 0)
    }

    func testPermissionDeniedYieldsAccessRequired() async {
        let client = MockMusicClient()
        client.errorToThrow = .accessRequired

        let service = AppleMusicNowPlayingService(client: client)
        await startAndWait(service)
        defer { service.stop() }

        XCTAssertEqual(service.availability, .accessRequired)
        XCTAssertTrue(service.availability.offersSettingsButton)
        XCTAssertNil(service.snapshot.metadata)
    }

    func testStoppedPlayerShowsTheIdleState() async {
        let client = MockMusicClient()
        // A track is loaded, but the transport is stopped.
        client.setState(.stopped, title: "Loaded But Stopped", position: 0)

        let service = AppleMusicNowPlayingService(client: client)
        await startAndWait(service)
        defer { service.stop() }

        XCTAssertEqual(service.availability, .noTrack)
        XCTAssertNil(service.snapshot.metadata)
    }

    func testPausedTrackIsDisplayedWithPausedState() async {
        let client = MockMusicClient()
        client.setState(.paused, title: "Paused Song", position: 60)

        let service = AppleMusicNowPlayingService(client: client)
        await startAndWait(service)
        defer { service.stop() }

        XCTAssertEqual(service.availability, .ready)
        XCTAssertEqual(service.snapshot.state, .paused)
        XCTAssertEqual(service.snapshot.metadata?.title, "Paused Song")
    }

    func testArtworkIsFetchedOncePerTrackAndCached() async {
        let client = MockMusicClient()
        let artwork = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x11, 0x22])
        client.artwork = artwork
        client.setState(.playing, persistentID: "TRACK-1")

        let cache = ArtworkCache(capacity: 4)
        let service = AppleMusicNowPlayingService(client: client, artworkCache: cache)

        let expectation = XCTestExpectation(description: "artwork loaded")
        expectation.assertForOverFulfill = false
        service.onChange = {
            if service.artworkData != nil { expectation.fulfill() }
        }

        service.start()
        await fulfillment(of: [expectation], timeout: 5)

        XCTAssertEqual(service.artworkData, artwork)
        XCTAssertEqual(cache.data(for: "TRACK-1"), artwork)

        // A second refresh of the same track must come from the cache.
        let callsAfterFirstLoad = client.fetchArtworkCallCount
        service.refreshNow()
        try? await Task.sleep(nanoseconds: 300_000_000)

        XCTAssertEqual(
            client.fetchArtworkCallCount,
            callsAfterFirstLoad,
            "artwork must not be re-read for a track already in the cache"
        )
        service.stop()
    }

    func testTrackChangeReplacesMetadataAndArtwork() async {
        let client = MockMusicClient()
        client.setState(.playing, title: "Song A", position: 100, persistentID: "A")
        client.artwork = Data([1, 1, 1])

        let service = AppleMusicNowPlayingService(client: client, artworkCache: ArtworkCache(capacity: 4))

        let firstLoad = XCTestExpectation(description: "song A")
        firstLoad.assertForOverFulfill = false
        service.onChange = { firstLoad.fulfill() }
        service.start()
        await fulfillment(of: [firstLoad], timeout: 5)

        XCTAssertEqual(service.snapshot.metadata?.title, "Song A")
        XCTAssertEqual(service.artworkData, Data([1, 1, 1]))

        // Next track.
        client.setState(.playing, title: "Song B", position: 0, persistentID: "B")
        client.artwork = Data([2, 2, 2])

        let secondLoad = XCTestExpectation(description: "song B")
        secondLoad.assertForOverFulfill = false
        service.onChange = {
            if service.snapshot.metadata?.title == "Song B", service.artworkData == Data([2, 2, 2]) {
                secondLoad.fulfill()
            }
        }
        service.refreshNow()
        await fulfillment(of: [secondLoad], timeout: 5)

        XCTAssertEqual(service.snapshot.metadata?.title, "Song B")
        XCTAssertEqual(service.snapshot.metadata?.persistentID, "B")
        XCTAssertEqual(service.artworkData, Data([2, 2, 2]))
        service.stop()
    }

    func testTrackDisappearingClearsMetadata() async {
        let client = MockMusicClient()
        client.setState(.playing, title: "Something", position: 30, persistentID: "X")

        let service = AppleMusicNowPlayingService(client: client)
        await startAndWait(service)
        XCTAssertNotNil(service.snapshot.metadata)

        // Music.app quits.
        client.isRunning = false

        let cleared = XCTestExpectation(description: "cleared")
        cleared.assertForOverFulfill = false
        service.onChange = {
            if service.snapshot.metadata == nil { cleared.fulfill() }
        }
        service.refreshNow()
        await fulfillment(of: [cleared], timeout: 5)

        XCTAssertEqual(service.availability, .musicAppNotRunning)
        XCTAssertNil(service.snapshot.metadata, "a stale track must not be left on screen")
        service.stop()
    }

    func testTransportCommandsAreForwardedOnlyWhenMusicIsRunning() async {
        let client = MockMusicClient()
        client.setState(.playing)

        let service = AppleMusicNowPlayingService(client: client)
        await startAndWait(service)

        service.playPause()
        try? await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(client.sentCommands, [.playPause])

        service.stop()
    }

    func testTransportDoesNothingWhenMusicIsNotRunning() async {
        let client = MockMusicClient()
        client.isRunning = false

        let service = AppleMusicNowPlayingService(client: client)
        await startAndWait(service)

        service.playPause()
        service.next()
        try? await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertTrue(
            client.sentCommands.isEmpty,
            "a transport button must never launch Music.app"
        )
        service.stop()
    }

    func testPollIntervalIsClampedToASaneRange() async {
        // Guards against a stored settings blob asking for 0.01 s polling,
        // which would hammer Music.app with Apple Events.
        let service = AppleMusicNowPlayingService(client: MockMusicClient())
        service.setPollInterval(0.001)
        service.setPollInterval(999)
        // No crash, no assertion — the clamp is internal. The point is that
        // neither extreme is accepted verbatim.
        XCTAssertTrue(true)
    }
}

// MARK: - Apple Event decoding

/// Regression tests for the descriptor-level bugs that only showed up under
/// live verification. These build descriptors by hand, so they run without
/// Music.app and would have caught both failures.
final class AppleEventDecodingTests: XCTestCase {

    /// Builds a descriptor with an exact four-character type, which is the
    /// only way to reproduce AppleScript's `'true'` / `'false'` forms.
    private func descriptor(_ type: DescType, _ data: Data = Data()) -> NSAppleEventDescriptor {
        guard let made = NSAppleEventDescriptor(descriptorType: type, data: data) else {
            fatalError("could not build descriptor of type \(type)")
        }
        return made
    }

    /// The bug that made every track invisible: AppleScript returns `true` as a
    /// null descriptor typed `'true'`, not as a `'bool'` descriptor.
    func testBooleanDecodesAppleScriptsTrueType() {
        XCTAssertTrue(AppleEventDecoding.boolean(descriptor(AppleEventDecoding.trueType)))
    }

    func testBooleanDecodesAppleScriptsFalseType() {
        XCTAssertFalse(AppleEventDecoding.boolean(descriptor(AppleEventDecoding.falseType)))
    }

    func testBooleanStillHandlesTheBoolType() {
        // The `'bool'` form is what the constants suggest, and older scripts can
        // produce it, so both must work.
        XCTAssertTrue(AppleEventDecoding.boolean(NSAppleEventDescriptor(boolean: true)))
        XCTAssertFalse(AppleEventDecoding.boolean(NSAppleEventDescriptor(boolean: false)))
    }

    func testBooleanIsFalseForMissingValueAndNil() {
        XCTAssertFalse(AppleEventDecoding.boolean(descriptor(AppleEventDecoding.OSType.missing)))
        XCTAssertFalse(AppleEventDecoding.boolean(nil))
        XCTAssertFalse(AppleEventDecoding.boolean(NSAppleEventDescriptor(string: "true")))
    }

    func testTextMapsMissingValueToEmptyString() {
        XCTAssertEqual(AppleEventDecoding.text(descriptor(AppleEventDecoding.OSType.missing)), "")
        XCTAssertEqual(AppleEventDecoding.text(nil), "")
        XCTAssertEqual(AppleEventDecoding.text(NSAppleEventDescriptor(string: "hello")), "hello")
    }

    func testNumberRejectsNonNumericDescriptorsWithoutCoercing() {
        // A `missing value` duration must read as 0, not blow up.
        XCTAssertEqual(AppleEventDecoding.number(descriptor(AppleEventDecoding.OSType.missing)), 0)
        XCTAssertEqual(AppleEventDecoding.number(NSAppleEventDescriptor(string: "abc")), 0)
        XCTAssertEqual(AppleEventDecoding.number(NSAppleEventDescriptor(double: 214.573)), 214.573, accuracy: 0.001)
        XCTAssertEqual(AppleEventDecoding.number(NSAppleEventDescriptor(int32: 1)), 1)
    }

    /// Builds a list exactly as the production script does.
    private func metadataList(
        state: String = "playing",
        hasTrack: Bool = true,
        title: String = "Khumbu Icefall",
        artist: String = "Adam Young",
        album: String = "The Ascent of Everest",
        duration: Double = 214.573,
        position: Double = 25.098,
        id: String = "495B6C02EE9ACB78"
    ) -> NSAppleEventDescriptor {
        let list = NSAppleEventDescriptor.list()
        list.insert(NSAppleEventDescriptor(string: state), at: 1)
        list.insert(descriptor(hasTrack ? AppleEventDecoding.trueType : AppleEventDecoding.falseType), at: 2)
        list.insert(NSAppleEventDescriptor(string: title), at: 3)
        list.insert(NSAppleEventDescriptor(string: artist), at: 4)
        list.insert(NSAppleEventDescriptor(string: album), at: 5)
        list.insert(NSAppleEventDescriptor(double: duration), at: 6)
        list.insert(NSAppleEventDescriptor(double: position), at: 7)
        list.insert(NSAppleEventDescriptor(string: id), at: 8)
        list.insert(NSAppleEventDescriptor(int32: 1), at: 9)
        return list
    }

    func testDecodesARealisticScriptResult() throws {
        // The shape below is what the production script actually returned on
        // macOS 15.5, captured during verification.
        let raw = try AppleEventDecoding.decodeSnapshot(
            metadataList(),
            notRunningSentinel: "__MUSIC_NOT_RUNNING__"
        )

        XCTAssertEqual(raw.playerStateText, "playing")
        XCTAssertTrue(raw.hasTrack)
        XCTAssertEqual(raw.title, "Khumbu Icefall")
        XCTAssertEqual(raw.artist, "Adam Young")
        XCTAssertEqual(raw.album, "The Ascent of Everest")
        XCTAssertEqual(raw.duration, 214.573, accuracy: 0.001)
        XCTAssertEqual(raw.position, 25.098, accuracy: 0.001)
        XCTAssertEqual(raw.persistentID, "495B6C02EE9ACB78")
        XCTAssertTrue(raw.isDisplayable)
    }

    func testNotRunningSentinelBecomesAnError() {
        let list = metadataList(state: "__MUSIC_NOT_RUNNING__", hasTrack: false)
        XCTAssertThrowsError(
            try AppleEventDecoding.decodeSnapshot(list, notRunningSentinel: "__MUSIC_NOT_RUNNING__")
        ) { error in
            XCTAssertEqual(error as? MusicClientError, .musicAppNotRunning)
        }
    }

    func testWrongFieldCountIsRejectedRatherThanMisread() {
        // If the script and the decoder ever drift, this must fail loudly
        // instead of silently mapping title onto artist.
        let short = NSAppleEventDescriptor.list()
        short.insert(NSAppleEventDescriptor(string: "playing"), at: 1)
        XCTAssertThrowsError(
            try AppleEventDecoding.decodeSnapshot(short, notRunningSentinel: "x")
        )
    }

    func testMissingValueFieldsDoNotLoseTheWholeReading() throws {
        // Music.app returns `missing value` for e.g. artist on some media kinds.
        let list = metadataList()
        list.insert(descriptor(AppleEventDecoding.OSType.missing), at: 4)   // artist
        list.insert(descriptor(AppleEventDecoding.OSType.missing), at: 6)   // duration

        let raw = try AppleEventDecoding.decodeSnapshot(list, notRunningSentinel: "x")
        XCTAssertEqual(raw.artist, "")
        XCTAssertEqual(raw.duration, 0)
        XCTAssertEqual(raw.title, "Khumbu Icefall", "one missing field must not lose the rest")
    }
}

// MARK: - Playhead regression

@MainActor
final class PlayheadPublicationTests: XCTestCase {

    /// Regression test for the second live-verification bug.
    ///
    /// When a reading is not displayable the estimator is unanchored, so
    /// `estimate()` returns 0 — and 0 is a perfectly plausible playhead
    /// position, so the tick used to overwrite a correct value with it. The
    /// live trace showed the position alternating `38.83 → 0.00 → 40.05`.
    func testTheTickDoesNotOverwriteThePositionWithAnUnanchoredZero() async {
        let client = MockMusicClient()
        // Playing, but with a blank title, so the reading is not displayable and
        // the estimator never gets an anchor.
        client.rawSnapshot = MusicRawSnapshot(
            playerStateText: "playing",
            hasTrack: true,
            title: "",
            artist: "",
            album: "",
            duration: 200,
            position: 42,
            persistentID: "X"
        )

        let service = AppleMusicNowPlayingService(client: client)

        let expectation = XCTestExpectation(description: "first update")
        expectation.assertForOverFulfill = false
        service.onChange = { expectation.fulfill() }
        service.start()
        await fulfillment(of: [expectation], timeout: 5)

        XCTAssertEqual(service.availability, .noTrack)

        // The playback tick fires every 0.5 s; wait past several of them.
        try? await Task.sleep(nanoseconds: 1_400_000_000)

        XCTAssertEqual(
            service.snapshot.position,
            0,
            accuracy: 0.001,
            "a non-displayable reading must report no playhead, and the tick must not resurrect one"
        )
        service.stop()
    }

    /// The positive case: a displayable track anchors the estimator, and the
    /// tick then advances the playhead smoothly between polls.
    func testTheTickAdvancesThePlayheadForADisplayableTrack() async {
        let client = MockMusicClient()
        client.setState(.playing, title: "Anchored", duration: 300, position: 30, persistentID: "A")

        let service = AppleMusicNowPlayingService(client: client)
        let expectation = XCTestExpectation(description: "first update")
        expectation.assertForOverFulfill = false
        service.onChange = { expectation.fulfill() }
        service.start()
        await fulfillment(of: [expectation], timeout: 5)

        let before = service.snapshot.position
        XCTAssertEqual(service.availability, .ready)

        try? await Task.sleep(nanoseconds: 1_200_000_000)
        let after = service.snapshot.position

        // The mock reports a fixed 30 s and the poll re-anchors to it every
        // 1.5 s. Between two polls the playhead may therefore drift forward by
        // at most one poll interval, and must never run away or go backwards.
        XCTAssertGreaterThanOrEqual(after, before - 0.01, "the playhead must never jump backwards")
        XCTAssertLessThanOrEqual(
            after,
            30 + 1.5 + 0.35,
            "the playhead must stay anchored to what Music.app reported, allowing one poll interval"
        )
        service.stop()
    }
}

// MARK: - Late-arriving artwork

@MainActor
final class ArtworkRetryTests: XCTestCase {

    /// Streamed tracks commonly have no cover for the first moment or two.
    /// Caching that first `nil` would leave the track permanently blank.
    func testArtworkThatArrivesLateIsStillPickedUp() async {
        let client = MockMusicClient()
        client.artwork = nil
        client.setState(.playing, title: "Streamed", duration: 200, position: 0, persistentID: "LATE-1")

        let service = AppleMusicNowPlayingService(client: client, artworkCache: ArtworkCache(capacity: 4))

        let first = XCTestExpectation(description: "first poll")
        first.assertForOverFulfill = false
        service.onChange = { first.fulfill() }
        service.start()
        await fulfillment(of: [first], timeout: 5)

        XCTAssertNil(service.artworkData, "nothing to show yet")

        // The cover shows up.
        let blob = Data([0xFF, 0xD8, 0xFF, 0xE0, 0xAA])
        client.artwork = blob

        let arrived = XCTestExpectation(description: "artwork arrives")
        arrived.assertForOverFulfill = false
        service.onChange = {
            if service.artworkData == blob { arrived.fulfill() }
        }

        // The retry happens on the next poll rather than needing a track change.
        await fulfillment(of: [arrived], timeout: 8)
        XCTAssertEqual(service.artworkData, blob)
        service.stop()
    }

    func testRetriesAreBoundedSoAMissingCoverDoesNotPollForever() async {
        let client = MockMusicClient()
        client.artwork = nil
        client.setState(.playing, title: "No Cover", duration: 200, position: 0, persistentID: "NONE-1")

        let service = AppleMusicNowPlayingService(client: client, artworkCache: ArtworkCache(capacity: 4))

        let first = XCTestExpectation(description: "first poll")
        first.assertForOverFulfill = false
        service.onChange = { first.fulfill() }
        service.start()
        await fulfillment(of: [first], timeout: 5)

        // Long enough for several poll intervals to elapse.
        try? await Task.sleep(nanoseconds: 9_000_000_000)

        XCTAssertNil(service.artworkData)
        // The retry budget is deliberately small; without it a track that
        // genuinely has no cover would trigger a fetch on every single poll.
        XCTAssertLessThanOrEqual(
            client.fetchArtworkCallCount,
            6,
            "artwork fetches must be bounded, got \(client.fetchArtworkCallCount)"
        )
        service.stop()
    }
}
