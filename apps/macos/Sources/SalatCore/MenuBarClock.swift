import Foundation

/// Decides how long the menu bar label stays valid, so the app can sleep until the
/// text would actually change instead of polling (via MawaKit).
public enum MenuBarClock {
    public static func refreshInterval(
        for status: PrayerStatus?,
        at now: Date,
        showsCountdown: Bool,
        maxInterval: TimeInterval = 15 * 60
    ) -> TimeInterval {
        statusBarRefreshInterval(status: status, now: now, showsCountdown: showsCountdown, maxInterval: maxInterval)
    }
}
