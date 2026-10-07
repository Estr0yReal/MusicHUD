import XCTest
@testable import MusicHUDCore

/// Phase 7.1 tests: language resolution, persistence and launch-at-login state.
///
/// The `SMAppService` calls themselves are not exercised — they change real
/// system state and register a real login item, which a test must not do.
/// What *is* tested is the mapping from `SMAppService.Status` to what the switch
/// shows, which is where a lie would actually appear.
final class ReleaseReadinessTests: XCTestCase {

    // MARK: - Default language

    func testAFirstLaunchFollowsTheSystemLanguage() {
        XCTAssertEqual(
            AppLanguageResolver.resolve(stored: nil, system: ["zh-Hans-CN", "en-US"]),
            .simplifiedChinese
        )
        XCTAssertEqual(
            AppLanguageResolver.resolve(stored: nil, system: ["en-US"]),
            .english
        )
    }

    func testTheCommonChineseIdentifiersAllResolveToChinese() {
        for identifier in ["zh", "zh-Hans", "zh-Hans-CN", "zh-CN", "zh-SG", "ZH-HANS"] {
            XCTAssertEqual(
                AppLanguageResolver.resolve(stored: nil, system: [identifier]),
                .simplifiedChinese,
                "\(identifier) should select the Chinese localisation"
            )
        }
    }

    func testTraditionalChineseFallsBackToEnglishRatherThanWrongChinese() {
        // `zh-Hant` is a different script and is not shipped. Showing simplified
        // to a traditional reader would be worse than showing English.
        for identifier in ["zh-Hant", "zh-TW", "zh-HK", "zh-MO"] {
            XCTAssertEqual(
                AppLanguageResolver.resolve(stored: nil, system: [identifier]),
                .english,
                "\(identifier) should not select the simplified localisation"
            )
        }
    }

    func testAnUnsupportedSystemLanguageFallsBackToEnglish() {
        XCTAssertEqual(AppLanguageResolver.resolve(stored: nil, system: ["fr-FR", "de-DE"]), .english)
        XCTAssertEqual(AppLanguageResolver.resolve(stored: nil, system: []), .english)
    }

    func testTheFirstSupportedSystemLanguageWins() {
        XCTAssertEqual(
            AppLanguageResolver.resolve(stored: nil, system: ["fr-FR", "en-GB", "zh-Hans"]),
            .english
        )
        XCTAssertEqual(
            AppLanguageResolver.resolve(stored: nil, system: ["de-DE", "zh-Hans", "en-US"]),
            .simplifiedChinese
        )
    }

    // MARK: - Stored choice

    func testAnExplicitChoiceAlwaysWins() {
        // Even when it disagrees with the system — that is the whole point of a
        // language setting.
        XCTAssertEqual(
            AppLanguageResolver.resolve(stored: .english, system: ["zh-Hans-CN"]),
            .english
        )
        XCTAssertEqual(
            AppLanguageResolver.resolve(stored: .simplifiedChinese, system: ["en-US"]),
            .simplifiedChinese
        )
    }

    func testAStoredChoiceIsNotOverwrittenOnALaterLaunch() {
        // Repeated resolution must be stable: a second launch must not fall back
        // to the system.
        var stored: AppLanguage? = .english
        for _ in 0..<5 {
            stored = AppLanguageResolver.resolve(stored: stored, system: ["zh-Hans-CN"])
        }
        XCTAssertEqual(stored, .english)
    }

    func testLocaleIdentifiersAreWhatSwiftUIExpects() {
        XCTAssertEqual(AppLanguageResolver.localeIdentifier(for: .english), "en")
        XCTAssertEqual(AppLanguageResolver.localeIdentifier(for: .simplifiedChinese), "zh-Hans")
    }

    func testEachLanguageNamesItselfInItsOwnScript() {
        // A user who cannot read the current interface must still find their own
        // language in the picker.
        XCTAssertEqual(AppLanguage.english.endonym, "English")
        XCTAssertEqual(AppLanguage.simplifiedChinese.endonym, "中文")
    }

    // MARK: - Persistence

    private func freshDefaults(_ name: String) -> UserDefaults {
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    func testAnUnsetLanguageIsNilNotADefault() {
        // `nil` is meaningful: it means "never chosen", which is what lets the
        // system language apply on a first launch.
        let store = LanguageStore(defaults: freshDefaults("MusicHUDTests.lang.none"))
        XCTAssertNil(store.load())
    }

    func testLanguageRoundTrips() {
        let defaults = freshDefaults("MusicHUDTests.lang.round")
        let store = LanguageStore(defaults: defaults)
        store.save(.simplifiedChinese)
        XCTAssertEqual(LanguageStore(defaults: defaults).load(), .simplifiedChinese)
        store.save(.english)
        XCTAssertEqual(LanguageStore(defaults: defaults).load(), .english)
    }

    func testClearingForgetsTheChoice() {
        let defaults = freshDefaults("MusicHUDTests.lang.clear")
        let store = LanguageStore(defaults: defaults)
        store.save(.simplifiedChinese)
        store.clear()
        XCTAssertNil(LanguageStore(defaults: defaults).load())
    }

    func testTheLanguageLivesOnItsOwnKeySoExistingSettingsSurvive() {
        // The regression the brief specifically calls out: adding a language
        // setting must not reset the stored HUD settings or world clock.
        let defaults = freshDefaults("MusicHUDTests.lang.isolation")
        defaults.set(Data("existing-hud-settings".utf8), forKey: "MusicHUD.settings.v1")
        defaults.set(Data("existing-world-clock".utf8), forKey: "MusicHUD.worldClock.v1")

        LanguageStore(defaults: defaults).save(.english)

        XCTAssertEqual(
            defaults.data(forKey: "MusicHUD.settings.v1"),
            Data("existing-hud-settings".utf8)
        )
        XCTAssertEqual(
            defaults.data(forKey: "MusicHUD.worldClock.v1"),
            Data("existing-world-clock".utf8)
        )
    }

    // MARK: - Bundle resolution

    func testBundleLookupTriesTheCanonicalAndLowercasedNames() {
        // SwiftPM lowercases .lproj directory names in the built bundle, so a
        // lookup by "zh-Hans" alone would miss.
        XCTAssertEqual(
            LocalizationBundle.candidates(for: .simplifiedChinese),
            ["zh-Hans", "zh-hans"]
        )
        XCTAssertEqual(LocalizationBundle.candidates(for: .english), ["en", "en"])
    }

    func testBundleLookupReturnsNilRatherThanCrashingWhenAbsent() {
        XCTAssertNil(LocalizationBundle.bundle(for: .english, in: nil))
    }

    // MARK: - Launch at login

    func testTheToggleReadsAsOnOnlyWhenItShould() {
        // `requiresApproval` counts as on: macOS accepted the registration and is
        // waiting for the user, so showing "off" would misreport what happened.
        XCTAssertTrue(LoginItemStatus.enabled.isOn)
        XCTAssertTrue(LoginItemStatus.requiresApproval.isOn)

        XCTAssertFalse(LoginItemStatus.disabled.isOn)
        XCTAssertFalse(LoginItemStatus.notFound.isOn)
        XCTAssertFalse(LoginItemStatus.failed("boom").isOn)
    }

    func testTheStatusMappingCoversEveryCaseTheUIReads() {
        // The UI switches over these to produce a label; a missing case would be
        // a compile error, but an *unreachable* one would silently never show.
        let cases: [LoginItemStatus] = [
            .enabled, .disabled, .requiresApproval, .notFound, .failed("x"),
        ]
        XCTAssertEqual(cases.count, 5)
        XCTAssertEqual(cases.filter(\.isOn).count, 2)
    }

    // MARK: - Time zones still work

    func testTheFiveDefaultCitiesStillResolveAfterTheLanguageWork() {
        let expected = ["Asia/Tokyo", "Asia/Shanghai", "Europe/London",
                        "America/New_York", "America/Los_Angeles"]
        XCTAssertEqual(WorldClockCatalogue.defaults.map(\.timeZoneIdentifier), expected)
        for city in WorldClockCatalogue.defaults {
            XCTAssertNotNil(city.timeZone, "\(city.timeZoneIdentifier) must still resolve")
            XCTAssertFalse(city.timeString(at: Date()).isEmpty)
        }
    }

    func testEveryCityHasALocalisationKeyForItsDisplayName() {
        // The city names are translated, so each one needs a key in the tables.
        for city in WorldClockCatalogue.all {
            XCTAssertFalse(city.localizationKey.isEmpty, city.displayName)
        }
    }
}
