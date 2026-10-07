import Foundation

/// Persists the user's language choice.
///
/// WHY ITS OWN KEY
/// Adding a field to `HUDSettings` would make every previously stored blob fail
/// to decode — Swift's synthesised `Codable` requires every key — silently
/// resetting the user's window position, audio source and appearance. A separate
/// key has no migration cost at all, which is exactly what the brief asks for.
///
/// Absence is meaningful: it means "the user has never chosen", and only then
/// does the system language decide.
public struct LanguageStore {
    private static let key = "MusicHUD.language.v1"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// The stored choice, or `nil` if the user has never chosen one.
    public func load() -> AppLanguage? {
        guard let raw = defaults.string(forKey: Self.key) else { return nil }
        return AppLanguage(rawValue: raw)
    }

    public func save(_ language: AppLanguage) {
        defaults.set(language.rawValue, forKey: Self.key)
    }

    /// Forgets the choice, so the system language applies again.
    public func clear() {
        defaults.removeObject(forKey: Self.key)
    }
}
