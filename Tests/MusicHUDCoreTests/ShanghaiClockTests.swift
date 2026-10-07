import XCTest
@testable import MusicHUDCore

/// Phase 7 addition: the Shanghai entry in the World Clock.
///
/// Offset and DST assertions are made against `Foundation.TimeZone` rather than
/// against literals this project could have got wrong — the point of these tests
/// is that the *system* time-zone database says what we claim, on this machine,
/// at a fixed instant.
final class ShanghaiClockTests: XCTestCase {

    /// 2025-01-01 00:00:00 UTC — northern winter (EST/GMT).
    private let winter = Date(timeIntervalSince1970: 1_735_689_600)
    /// 2025-07-01 00:00:00 UTC — northern summer (EDT/BST).
    private let summer = Date(timeIntervalSince1970: 1_751_328_000)

    private var shanghai: WorldClockCity {
        WorldClockCatalogue.defaults.first { $0.timeZoneIdentifier == "Asia/Shanghai" }!
    }

    private func city(_ identifier: String) -> WorldClockCity {
        WorldClockCatalogue.all.first { $0.timeZoneIdentifier == identifier }
            ?? WorldClockCity(timeZoneIdentifier: identifier, displayName: identifier)
    }

    /// Offset difference in whole hours between two zones at an instant.
    private func hourGap(_ a: String, _ b: String, at date: Date) -> Double {
        let ta = TimeZone(identifier: a)!
        let tb = TimeZone(identifier: b)!
        return Double(ta.secondsFromGMT(for: date) - tb.secondsFromGMT(for: date)) / 3600
    }

    // MARK: - 1. It exists and resolves

    func testShanghaiCanBeCreatedFromItsIANAIdentifier() {
        let zone = TimeZone(identifier: "Asia/Shanghai")
        XCTAssertNotNil(zone, "Asia/Shanghai must resolve from the system database")
        XCTAssertEqual(zone?.identifier, "Asia/Shanghai")
        XCTAssertTrue(shanghai.isValid)
        XCTAssertEqual(shanghai.displayName, "SHANGHAI")
    }

    // MARK: - 2. Abbreviation

    func testShanghaiAbbreviationIsCST() {
        // VERIFIED: macOS returns the bare offset `GMT+8` for Asia/Shanghai, so
        // the curated fallback is what reaches the display — the same path Tokyo
        // and London use. Assert both that the system gives a bare offset (the
        // reason the fallback exists) and that CST is what comes out.
        let system = TimeZone(identifier: "Asia/Shanghai")!
            .localizedName(for: .shortStandard, locale: Locale(identifier: "en_US")) ?? ""
        XCTAssertTrue(
            WorldClockCity.isBareOffset(system),
            "if macOS ever returns a real abbreviation this fallback becomes dead code and should be revisited"
        )

        XCTAssertEqual(shanghai.shortTimeZoneName(at: winter), "CST")
        XCTAssertEqual(shanghai.shortTimeZoneName(at: summer), "CST")
        XCTAssertEqual(shanghai.caption(at: winter), "SHANGHAI · CST")
    }

    // MARK: - 3. UTC offset

    func testShanghaiIsUTCPlusEight() {
        let zone = TimeZone(identifier: "Asia/Shanghai")!
        XCTAssertEqual(zone.secondsFromGMT(for: winter), 8 * 3600)
        XCTAssertEqual(zone.secondsFromGMT(for: summer), 8 * 3600)
    }

    // MARK: - 4. No daylight saving

    func testShanghaiHasNoDaylightSaving() {
        let zone = TimeZone(identifier: "Asia/Shanghai")!
        XCTAssertFalse(zone.isDaylightSavingTime(for: winter))
        XCTAssertFalse(zone.isDaylightSavingTime(for: summer))
        // And the two curated abbreviations being identical is the declaration of
        // that fact, so neither can drift.
        XCTAssertEqual(shanghai.standardAbbreviation, shanghai.daylightAbbreviation)
    }

    // MARK: - 5. Against Tokyo

    func testShanghaiIsOneHourBehindTokyo() {
        XCTAssertEqual(hourGap("Asia/Shanghai", "Asia/Tokyo", at: winter), -1)
        // Tokyo has no DST either, so this must hold year-round.
        XCTAssertEqual(hourGap("Asia/Shanghai", "Asia/Tokyo", at: summer), -1)
    }

    func testShanghaiAndTokyoRenderOneHourApart() {
        let tokyo = city("Asia/Tokyo")
        // 00:00 UTC is 08:00 in Shanghai and 09:00 in Tokyo.
        XCTAssertEqual(shanghai.timeString(at: winter), "08:00:00")
        XCTAssertEqual(tokyo.timeString(at: winter), "09:00:00")
    }

    // MARK: - 6. Against London

    func testShanghaiIsEightHoursAheadOfLondonInWinter() {
        XCTAssertEqual(hourGap("Asia/Shanghai", "Europe/London", at: winter), 8)
        // BST puts London on +1, so the gap narrows to 7 in summer.
        XCTAssertEqual(hourGap("Asia/Shanghai", "Europe/London", at: summer), 7)
    }

    // MARK: - 7. Against New York, across DST

    func testShanghaiGapToNewYorkFollowsNewYorkDaylightSaving() {
        // EST is -5 (gap 13); EDT is -4 (gap 12). The change must come from New
        // York's DST, not from Shanghai's — Shanghai has none.
        XCTAssertEqual(hourGap("Asia/Shanghai", "America/New_York", at: winter), 13)
        XCTAssertEqual(hourGap("Asia/Shanghai", "America/New_York", at: summer), 12)

        let newYork = TimeZone(identifier: "America/New_York")!
        XCTAssertFalse(newYork.isDaylightSavingTime(for: winter))
        XCTAssertTrue(newYork.isDaylightSavingTime(for: summer))
    }

    // MARK: - 8. Rotation

    func testShanghaiSitsSecondInTheDefaultRotation() {
        XCTAssertEqual(
            WorldClockCatalogue.defaults.map(\.displayName),
            ["TOKYO", "SHANGHAI", "LONDON", "NEW YORK", "LOS ANGELES"]
        )
    }

    func testShanghaiIsReachedByCycling() {
        var cycle = WorldClockCycle(cities: WorldClockCatalogue.defaults)
        XCTAssertEqual(cycle.mode, .track)

        cycle.advance()
        XCTAssertEqual(cycle.mode.city?.displayName, "TOKYO")
        cycle.advance()
        XCTAssertEqual(cycle.mode.city?.displayName, "SHANGHAI")

        // Walk the rest of the rotation and confirm it wraps back to Track.
        for expected in WorldClockCatalogue.defaults.map(\.displayName).dropFirst(2) {
            cycle.advance()
            XCTAssertEqual(cycle.mode.city?.displayName, expected)
        }
        cycle.advance()
        XCTAssertEqual(cycle.mode, .track)
    }

    // MARK: - 9. Disabling

    func testShanghaiCanBeDisabledAndIsThenSkipped() {
        var cities = WorldClockCatalogue.defaults
        cities[1].isEnabled = false                     // Shanghai off
        var cycle = WorldClockCycle(cities: cities)

        var visited: [String] = []
        for _ in 0..<cities.filter(\.isEnabled).count {
            cycle.advance()
            visited.append(cycle.mode.city?.displayName ?? "TRACK")
        }
        XCTAssertEqual(visited, ["TOKYO", "LONDON", "NEW YORK", "LOS ANGELES"])
    }

    func testDisablingShanghaiWhileItIsSelectedDropsBackToTrack() {
        var cycle = WorldClockCycle(cities: WorldClockCatalogue.defaults)
        cycle.advance(); cycle.advance()
        XCTAssertEqual(cycle.mode.city?.displayName, "SHANGHAI")

        var cities = WorldClockCatalogue.defaults
        cities[1].isEnabled = false
        cycle.update(cities: cities)
        XCTAssertEqual(cycle.mode, .track)
    }

    // MARK: - 10. Deleting

    func testShanghaiCanBeDeleted() {
        let without = WorldClockCatalogue.defaults.filter { $0.timeZoneIdentifier != "Asia/Shanghai" }
        XCTAssertEqual(without.count, 4)
        XCTAssertFalse(without.contains { $0.timeZoneIdentifier == "Asia/Shanghai" })

        // The cycle must simply not offer it any more.
        var cycle = WorldClockCycle(cities: without)
        var visited: [String] = []
        for _ in 0..<without.count {
            cycle.advance()
            visited.append(cycle.mode.city?.displayName ?? "TRACK")
        }
        XCTAssertFalse(visited.contains("SHANGHAI"))
    }

    func testDeletingShanghaiWhileItIsSelectedDropsBackToTrack() {
        var cycle = WorldClockCycle(cities: WorldClockCatalogue.defaults)
        cycle.advance(); cycle.advance()
        XCTAssertEqual(cycle.mode.city?.displayName, "SHANGHAI")

        cycle.update(cities: WorldClockCatalogue.defaults.filter {
            $0.timeZoneIdentifier != "Asia/Shanghai"
        })
        XCTAssertEqual(cycle.mode, .track)
    }

    // MARK: - 11. Restore defaults

    func testRestoringDefaultsBringsShanghaiBack() {
        let cleared = WorldClockCatalogue.defaults.filter { $0.timeZoneIdentifier != "Asia/Shanghai" }
        XCTAssertFalse(cleared.contains { $0.timeZoneIdentifier == "Asia/Shanghai" })

        // "Restore defaults" hands `defaults` straight back, so this is the whole
        // restore path.
        let restored = WorldClockCatalogue.defaults
        XCTAssertTrue(restored.contains { $0.timeZoneIdentifier == "Asia/Shanghai" })
        XCTAssertEqual(restored.count, 5)
    }

    // MARK: - 12. Persistence

    private func freshDefaults(_ name: String) -> UserDefaults {
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    func testShanghaiSurvivesASaveAndReload() {
        let defaults = freshDefaults("MusicHUDTests.shanghai")
        let store = WorldClockStore(defaults: defaults)

        // A user who has reordered and disabled things.
        var cities = WorldClockCatalogue.defaults
        cities.swapAt(0, 4)
        cities[2].isEnabled = false
        store.save(cities)

        let reloaded = WorldClockStore(defaults: defaults).load()
        XCTAssertEqual(reloaded, cities)
        XCTAssertEqual(
            reloaded.first { $0.timeZoneIdentifier == "Asia/Shanghai" }?.isEnabled,
            cities.first { $0.timeZoneIdentifier == "Asia/Shanghai" }?.isEnabled
        )
    }

    func testAFreshStoreIncludesShanghai() {
        let defaults = freshDefaults("MusicHUDTests.shanghaiFresh")
        let loaded = WorldClockStore(defaults: defaults).load()
        XCTAssertTrue(loaded.contains { $0.timeZoneIdentifier == "Asia/Shanghai" })
        XCTAssertEqual(loaded.map(\.displayName), ["TOKYO", "SHANGHAI", "LONDON", "NEW YORK", "LOS ANGELES"])
    }

    // MARK: - Migration of an existing configuration

    func testAnExistingConfigurationGainsShanghaiWithoutLosingItsOrder() {
        // What a Phase 6 user has stored: four cities, no Shanghai.
        let existing = WorldClockCatalogue.defaults.filter { $0.timeZoneIdentifier != "Asia/Shanghai" }
        XCTAssertEqual(existing.count, 4)

        let migrated = WorldClockStore.migrated(existing)
        XCTAssertEqual(
            migrated.map(\.displayName),
            ["TOKYO", "SHANGHAI", "LONDON", "NEW YORK", "LOS ANGELES"],
            "Shanghai is inserted after Tokyo, where it belongs in the rotation"
        )
    }

    func testMigrationPreservesAUsersOwnOrderingAndEnabledState() {
        // A user who moved Los Angeles to the front and turned London off.
        var custom = WorldClockCatalogue.defaults.filter { $0.timeZoneIdentifier != "Asia/Shanghai" }
        custom.swapAt(0, 3)                                   // LA to the front
        let london = custom.firstIndex { $0.timeZoneIdentifier == "Europe/London" }!
        custom[london].isEnabled = false

        let migrated = WorldClockStore.migrated(custom)

        // Every pre-existing city keeps its relative position; Shanghai is the
        // only addition.
        let keptRelative = migrated.map(\.timeZoneIdentifier)
            .filter { $0 != "Asia/Shanghai" }
        XCTAssertEqual(keptRelative, custom.map(\.timeZoneIdentifier))
        XCTAssertEqual(migrated.first?.timeZoneIdentifier, "America/Los_Angeles",
                       "the user's reordering survives")
        XCTAssertEqual(
            migrated.first { $0.timeZoneIdentifier == "Europe/London" }?.isEnabled,
            false,
            "a disabled city must stay disabled"
        )
    }

    func testMigrationDoesNotDuplicateShanghai() {
        let migrated = WorldClockStore.migrated(WorldClockCatalogue.defaults)
        XCTAssertEqual(migrated.count, 5)
        XCTAssertEqual(
            migrated.filter { $0.timeZoneIdentifier == "Asia/Shanghai" }.count,
            1
        )
    }

    func testMigrationAppendsWhenTokyoIsAbsent() {
        let noTokyo = [
            city("Europe/London"),
            city("America/New_York"),
        ]
        let migrated = WorldClockStore.migrated(noTokyo)
        XCTAssertEqual(migrated.first?.timeZoneIdentifier, "Asia/Shanghai")
        XCTAssertEqual(migrated.count, 3)
    }

    func testStoredConfigurationIsMigratedOnlyOnce() {
        let defaults = freshDefaults("MusicHUDTests.shanghaiMigrate")
        let store = WorldClockStore(defaults: defaults)

        // Seed a Phase 6 configuration: a list without Shanghai, and no schema
        // marker, which is exactly what an existing install looks like.
        let existing = WorldClockCatalogue.defaults.filter { $0.timeZoneIdentifier != "Asia/Shanghai" }
        store.save(existing)
        defaults.removeObject(forKey: "MusicHUD.worldClock.schema")

        // First load migrates.
        var loaded = store.load()
        XCTAssertTrue(loaded.contains { $0.timeZoneIdentifier == "Asia/Shanghai" })

        // The user deliberately deletes it.
        loaded.removeAll { $0.timeZoneIdentifier == "Asia/Shanghai" }
        store.save(loaded)

        // Second load must respect that, not resurrect it.
        let reloaded = store.load()
        XCTAssertFalse(
            reloaded.contains { $0.timeZoneIdentifier == "Asia/Shanghai" },
            "a deliberate deletion must survive a relaunch"
        )
        XCTAssertEqual(reloaded.count, 4)
    }

    // MARK: - Nothing else moved

    func testTheOtherFourCitiesBehaveExactlyAsBefore() {
        // This addition must not have disturbed the existing entries.
        XCTAssertEqual(city("Asia/Tokyo").shortTimeZoneName(at: winter), "JST")
        XCTAssertEqual(city("Europe/London").shortTimeZoneName(at: winter), "GMT")
        XCTAssertEqual(city("Europe/London").shortTimeZoneName(at: summer), "BST")
        XCTAssertEqual(city("America/New_York").shortTimeZoneName(at: winter), "EST")
        XCTAssertEqual(city("America/New_York").shortTimeZoneName(at: summer), "EDT")
        XCTAssertEqual(city("America/Los_Angeles").shortTimeZoneName(at: winter), "PST")
        XCTAssertEqual(city("America/Los_Angeles").shortTimeZoneName(at: summer), "PDT")
    }

    func testCatalogueStillHasNoDuplicateIdentifiers() {
        let identifiers = WorldClockCatalogue.all.map(\.timeZoneIdentifier)
        XCTAssertEqual(Set(identifiers).count, identifiers.count)
        XCTAssertEqual(identifiers.count, WorldClockCatalogue.defaults.count + WorldClockCatalogue.additional.count)
        XCTAssertFalse(WorldClockCatalogue.additional.contains { $0.timeZoneIdentifier == "Asia/Shanghai" },
                       "Shanghai belongs to the defaults now, not the optional extras")
    }
}
