import Foundation

/// Persists the World Clock city list.
///
/// Stored under its **own** UserDefaults key rather than as a field on
/// `HUDSettings`. Adding a field to that struct would have made every existing
/// stored blob fail to decode — Swift's synthesised `Codable` requires every key
/// — which would silently reset the user's window position, audio source and
/// appearance on first launch after the upgrade. A separate key has no such
/// migration cost, and the city list is a separate concern anyway.
public struct WorldClockStore {
    private static let key = "MusicHUD.worldClock.v1"

    /// Schema marker for one-off migrations of the stored city list.
    ///
    /// Needed because the migration must run exactly once. Without it, a user
    /// who deliberately *deleted* Shanghai would find it back on the next
    /// launch — the same "helpful" behaviour that makes an app untrustworthy.
    private static let schemaKey = "MusicHUD.worldClock.schema"
    private static let currentSchema = 2

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Loads the configured cities, applying any pending migration.
    public func load() -> [WorldClockCity] {
        guard
            let data = defaults.data(forKey: Self.key),
            let decoded = try? JSONDecoder().decode([WorldClockCity].self, from: data)
        else {
            // Fresh install: the defaults already include Shanghai.
            defaults.set(Self.currentSchema, forKey: Self.schemaKey)
            return WorldClockCatalogue.defaults
        }

        var cities = Self.sanitized(decoded)
        if defaults.integer(forKey: Self.schemaKey) < Self.currentSchema {
            cities = Self.migrated(cities)
            save(cities)
            defaults.set(Self.currentSchema, forKey: Self.schemaKey)
        }
        return cities
    }

    /// Adds cities introduced after a list was first stored.
    ///
    /// Deliberately *insertive* rather than a reset: the user's own ordering and
    /// enable/disable choices are preserved, and the new city is placed where it
    /// belongs in the default rotation — after Tokyo, which is where it sits in
    /// `defaults`. A user who has reordered things keeps their order.
    public static func migrated(_ cities: [WorldClockCity]) -> [WorldClockCity] {
        var result = cities

        if !result.contains(where: { $0.timeZoneIdentifier == "Asia/Shanghai" }),
           let shanghai = WorldClockCatalogue.defaults.first(where: {
               $0.timeZoneIdentifier == "Asia/Shanghai"
           }) {
            let insertion = result.firstIndex { $0.timeZoneIdentifier == "Asia/Tokyo" }
                .map { $0 + 1 } ?? 0
            result.insert(shanghai, at: min(insertion, result.count))
        }
        return result
    }

    @discardableResult
    public func save(_ cities: [WorldClockCity]) -> Bool {
        guard let data = try? JSONEncoder().encode(cities) else { return false }
        defaults.set(data, forKey: Self.key)
        return true
    }

    public func reset() {
        defaults.removeObject(forKey: Self.key)
    }

    /// Drops entries whose time-zone identifier does not exist on this system,
    /// and guarantees the list is never empty.
    ///
    /// A zone can disappear between OS releases, and an entry pointing at a
    /// missing zone would render `--:--:--` with no explanation.
    public static func sanitized(_ cities: [WorldClockCity]) -> [WorldClockCity] {
        var seen = Set<String>()
        let valid = cities.filter { city in
            guard city.isValid else { return false }
            return seen.insert(city.timeZoneIdentifier).inserted
        }
        return valid.isEmpty ? WorldClockCatalogue.defaults : valid
    }
}
