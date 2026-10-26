import Foundation

/// Countdown text (via MawaKit).
public enum CountdownFormatter {
    /// Short form for the menu bar: `1h 23m`, `23m`, `45s`.
    public static func compact(_ interval: TimeInterval) -> String {
        countdownCompact(seconds: interval)
    }

    /// How long until `compact(remaining)` shows a different string.
    public static func timeUntilCompactChange(_ remaining: TimeInterval) -> TimeInterval {
        countdownTimeUntilChange(seconds: remaining)
    }

    /// Clock form for the popover: `1:23:45` or `23:45`.
    public static func clock(_ interval: TimeInterval) -> String {
        countdownClock(seconds: interval)
    }
}

public enum HijriDate {
    /// E.g. `2 Jumada I 1448 AH`, shifted by the mosque's Hijri adjustment.
    public static func string(for date: Date, adjustment: Int = 0, timeZone: TimeZone = .current, locale: Locale = .current) -> String {
        var calendar = Calendar(identifier: .islamicUmmAlQura)
        calendar.timeZone = timeZone
        calendar.locale = locale
        let adjusted = calendar.date(byAdding: .day, value: adjustment, to: date) ?? date

        var style = Date.FormatStyle(date: .long, time: .omitted, locale: locale, calendar: calendar, timeZone: timeZone)
        style.calendar = calendar
        return adjusted.formatted(style)
    }
}
