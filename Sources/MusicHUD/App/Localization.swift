import Foundation
import MusicHUDCore
import SwiftUI

/// The app's current language, and the string lookup used outside SwiftUI.
///
/// HOW LOCALISATION IS WIRED
/// * SwiftUI views use `Text("some.key")`. SwiftUI resolves a
///   `LocalizedStringKey` against `Bundle.main` for the locale in the
///   environment, so the root view carries `.environment(\.locale, …)` and a
///   language change re-renders them immediately — no restart, no duplicated
///   views, no dictionary.
/// * AppKit does not read the SwiftUI environment, so `NSMenu` items come from
///   `string(_:)` here, which reads the same `.lproj` tables explicitly. The
///   status menu is rebuilt on every open, so it picks up a change at once.
///
/// The published `language` is what makes the switch instant: views that read
/// strings through `string(_:)` observe this object and re-render.
@MainActor
final class Localization: ObservableObject {

    /// The language in use. Changing it re-resolves the bundle and republishes.
    @Published private(set) var language: AppLanguage

    /// The bundle holding the `.lproj` tables.
    private let container: Bundle

    private var bundle: Bundle?

    init(
        stored: AppLanguage?,
        container: Bundle = .main
    ) {
        self.container = container
        let resolved = AppLanguageResolver.resolve(stored: stored)
        self.language = resolved
        self.bundle = LocalizationBundle.bundle(for: resolved, in: container)
    }

    /// The locale to hand to SwiftUI's `\.locale`.
    var locale: Locale {
        Locale(identifier: AppLanguageResolver.localeIdentifier(for: language))
    }

    /// Switches language. Cheap: one bundle lookup, and one published change.
    func setLanguage(_ newLanguage: AppLanguage) {
        guard newLanguage != language else { return }
        language = newLanguage
        bundle = LocalizationBundle.bundle(for: newLanguage, in: container)
    }

    /// A localised string for the current language.
    func string(_ key: String) -> String {
        bundle?.localizedString(forKey: key, value: nil, table: nil) ?? key
    }

    /// A localised format string with arguments.
    func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: string(key), arguments: arguments)
    }

    /// A localised string for an arbitrary language, for previews and tests.
    func string(_ key: String, language: AppLanguage) -> String {
        LocalizationBundle.bundle(for: language, in: container)?
            .localizedString(forKey: key, value: nil, table: nil) ?? key
    }
}

/// Shorthand used at AppKit call sites.
extension Localization {
    subscript(key: String) -> String { string(key) }
}

/// A localised string in the app's current language.
///
/// Deliberately a free function taking the app state: views already hold
/// `app`, so this keeps call sites to `L(app, "some.key")` without threading a
/// `Localization` through every initialiser, and without duplicating any view.
@MainActor
func L(_ app: AppState, _ key: String) -> String {
    app.localization.string(key)
}

/// A localised string in the app's current language, for views that do not hold
/// the app state. Reads the same process-wide instance the app keeps in sync.
@MainActor
func L(_ key: String) -> String {
    AppLocalization.shared.string(key)
}

/// The same lookup for the diagnostics panel, which is handed the capture
/// service rather than the whole app state.
@MainActor
func L(_ service: AudioCaptureService, _ key: String) -> String {
    AppLocalization.shared.string(key)
}

/// The process-wide localisation, so AppKit-only call sites (the diagnostics
/// window) can resolve strings without threading the app state through.
@MainActor
enum AppLocalization {
    static var shared = Localization(stored: LanguageStore().load())
}
