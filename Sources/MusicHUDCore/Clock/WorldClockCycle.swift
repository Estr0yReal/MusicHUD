import Foundation

/// What the large display is currently showing.
public enum ClockDisplayMode: Equatable, Sendable {
    /// The track-derived value, i.e. whatever `ClockMode` is configured.
    case track
    /// Wall-clock time in one city.
    case worldClock(WorldClockCity)

    public var isWorldClock: Bool {
        if case .worldClock = self { return true }
        return false
    }

    public var city: WorldClockCity? {
        if case .worldClock(let city) = self { return city }
        return nil
    }
}

/// Click-to-cycle rotation through the enabled cities, with Track as the home
/// position.
///
/// Deliberately a small value type rather than view state: the cycle order, the
/// disabled-city filtering and the wrap back to Track are exactly the parts that
/// are worth testing without a window on screen.
///
/// Order is: Track → city 1 → city 2 → … → city n → Track.
public struct WorldClockCycle: Equatable, Sendable {

    /// Cities in rotation order. Disabled cities are excluded automatically, so
    /// toggling one in Settings cannot leave the cycle pointing at a hidden city.
    public private(set) var cities: [WorldClockCity]

    /// `nil` means Track mode.
    public private(set) var index: Int?

    public init(cities: [WorldClockCity] = []) {
        self.cities = cities.filter(\.isEnabled)
        self.index = nil
    }

    public var mode: ClockDisplayMode {
        guard let index, cities.indices.contains(index) else { return .track }
        return .worldClock(cities[index])
    }

    public var isAtTrack: Bool { mode == .track }

    /// Advances one step, wrapping past the last city back to Track.
    public mutating func advance() {
        guard !cities.isEmpty else {
            index = nil
            return
        }
        guard let current = index else {
            index = 0
            return
        }
        let next = current + 1
        index = next < cities.count ? next : nil
    }

    /// Returns to Track mode.
    public mutating func resetToTrack() {
        index = nil
    }

    /// Replaces the city list, keeping the current position if it still exists.
    ///
    /// Called when Settings changes the list. If the selected city was disabled
    /// or removed, the cycle drops back to Track rather than silently showing a
    /// different city than the user selected.
    public mutating func update(cities newCities: [WorldClockCity]) {
        let selectedIdentifier = mode.city?.timeZoneIdentifier
        cities = newCities.filter(\.isEnabled)

        guard let selectedIdentifier else {
            index = nil
            return
        }
        index = cities.firstIndex { $0.timeZoneIdentifier == selectedIdentifier }
    }
}

/// Formats the large display for either mode.
public enum WorldClockFormatter {

    /// Text shown on the seven-segment display.
    public static func timeText(
        mode: ClockDisplayMode,
        date: Date,
        trackText: String
    ) -> String {
        switch mode {
        case .track:
            return trackText
        case .worldClock(let city):
            return city.timeString(at: date)
        }
    }

    /// Caption under the digits.
    ///
    /// Track mode uses the literal `TRACK` the brief specifies; the city caption
    /// is `<CITY> · <ABBR>`, which carries its own context so no `WORLD` or
    /// `TIME` prefix is needed.
    public static func caption(
        mode: ClockDisplayMode,
        date: Date,
        trackCaption: String,
        locale: Locale = Locale(identifier: "en_US")
    ) -> String {
        switch mode {
        case .track:
            return trackCaption
        case .worldClock(let city):
            return city.caption(at: date, locale: locale)
        }
    }
}
