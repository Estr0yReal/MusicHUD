import Foundation

/// A language the app can display itself in.
///
/// Deliberately a closed, small set: the app ships two localisations, and a
/// free-form language code would only invite a code path that can never be
/// tested.
public enum AppLanguage: String, CaseIterable, Codable, Sendable, Identifiable {
    case english = "en"
    /// Simplified Chinese. The `.lproj` directory is `zh-Hans`, which SwiftPM
    /// lowercases to `zh-hans` in the built bundle — see `LocalizationBundle`.
    case simplifiedChinese = "zh-Hans"

    public var id: String { rawValue }

    /// Name shown **in the language itself**, the convention for a language
    /// picker: a user who cannot read the current interface language must still
    /// be able to find their own.
    public var endonym: String {
        switch self {
        case .english: return "English"
        case .simplifiedChinese: return "中文"
        }
    }
}

/// Chooses the language to start in.
///
/// Separate from the setting itself so the rule can be tested: an explicit
/// choice always wins, and only a first launch falls back to the system.
public enum AppLanguageResolver {

    /// - Parameter stored: the user's explicit choice, or `nil` if never made.
    /// - Parameter system: the system's preferred languages, most preferred first.
    public static func resolve(stored: AppLanguage?, system: [String]) -> AppLanguage {
        // An explicit choice is never overridden — not by a system language
        // change, and not on a later launch.
        if let stored { return stored }

        for identifier in system {
            let lowered = identifier.lowercased()
            // `zh`, `zh-Hans`, `zh-CN`, `zh-SG` all mean the simplified
            // localisation. `zh-Hant`/`zh-TW`/`zh-HK` are traditional, which is
            // not shipped, so those users get English rather than the wrong
            // Chinese.
            if lowered == "zh" || lowered.hasPrefix("zh-hans")
                || lowered.hasPrefix("zh-cn") || lowered.hasPrefix("zh-sg") {
                return .simplifiedChinese
            }
            if lowered.hasPrefix("en") { return .english }
        }
        return .english
    }

    /// The system's preferred languages, most preferred first.
    public static var systemLanguages: [String] {
        Locale.preferredLanguages
    }

    /// Resolves using the real system language list.
    public static func resolve(stored: AppLanguage?) -> AppLanguage {
        resolve(stored: stored, system: systemLanguages)
    }

    /// The BCP-47 identifier to hand to SwiftUI's `\.locale`.
    public static func localeIdentifier(for language: AppLanguage) -> String {
        switch language {
        case .english: return "en"
        case .simplifiedChinese: return "zh-Hans"
        }
    }
}

/// Resolves the `.lproj` bundle for a language.
///
/// WHY THIS IS NOT JUST `Bundle.main`
/// Two reasons. The app ships its own language setting, so the language in use
/// is not necessarily the system's. And SwiftPM **lowercases** `.lproj`
/// directory names when it copies them into the resource bundle, so a lookup by
/// the canonical identifier (`zh-Hans`) misses while `zh-hans` hits. Verified on
/// macOS 15.5: `Bundle.module.localizations` returns `["zh-hans", "en"]`.
public enum LocalizationBundle {

    /// The candidate strings-table names to try for a language, in order.
    public static func candidates(for language: AppLanguage) -> [String] {
        [language.rawValue, language.rawValue.lowercased()]
    }

    /// Loads the localisation bundle, falling back to English and then to the
    /// bundle that holds the tables at all.
    public static func bundle(
        for language: AppLanguage,
        in container: Bundle?,
        resourceName: String = "Localizable"
    ) -> Bundle? {
        guard let container else { return nil }

        for candidate in candidates(for: language) {
            if let path = container.path(forResource: candidate, ofType: "lproj"),
               let bundle = Bundle(path: path) {
                return bundle
            }
        }
        // Fall back to English so an unknown or missing language shows real
        // strings rather than raw keys.
        for candidate in candidates(for: .english) {
            if let path = container.path(forResource: candidate, ofType: "lproj"),
               let bundle = Bundle(path: path) {
                return bundle
            }
        }
        return nil
    }
}
