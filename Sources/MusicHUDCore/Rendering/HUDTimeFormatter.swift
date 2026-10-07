import Foundation

/// Formatting shared by the retro clock and the track-info rows.
public enum HUDTimeFormatter {

    /// `00:42:55` — always `HH:MM:SS`, zero padded. This is the reference format.
    public static func clockStyle(_ seconds: TimeInterval) -> String {
        let total = Int(max(seconds, 0).rounded(.down))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }

    /// `3:47`, or `1:02:33` once the track passes an hour. Used for track lengths.
    public static func duration(_ seconds: TimeInterval) -> String {
        let total = Int(max(seconds, 0).rounded(.down))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }

    /// `-2:24` signed remaining time, used on the right of the progress bar.
    public static func remaining(_ seconds: TimeInterval) -> String {
        "-" + duration(seconds)
    }

    /// Wall-clock string for the big display, in the given time zone.
    public static func wallClock(_ date: Date, timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.hour, .minute, .second], from: date)
        return String(
            format: "%02d:%02d:%02d",
            parts.hour ?? 0,
            parts.minute ?? 0,
            parts.second ?? 0
        )
    }

    /// Human-readable name of a time zone, e.g. `太平洋时间`.
    ///
    /// Falls back to the raw identifier when the system has no localized name.
    public static func timeZoneName(_ identifier: String, locale: Locale = .current) -> String {
        guard let zone = TimeZone(identifier: identifier) else { return identifier }
        return zone.localizedName(for: .generic, locale: locale)
            ?? zone.localizedName(for: .standard, locale: locale)
            ?? identifier
    }
}
