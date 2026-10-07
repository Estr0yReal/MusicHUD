import Foundation

/// One entry in the World Clock rotation.
///
/// `displayName` is stored rather than derived: `TimeZone.localizedName` returns
/// a *localised* place name ("东京", "伦敦"), and the HUD's caption is set in
/// tracked Latin capitals like the rest of the card.
public struct WorldClockCity: Codable, Equatable, Sendable, Identifiable {
    /// A real IANA identifier. Never a hand-rolled UTC offset.
    public var timeZoneIdentifier: String
    /// Caption text, e.g. `TOKYO`.
    public var displayName: String
    /// Whether this city takes part in the click rotation.
    public var isEnabled: Bool
    /// Falls back to the identifier when a curated abbreviation is absent, and
    /// is always used in preference to the system's when the system only
    /// yields a bare offset (see `shortTimeZoneName`).
    public var standardAbbreviation: String
    public var daylightAbbreviation: String

    public var id: String { timeZoneIdentifier }

    public init(
        timeZoneIdentifier: String,
        displayName: String,
        isEnabled: Bool = true,
        standardAbbreviation: String = "",
        daylightAbbreviation: String = ""
    ) {
        self.timeZoneIdentifier = timeZoneIdentifier
        self.displayName = displayName
        self.isEnabled = isEnabled
        self.standardAbbreviation = standardAbbreviation
        self.daylightAbbreviation = daylightAbbreviation
    }

    /// Stable key for the app's localisation tables.
    ///
    /// Derived from the IANA identifier rather than stored, so a city cannot be
    /// added without a key and silently fall back to its English name.
    public var localizationKey: String {
        switch timeZoneIdentifier {
        case "Asia/Tokyo": return "city.tokyo"
        case "Asia/Shanghai": return "city.shanghai"
        case "Europe/London": return "city.london"
        case "America/New_York": return "city.newYork"
        case "America/Los_Angeles": return "city.losAngeles"
        case "Asia/Hong_Kong": return "city.hongKong"
        case "Asia/Singapore": return "city.singapore"
        case "Asia/Seoul": return "city.seoul"
        case "Asia/Kolkata": return "city.mumbai"
        case "Asia/Dubai": return "city.dubai"
        case "Europe/Paris": return "city.paris"
        case "Europe/Berlin": return "city.berlin"
        case "Europe/Moscow": return "city.moscow"
        case "Australia/Sydney": return "city.sydney"
        case "Pacific/Auckland": return "city.auckland"
        case "America/Chicago": return "city.chicago"
        case "America/Sao_Paulo": return "city.saoPaulo"
        case "UTC": return "city.utc"
        default: return "city.\(timeZoneIdentifier)"
        }
    }

    /// The resolved time zone, or `nil` if the identifier is not on this system.
    public var timeZone: TimeZone? {
        TimeZone(identifier: timeZoneIdentifier)
    }

    /// Whether the identifier resolves on this system.
    public var isValid: Bool { timeZone != nil }
}

public extension WorldClockCity {

    /// Short time-zone name for a given instant, e.g. `JST`, `BST`, `EDT`.
    ///
    /// SDK BEHAVIOUR, VERIFIED ON macOS 15.5: `TimeZone.localizedName(for:locale:)`
    /// returns `EDT`/`EST` and `PDT`/`PST` for the US zones, but only a bare
    /// offset for others — `GMT+9` for Asia/Tokyo and `GMT+1`/`GMT` for
    /// Europe/London. `TimeZone.abbreviation(for:)` behaves the same way, and
    /// returning `GMT+9` where the brief expects `JST` is not acceptable.
    ///
    /// So: the system value is used whenever it carries identity, and the
    /// curated abbreviation is used only when the system returned a bare
    /// offset. **DST is still decided by the system** via
    /// `isDaylightSavingTime(for:)` — no offset is ever computed here.
    func shortTimeZoneName(at date: Date, locale: Locale = Locale(identifier: "en_US")) -> String {
        guard let timeZone else { return "" }

        let isDaylight = timeZone.isDaylightSavingTime(for: date)
        let systemName = timeZone.localizedName(
            for: isDaylight ? .shortDaylightSaving : .shortStandard,
            locale: locale
        ) ?? ""

        if !Self.isBareOffset(systemName) { return systemName }

        let curated = isDaylight ? daylightAbbreviation : standardAbbreviation
        return curated.isEmpty ? systemName : curated
    }

    /// `true` for names like `GMT+9`, `GMT-5`, which identify nothing.
    static func isBareOffset(_ name: String) -> Bool {
        guard name.hasPrefix("GMT") || name.hasPrefix("UTC") else { return false }
        return name.contains("+") || name.contains("-")
    }

    /// Caption line for the display, e.g. `TOKYO · JST`.
    func caption(at date: Date, locale: Locale = Locale(identifier: "en_US")) -> String {
        let abbreviation = shortTimeZoneName(at: date, locale: locale)
        return abbreviation.isEmpty ? displayName : "\(displayName) · \(abbreviation)"
    }

    /// Local wall-clock time in this city, formatted `HH:MM:SS`.
    func timeString(at date: Date) -> String {
        guard let timeZone else { return "--:--:--" }
        return HUDTimeFormatter.wallClock(date, timeZone: timeZone)
    }
}

/// The cities offered in Settings.
///
/// A short curated list, as the brief allows — deliberately not a city database.
public enum WorldClockCatalogue {

    /// The default rotation: Track → Tokyo → Shanghai → London → New York → LA.
    ///
    /// Verified on macOS 15.5: `TimeZone.localizedName` returns the bare offset
    /// `GMT+8` for Asia/Shanghai, so the curated `CST` is what actually reaches
    /// the display — the same fallback Tokyo and London rely on. Shanghai has no
    /// daylight saving, so both abbreviations are `CST`.
    public static let defaults: [WorldClockCity] = [
        WorldClockCity(
            timeZoneIdentifier: "Asia/Tokyo",
            displayName: "TOKYO",
            standardAbbreviation: "JST",
            daylightAbbreviation: "JST"
        ),
        WorldClockCity(
            timeZoneIdentifier: "Asia/Shanghai",
            displayName: "SHANGHAI",
            standardAbbreviation: "CST",
            daylightAbbreviation: "CST"
        ),
        WorldClockCity(
            timeZoneIdentifier: "Europe/London",
            displayName: "LONDON",
            standardAbbreviation: "GMT",
            daylightAbbreviation: "BST"
        ),
        WorldClockCity(
            timeZoneIdentifier: "America/New_York",
            displayName: "NEW YORK",
            standardAbbreviation: "EST",
            daylightAbbreviation: "EDT"
        ),
        WorldClockCity(
            timeZoneIdentifier: "America/Los_Angeles",
            displayName: "LOS ANGELES",
            standardAbbreviation: "PST",
            daylightAbbreviation: "PDT"
        ),
    ]

    /// Extra cities a user may add. Every identifier is a real IANA zone.
    public static let additional: [WorldClockCity] = [
        WorldClockCity(timeZoneIdentifier: "Asia/Hong_Kong", displayName: "HONG KONG", standardAbbreviation: "HKT", daylightAbbreviation: "HKT"),
        WorldClockCity(timeZoneIdentifier: "Asia/Singapore", displayName: "SINGAPORE", standardAbbreviation: "SGT", daylightAbbreviation: "SGT"),
        WorldClockCity(timeZoneIdentifier: "Asia/Seoul", displayName: "SEOUL", standardAbbreviation: "KST", daylightAbbreviation: "KST"),
        WorldClockCity(timeZoneIdentifier: "Asia/Kolkata", displayName: "MUMBAI", standardAbbreviation: "IST", daylightAbbreviation: "IST"),
        WorldClockCity(timeZoneIdentifier: "Asia/Dubai", displayName: "DUBAI", standardAbbreviation: "GST", daylightAbbreviation: "GST"),
        WorldClockCity(timeZoneIdentifier: "Europe/Paris", displayName: "PARIS", standardAbbreviation: "CET", daylightAbbreviation: "CEST"),
        WorldClockCity(timeZoneIdentifier: "Europe/Berlin", displayName: "BERLIN", standardAbbreviation: "CET", daylightAbbreviation: "CEST"),
        WorldClockCity(timeZoneIdentifier: "Europe/Moscow", displayName: "MOSCOW", standardAbbreviation: "MSK", daylightAbbreviation: "MSK"),
        WorldClockCity(timeZoneIdentifier: "Australia/Sydney", displayName: "SYDNEY", standardAbbreviation: "AEST", daylightAbbreviation: "AEDT"),
        WorldClockCity(timeZoneIdentifier: "Pacific/Auckland", displayName: "AUCKLAND", standardAbbreviation: "NZST", daylightAbbreviation: "NZDT"),
        WorldClockCity(timeZoneIdentifier: "America/Chicago", displayName: "CHICAGO", standardAbbreviation: "CST", daylightAbbreviation: "CDT"),
        WorldClockCity(timeZoneIdentifier: "America/Sao_Paulo", displayName: "SÃO PAULO", standardAbbreviation: "BRT", daylightAbbreviation: "BRT"),
        WorldClockCity(timeZoneIdentifier: "UTC", displayName: "UTC", standardAbbreviation: "UTC", daylightAbbreviation: "UTC"),
    ]

    /// Everything selectable in Settings, defaults first.
    public static var all: [WorldClockCity] { defaults + additional }
}
