import XCTest
@testable import MusicHUDCore

/// Tests for the logic layer.
///
/// The drawing code cannot be asserted on from here, but everything it depends
/// on — the segment table, the formatters, the proportional layout arithmetic
/// and the now-playing state machine — can be, and those are where the
/// mistakes actually live.
final class MusicHUDCoreTests: XCTestCase {

    // MARK: - Seven-segment table

    func testEveryDigitReturnsAValidMask() {
        for character in "0123456789" {
            let mask = SevenSegmentFont.mask(for: character)
            XCTAssertNotEqual(mask, .none, "digit \(character) produced a blank mask")
            XCTAssertTrue(
                mask.isSubset(of: .all),
                "digit \(character) set bits outside the seven segments"
            )
        }
    }

    func testKnownDigitShapes() {
        // These are the shapes that make a seven-segment display readable; if
        // any of them drifts, the clock silently shows wrong numbers.
        XCTAssertEqual(
            SevenSegmentFont.mask(for: "1"),
            [.topRight, .bottomRight]
        )
        XCTAssertEqual(
            SevenSegmentFont.mask(for: "8"),
            .all
        )
        XCTAssertEqual(
            SevenSegmentFont.mask(for: "0"),
            [.top, .topLeft, .topRight, .bottomLeft, .bottomRight, .bottom]
        )
        XCTAssertEqual(
            SevenSegmentFont.mask(for: "4"),
            [.topLeft, .middle, .topRight, .bottomRight]
        )
        XCTAssertEqual(
            SevenSegmentFont.mask(for: "7"),
            [.top, .topRight, .bottomRight]
        )
    }

    func testZeroAndCapitalODoNotShareTheMiddleSegment() {
        // The middle segment is the only thing distinguishing 0 from 8/O.
        XCTAssertFalse(SevenSegmentFont.mask(for: "0").contains(.middle))
    }

    func testUnsupportedCharacterRendersBlank() {
        XCTAssertEqual(SevenSegmentFont.mask(for: "Z"), .none)
        XCTAssertEqual(SevenSegmentFont.mask(for: ":"), .none)
    }

    func testColonIsHandledByTheDigitRowNotTheSegmentTable() {
        // The clock string uses ":" as a separator; the segment table must
        // report it as blank so the caller knows to draw a colon glyph instead.
        let masks = SevenSegmentFont.masks(for: "00:42:55")
        XCTAssertEqual(masks.count, 8)
        XCTAssertEqual(masks[2], .none)
        XCTAssertEqual(masks[5], .none)
    }

    func testMaskPositionRoundTrip() {
        for position in SevenSegmentPosition.allCases {
            let mask = SevenSegmentMask.none.setting(position, lit: true)
            XCTAssertTrue(mask.contains(position))
            XCTAssertEqual(mask, position.mask)

            let cleared = mask.setting(position, lit: false)
            XCTAssertFalse(cleared.contains(position))
        }
    }

    // MARK: - Time formatting

    func testClockStyleIsAlwaysZeroPaddedHMS() {
        XCTAssertEqual(HUDTimeFormatter.clockStyle(0), "00:00:00")
        XCTAssertEqual(HUDTimeFormatter.clockStyle(42 * 60 + 55), "00:42:55")
        XCTAssertEqual(HUDTimeFormatter.clockStyle(3600), "01:00:00")
        XCTAssertEqual(HUDTimeFormatter.clockStyle(3661), "01:01:01")
    }

    func testClockStyleClampsNegativeInput() {
        // A track that has not started, or a clock skew, must never render "-1".
        XCTAssertEqual(HUDTimeFormatter.clockStyle(-5), "00:00:00")
    }

    func testClockStyleTruncatesRatherThanRounds() {
        // A display that rounds up would show 00:00:01 for the whole first
        // second of playback, which reads as a bug.
        XCTAssertEqual(HUDTimeFormatter.clockStyle(0.99), "00:00:00")
        XCTAssertEqual(HUDTimeFormatter.clockStyle(1.99), "00:00:01")
    }

    func testDurationDropsTheHourComponentUnderAnHour() {
        XCTAssertEqual(HUDTimeFormatter.duration(227), "3:47")
        XCTAssertEqual(HUDTimeFormatter.duration(3753), "1:02:33")
        XCTAssertEqual(HUDTimeFormatter.duration(0), "0:00")
    }

    func testRemainingIsSigned() {
        XCTAssertEqual(HUDTimeFormatter.remaining(144), "-2:24")
    }

    func testWallClockUsesTheRequestedTimeZone() {
        // 2024-01-01 00:00:00 UTC
        let date = Date(timeIntervalSince1970: 1_704_067_200)
        XCTAssertEqual(HUDTimeFormatter.wallClock(date, timeZone: TimeZone(identifier: "UTC")!), "00:00:00")
        XCTAssertEqual(
            HUDTimeFormatter.wallClock(date, timeZone: TimeZone(identifier: "Asia/Shanghai")!),
            "08:00:00"
        )
    }

    func testTimeZoneNameFallsBackToTheIdentifier() {
        XCTAssertEqual(HUDTimeFormatter.timeZoneName("Not/AZone"), "Not/AZone")
    }

    // MARK: - Settings

    func testSettingsRoundTripThroughTheStore() {
        let defaults = UserDefaults(suiteName: "MusicHUDTests.roundTrip")!
        defaults.removePersistentDomain(forName: "MusicHUDTests.roundTrip")
        let store = HUDSettingsStore(defaults: defaults)

        var settings = HUDSettings()
        settings.cornerRadius = 26
        settings.spectrumBarCount = 72
        settings.clockMode = .timeZoneTime
        settings.clockStyle = .monospaced
        settings.timeZoneIdentifier = "America/Los_Angeles"
        store.save(settings)

        let loaded = store.load()
        XCTAssertEqual(loaded, settings)
    }

    func testLoadingEmptyStoreYieldsDefaults() {
        let defaults = UserDefaults(suiteName: "MusicHUDTests.empty")!
        defaults.removePersistentDomain(forName: "MusicHUDTests.empty")
        XCTAssertEqual(HUDSettingsStore(defaults: defaults).load(), HUDSettings())
    }

    func testCorruptStoredDataFallsBackToDefaults() {
        let defaults = UserDefaults(suiteName: "MusicHUDTests.corrupt")!
        defaults.removePersistentDomain(forName: "MusicHUDTests.corrupt")
        defaults.set(Data("not json".utf8), forKey: "MusicHUD.settings.v1")
        XCTAssertEqual(HUDSettingsStore(defaults: defaults).load(), HUDSettings())
    }

    func testSanitizeClampsOutOfRangeValues() {
        var settings = HUDSettings()
        settings.windowOpacity = 12
        settings.cornerRadius = -40
        settings.blurStrength = 5
        settings.panelTint = -1
        settings.clockScale = 99
        settings.spectrumBarCount = 5000
        settings.timeZoneIdentifier = "Not/AZone"

        let clean = settings.sanitized()

        XCTAssertEqual(clean.windowOpacity, 1.0)
        XCTAssertEqual(clean.cornerRadius, 0)
        XCTAssertEqual(clean.blurStrength, 1)
        XCTAssertEqual(clean.panelTint, 0)
        XCTAssertEqual(clean.clockScale, 1.4)
        XCTAssertEqual(clean.spectrumBarCount, 96)
        // A stale time zone must not survive; the clock would show the wrong time.
        XCTAssertNotNil(TimeZone(identifier: clean.timeZoneIdentifier))
    }

    func testSanitizeClampsARememberedWindowFrame() {
        var settings = HUDSettings()
        settings.windowFrame = WindowFrame(x: 10, y: 10, width: 5, height: 20_000)
        let clean = settings.sanitized()
        XCTAssertEqual(clean.windowFrame?.width, HUDSettings.minimumSize.width)
        XCTAssertEqual(clean.windowFrame?.height, HUDSettings.maximumSize.height)
    }

    // MARK: - Now playing model

    func testSnapshotProgressAndRemaining() {
        let metadata = TrackMetadata(title: "T", artist: "A", album: "B", duration: 200)
        let snapshot = NowPlayingSnapshot(metadata: metadata, state: .playing, position: 50, source: .demo)

        XCTAssertEqual(snapshot.progress, 0.25)
        XCTAssertEqual(snapshot.remaining, 150)
        XCTAssertTrue(snapshot.hasTrack)
    }

    func testSnapshotProgressIsNilWhenDurationIsUnknown() {
        let metadata = TrackMetadata(title: "T", artist: "A", album: "B", duration: 0)
        let snapshot = NowPlayingSnapshot(metadata: metadata, state: .playing, position: 50)
        XCTAssertNil(snapshot.progress)
        XCTAssertNil(snapshot.remaining)
    }

    func testSnapshotProgressIsClampedPastTheEnd() {
        let metadata = TrackMetadata(title: "T", artist: "A", album: "B", duration: 100)
        let snapshot = NowPlayingSnapshot(metadata: metadata, state: .playing, position: 500)
        XCTAssertEqual(snapshot.progress, 1.0)
        XCTAssertEqual(snapshot.remaining, 0)
    }

    func testIdleSnapshotHasNoTrack() {
        XCTAssertFalse(NowPlayingSnapshot.idle.hasTrack)
        XCTAssertEqual(NowPlayingSnapshot.idle.state, .stopped)
        XCTAssertEqual(NowPlayingSnapshot.idle.source, .none)
    }

    func testDemoTracksAreNotEmptyAndHaveDurations() {
        for track in DemoLibrary.tracks {
            XCTAssertFalse(track.isEmpty)
            XCTAssertGreaterThan(track.duration, 0)
        }
    }

    func testDemoSessionElapsedMatchesTheReferenceReadout() {
        // The reference design shows 00:42:55 as the default readout.
        XCTAssertEqual(HUDTimeFormatter.clockStyle(DemoLibrary.sessionElapsed(forTrackAt: 0)), "00:42:55")
    }

    // MARK: - Layout arithmetic

    func testMetricsScaleIsOneAtTheDesignSize() {
        let metrics = HUDMetrics(containerWidth: 300, containerHeight: 420)
        XCTAssertEqual(metrics.scale, 1.0, accuracy: 0.0001)
        XCTAssertEqual(metrics.naturalContentHeight, HUDMetrics.designContentHeight, accuracy: 0.0001)
        XCTAssertEqual(metrics.verticalSlack, 20, accuracy: 0.0001)
    }

    func testMetricsScaleDownForASmallWindowAndNeverCollapse() {
        let tiny = HUDMetrics(containerWidth: 90, containerHeight: 120)
        XCTAssertGreaterThanOrEqual(tiny.scale, 0.78)
    }

    func testClockDigitsAlwaysFitTheAvailableWidth() {
        // The single most likely visual break: the digits overflowing the card.
        for width in stride(from: 240.0, through: 900.0, by: 20.0) {
            let height = width * 1.4
            let metrics = HUDMetrics(containerWidth: width, containerHeight: height)
            for scale in [0.6, 1.0, 1.4] {
                let digitHeight = metrics.digitHeight(clockScale: scale)
                let totalWidth = digitHeight * HUDMetrics.clockWidthInDigitHeights
                XCTAssertLessThanOrEqual(
                    totalWidth,
                    metrics.contentWidth + 0.001,
                    "digits overflow at width \(width), clock scale \(scale)"
                )
            }
        }
    }

    func testMetricsGrowMonotonicallyWithTheWindow() {
        let small = HUDMetrics(containerWidth: 300, containerHeight: 420)
        let large = HUDMetrics(containerWidth: 600, containerHeight: 840)
        XCTAssertGreaterThan(large.artworkSize, small.artworkSize)
        XCTAssertGreaterThan(large.spectrumHeight, small.spectrumHeight)
        XCTAssertGreaterThan(large.clockDigitHeight, small.clockDigitHeight)
    }

    // MARK: - Band resampling (DSP bands -> drawn bars)

    func testResampleHandlesEdgeCounts() {
        XCTAssertEqual(SpectrumBands.resample([], to: 10), [])
        XCTAssertEqual(SpectrumBands.resample([0.5], to: 0), [])
        XCTAssertEqual(SpectrumBands.resample([0.5], to: 3), [0.5, 0.5, 0.5])

        // Identity resample. Compared with a tolerance because the input is
        // `Float` and the output is `Double`: 0.1 as a Float is 0.10000000149…,
        // so exact equality here would be asserting a bug.
        let identity = SpectrumBands.resample([0.1, 0.2, 0.3], to: 3)
        XCTAssertEqual(identity.count, 3)
        for (actual, expected) in zip(identity, [0.1, 0.2, 0.3]) {
            XCTAssertEqual(actual, expected, accuracy: 0.0001)
        }
    }

    func testResamplePreservesEndpointsAndStaysInRange() {
        let input: [Float] = [0.0, 0.25, 0.9, 0.4, 0.1]
        let output = SpectrumBands.resample(input, to: 12)

        XCTAssertEqual(output.count, 12)
        XCTAssertEqual(output.first!, 0.0, accuracy: 0.0001)
        XCTAssertEqual(output.last!, 0.1, accuracy: 0.0001)
        for value in output {
            XCTAssertGreaterThanOrEqual(value, 0)
            XCTAssertLessThanOrEqual(value, 1)
        }
    }

    // MARK: - Artwork seeds

    func testArtworkPaletteIsDeterministicAndWrapsNegativeSeeds() {
        XCTAssertEqual(
            ArtworkPaletteLibrary.palette(forSeed: 0),
            ArtworkPaletteLibrary.palette(forSeed: ArtworkPaletteLibrary.palettes.count)
        )
        XCTAssertEqual(
            ArtworkPaletteLibrary.palette(forSeed: -1),
            ArtworkPaletteLibrary.palette(forSeed: ArtworkPaletteLibrary.palettes.count - 1)
        )
    }

}

// MARK: - Demo provider

/// `MockNowPlayingService` is main-actor isolated because `NowPlayingProviding`
/// is, so these live in their own isolated class.
@MainActor
final class MockNowPlayingServiceTests: XCTestCase {

    func testMockServiceStartsPlayingDemoData() {
        let service = MockNowPlayingService()
        XCTAssertEqual(service.snapshot.state, .playing)
        XCTAssertEqual(service.snapshot.source, .demo)
        XCTAssertTrue(service.snapshot.hasTrack)
    }

    func testMockServiceCyclesThroughTheLibraryWrappingAround() {
        let service = MockNowPlayingService()
        XCTAssertEqual(service.currentIndex, 0)

        service.previous()
        XCTAssertEqual(service.currentIndex, DemoLibrary.tracks.count - 1, "previous() must wrap")

        service.next()
        XCTAssertEqual(service.currentIndex, 0, "next() must wrap")

        for _ in 0..<DemoLibrary.tracks.count {
            service.next()
        }
        XCTAssertEqual(service.currentIndex, 0)
    }

    func testMockServicePlayPauseTogglesStateOnly() {
        let service = MockNowPlayingService()
        let positionBefore = service.snapshot.position

        service.playPause()
        XCTAssertEqual(service.snapshot.state, .paused)
        // Toggling transport must not silently move the playhead.
        XCTAssertEqual(service.snapshot.position, positionBefore)

        service.playPause()
        XCTAssertEqual(service.snapshot.state, .playing)
    }

    func testMockServiceNotifiesOnTransportChanges() {
        let service = MockNowPlayingService()
        var notifications = 0
        service.onChange = { notifications += 1 }

        service.playPause()
        service.next()
        service.previous()

        XCTAssertEqual(notifications, 3)
    }
}
