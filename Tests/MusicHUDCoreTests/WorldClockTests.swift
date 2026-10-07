import XCTest
@testable import MusicHUDCore

/// Phase 6 tests: the World Clock rotation and time-zone conversion.
///
/// Every assertion uses a fixed instant, so nothing here depends on when the
/// suite runs, and all conversions go through `TimeZone` rather than through any
/// arithmetic this project performs itself.
final class WorldClockTests: XCTestCase {

    /// 2025-01-01 00:00:00 UTC — northern winter: GMT / EST / PST, JST all year.
    private let winter = Date(timeIntervalSince1970: 1_735_689_600)

    /// 2025-07-01 00:00:00 UTC — northern summer: BST / EDT / PDT.
    private let summer = Date(timeIntervalSince1970: 1_751_328_000)

    private func city(_ identifier: String) -> WorldClockCity {
        WorldClockCatalogue.all.first { $0.timeZoneIdentifier == identifier }
            ?? WorldClockCity(timeZoneIdentifier: identifier, displayName: identifier)
    }

    // MARK: - Catalogue

    func testDefaultCatalogueIsTheCitiesTheBriefRequires() {
        let names = WorldClockCatalogue.defaults.map(\.displayName)
        XCTAssertEqual(names, ["TOKYO", "SHANGHAI", "LONDON", "NEW YORK", "LOS ANGELES"])
    }

    func testEveryCatalogueIdentifierIsARealTimeZone() {
        // A stale IANA identifier would render `--:--:--` with no explanation.
        for city in WorldClockCatalogue.all {
            XCTAssertNotNil(city.timeZone, "\(city.timeZoneIdentifier) does not resolve on this system")
            XCTAssertTrue(city.isValid)
        }
    }

    func testCatalogueIdentifiersAreUnique() {
        let identifiers = WorldClockCatalogue.all.map(\.timeZoneIdentifier)
        XCTAssertEqual(Set(identifiers).count, identifiers.count)
    }

    // MARK: - Time conversion

    func testTokyoTimeInWinter() {
        // JST is UTC+9 all year; no DST.
        XCTAssertEqual(city("Asia/Tokyo").timeString(at: winter), "09:00:00")
    }

    func testLondonTimeInWinterAndSummer() {
        // Winter: GMT (UTC+0). Summer: BST (UTC+1).
        XCTAssertEqual(city("Europe/London").timeString(at: winter), "00:00:00")
        XCTAssertEqual(city("Europe/London").timeString(at: summer), "01:00:00")
    }

    func testNewYorkTimeInWinterAndSummer() {
        // Winter: EST (UTC-5). Summer: EDT (UTC-4) — and the date rolls back.
        XCTAssertEqual(city("America/New_York").timeString(at: winter), "19:00:00")
        XCTAssertEqual(city("America/New_York").timeString(at: summer), "20:00:00")
    }

    func testLosAngelesTimeInWinterAndSummer() {
        XCTAssertEqual(city("America/Los_Angeles").timeString(at: winter), "16:00:00")
        XCTAssertEqual(city("America/Los_Angeles").timeString(at: summer), "17:00:00")
    }

    func testTimeConversionShiftsByExactlyTheSystemOffset() {
        // Cross-check the formatted string against the system's own offset, so a
        // bug in formatting cannot hide a wrong zone.
        for city in WorldClockCatalogue.defaults {
            let zone = city.timeZone!
            let offset = zone.secondsFromGMT(for: summer)
            let expected = Date(timeIntervalSince1970: Double(1_751_328_000 + offset))
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "UTC")!
            let parts = calendar.dateComponents([.hour, .minute, .second], from: expected)
            let text = String(format: "%02d:%02d:%02d", parts.hour!, parts.minute!, parts.second!)
            XCTAssertEqual(city.timeString(at: summer), text, "\(city.displayName)")
        }
    }

    // MARK: - Abbreviations

    func testUnitedStatesAbbreviationsComeFromTheSystem() {
        // macOS supplies these directly, including the DST switch.
        XCTAssertEqual(city("America/New_York").shortTimeZoneName(at: winter), "EST")
        XCTAssertEqual(city("America/New_York").shortTimeZoneName(at: summer), "EDT")
        XCTAssertEqual(city("America/Los_Angeles").shortTimeZoneName(at: winter), "PST")
        XCTAssertEqual(city("America/Los_Angeles").shortTimeZoneName(at: summer), "PDT")
    }

    func testCuratedAbbreviationCoversZonesTheSystemOnlyNamesByOffset() {
        // VERIFIED SDK BEHAVIOUR: `TimeZone.localizedName` returns `GMT+9` for
        // Asia/Tokyo and `GMT+1`/`GMT` for Europe/London on macOS 15.5, so the
        // curated label is what produces the JST / BST the brief asks for.
        XCTAssertEqual(city("Asia/Tokyo").shortTimeZoneName(at: winter), "JST")
        XCTAssertEqual(city("Europe/London").shortTimeZoneName(at: summer), "BST")
        XCTAssertEqual(city("Europe/London").shortTimeZoneName(at: winter), "GMT")
    }

    func testBareOffsetDetection() {
        XCTAssertTrue(WorldClockCity.isBareOffset("GMT+9"))
        XCTAssertTrue(WorldClockCity.isBareOffset("GMT-5"))
        XCTAssertTrue(WorldClockCity.isBareOffset("UTC+3"))
        // Real abbreviations must never be replaced by the curated fallback.
        XCTAssertFalse(WorldClockCity.isBareOffset("GMT"))
        XCTAssertFalse(WorldClockCity.isBareOffset("EST"))
        XCTAssertFalse(WorldClockCity.isBareOffset("BST"))
        XCTAssertFalse(WorldClockCity.isBareOffset("JST"))
    }

    func testACityWithNoCuratedAbbreviationFallsBackToTheIdentifier() {
        // `Europe/Paris` is in the catalogue with a curated label; strip it and
        // the system's own name must be used instead of an empty string.
        var paris = city("Europe/Paris")
        paris.standardAbbreviation = ""
        paris.daylightAbbreviation = ""
        XCTAssertFalse(paris.shortTimeZoneName(at: winter).isEmpty)
    }

    // MARK: - Captions

    func testCaptionIsCityThenAbbreviation() {
        XCTAssertEqual(city("Asia/Tokyo").caption(at: winter), "TOKYO · JST")
        XCTAssertEqual(city("Europe/London").caption(at: summer), "LONDON · BST")
        XCTAssertEqual(city("America/New_York").caption(at: winter), "NEW YORK · EST")
    }

    func testCaptionNeverSaysWorldOrTime() {
        // The brief is explicit; the city name provides the context.
        for city in WorldClockCatalogue.all {
            let caption = city.caption(at: summer).uppercased()
            XCTAssertFalse(caption.contains("WORLD"))
            XCTAssertFalse(caption.contains("TIME"))
        }
    }

    // MARK: - Display mode

    func testTrackModeUsesTheTrackTextAndTrackCaption() {
        let text = WorldClockFormatter.timeText(mode: .track, date: summer, trackText: "00:04:52")
        XCTAssertEqual(text, "00:04:52")

        let caption = WorldClockFormatter.caption(
            mode: .track, date: summer, trackCaption: "TRACK"
        )
        XCTAssertEqual(caption, "TRACK")
    }

    func testWorldClockModeOverridesTheTrackText() {
        let mode = ClockDisplayMode.worldClock(city("Asia/Tokyo"))
        XCTAssertEqual(
            WorldClockFormatter.timeText(mode: mode, date: winter, trackText: "00:04:52"),
            "09:00:00"
        )
        XCTAssertEqual(
            WorldClockFormatter.caption(mode: mode, date: winter, trackCaption: "TRACK"),
            "TOKYO · JST"
        )
    }

    func testDisplayModeAccessors() {
        XCTAssertFalse(ClockDisplayMode.track.isWorldClock)
        XCTAssertNil(ClockDisplayMode.track.city)

        let tokyo = ClockDisplayMode.worldClock(city("Asia/Tokyo"))
        XCTAssertTrue(tokyo.isWorldClock)
        XCTAssertEqual(tokyo.city?.displayName, "TOKYO")
    }

    // MARK: - Cycling

    func testCycleStartsAtTrack() {
        let cycle = WorldClockCycle(cities: WorldClockCatalogue.defaults)
        XCTAssertEqual(cycle.mode, .track)
        XCTAssertTrue(cycle.isAtTrack)
    }

    func testCycleVisitsEveryCityThenReturnsToTrack() {
        var cycle = WorldClockCycle(cities: WorldClockCatalogue.defaults)

        // Walk the catalogue rather than a hardcoded list: the rotation gained
        // Shanghai in Phase 7, and this test is about the walk, not the roster.
        for expected in WorldClockCatalogue.defaults.map(\.displayName) {
            cycle.advance()
            XCTAssertEqual(cycle.mode.city?.displayName, expected)
        }
        cycle.advance()
        XCTAssertEqual(cycle.mode, .track, "the rotation must wrap back to Track")
    }

    func testFullRotationIsExactlyOneMoreStepThanThereAreCities() {
        var cycle = WorldClockCycle(cities: WorldClockCatalogue.defaults)
        let steps = WorldClockCatalogue.defaults.count + 1
        for _ in 0..<steps { cycle.advance() }
        XCTAssertEqual(cycle.mode, .track)
    }

    func testResetToTrack() {
        var cycle = WorldClockCycle(cities: WorldClockCatalogue.defaults)
        cycle.advance()
        cycle.advance()
        XCTAssertTrue(cycle.mode.isWorldClock)
        cycle.resetToTrack()
        XCTAssertEqual(cycle.mode, .track)
    }

    func testDisabledCitiesAreSkipped() {
        var cities = WorldClockCatalogue.defaults
        let london = cities.firstIndex { $0.timeZoneIdentifier == "Europe/London" }!
        cities[london].isEnabled = false
        var cycle = WorldClockCycle(cities: cities)

        var visited: [String] = []
        for _ in 0..<cities.filter(\.isEnabled).count {
            cycle.advance()
            if let name = cycle.mode.city?.displayName { visited.append(name) }
        }
        XCTAssertFalse(visited.contains("LONDON"))
        XCTAssertEqual(visited.count, cities.filter(\.isEnabled).count)
    }

    func testAnEmptyCityListStillCyclesToTrackOnly() {
        var cycle = WorldClockCycle(cities: [])
        cycle.advance()
        XCTAssertEqual(cycle.mode, .track)
        cycle.advance()
        XCTAssertEqual(cycle.mode, .track)
    }

    func testUpdatingTheListKeepsTheSelectedCityWhenItSurvives() {
        // Select London *by identifier* so inserting a city into the defaults
        // cannot change which city this test is about.
        let defaults = WorldClockCatalogue.defaults
        let londonIndex = defaults.firstIndex { $0.timeZoneIdentifier == "Europe/London" }!

        var cycle = WorldClockCycle(cities: defaults)
        for _ in 0...londonIndex { cycle.advance() }
        XCTAssertEqual(cycle.mode.city?.displayName, "LONDON")

        // Reorder, London still present: the selection must follow the city,
        // not the slot it used to occupy.
        var reordered = defaults
        reordered.swapAt(0, 1)
        cycle.update(cities: reordered)
        XCTAssertEqual(cycle.mode.city?.displayName, "LONDON")
        XCTAssertEqual(cycle.mode.city?.timeZoneIdentifier, "Europe/London")
    }

    func testUpdatingTheListDropsToTrackWhenTheSelectedCityIsRemoved() {
        var cycle = WorldClockCycle(cities: WorldClockCatalogue.defaults)
        cycle.advance()                       // TOKYO
        XCTAssertEqual(cycle.mode.city?.displayName, "TOKYO")

        let withoutTokyo = WorldClockCatalogue.defaults.filter { $0.timeZoneIdentifier != "Asia/Tokyo" }
        cycle.update(cities: withoutTokyo)
        XCTAssertEqual(
            cycle.mode,
            .track,
            "silently showing a different city than the user selected would be wrong"
        )
    }

    func testDisablingTheSelectedCityDropsToTrack() {
        var cycle = WorldClockCycle(cities: WorldClockCatalogue.defaults)
        cycle.advance()                       // TOKYO

        var cities = WorldClockCatalogue.defaults
        let tokyo = cities.firstIndex { $0.timeZoneIdentifier == "Asia/Tokyo" }!
        cities[tokyo].isEnabled = false
        cycle.update(cities: cities)
        XCTAssertEqual(cycle.mode, .track)
    }

    // MARK: - Persistence

    func testStoreRoundTrips() {
        let defaults = UserDefaults(suiteName: "MusicHUDTests.worldClock")!
        defaults.removePersistentDomain(forName: "MusicHUDTests.worldClock")
        let store = WorldClockStore(defaults: defaults)

        var cities = WorldClockCatalogue.defaults
        cities[0].isEnabled = false
        store.save(cities)
        XCTAssertEqual(store.load(), cities)
    }

    func testEmptyStoreYieldsTheDefaults() {
        let defaults = UserDefaults(suiteName: "MusicHUDTests.worldClockEmpty")!
        defaults.removePersistentDomain(forName: "MusicHUDTests.worldClockEmpty")
        XCTAssertEqual(
            WorldClockStore(defaults: defaults).load(),
            WorldClockCatalogue.defaults
        )
    }

    func testSanitizeDropsInvalidZonesAndDuplicates() {
        let dirty = [
            WorldClockCity(timeZoneIdentifier: "Not/AZone", displayName: "NOWHERE"),
            WorldClockCity(timeZoneIdentifier: "Asia/Tokyo", displayName: "TOKYO"),
            WorldClockCity(timeZoneIdentifier: "Asia/Tokyo", displayName: "TOKYO AGAIN"),
            WorldClockCity(timeZoneIdentifier: "Europe/London", displayName: "LONDON"),
        ]
        let clean = WorldClockStore.sanitized(dirty)
        XCTAssertEqual(clean.map(\.timeZoneIdentifier), ["Asia/Tokyo", "Europe/London"])
    }

    func testSanitizeNeverReturnsAnEmptyList() {
        let clean = WorldClockStore.sanitized([
            WorldClockCity(timeZoneIdentifier: "Not/AZone", displayName: "NOWHERE")
        ])
        XCTAssertEqual(clean, WorldClockCatalogue.defaults)
    }
}
