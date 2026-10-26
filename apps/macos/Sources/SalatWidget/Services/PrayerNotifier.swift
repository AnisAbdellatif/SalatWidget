import AppKit
import SalatCore
import OSLog
import UserNotifications

/// Schedules local notifications for upcoming adhan and iqama times.
///
/// Notifications are scheduled for a rolling window of a few days (macOS keeps at
/// most 64 pending per app) and rescheduled whenever the timetable, the
/// preferences or the date changes.
@MainActor
final class PrayerNotifier {
    enum Authorization {
        case notDetermined
        case authorized
        case denied
    }

    /// `UNUserNotificationCenter` requires a real app bundle; it traps under `swift run`.
    static var isAvailable: Bool {
        Bundle.main.bundleURL.pathExtension == "app" && Bundle.main.bundleIdentifier != nil
    }

    private let presenter = ForegroundPresenter()
    private var lastScheduledIDs: [String] = []

    private var center: UNUserNotificationCenter? {
        Self.isAvailable ? UNUserNotificationCenter.current() : nil
    }

    init() {
        center?.delegate = presenter
    }

    func authorization() async -> Authorization {
        guard let center else { return .denied }
        switch await center.notificationSettings().authorizationStatus {
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        default: return .authorized
        }
    }

    /// Asks for permission if it hasn't been decided yet. Returns whether notifications are allowed.
    func requestAuthorization() async -> Bool {
        guard let center else { return false }
        switch await authorization() {
        case .authorized: return true
        case .denied: return false
        case .notDetermined:
            do {
                return try await center.requestAuthorization(options: [.alert, .sound])
            } catch {
                Logger.app.error("Notification authorization failed: \(error.localizedDescription, privacy: .public)")
                return false
            }
        }
    }

    /// Replaces all pending notifications with `events`. A no-op when nothing changed.
    func schedule(_ events: [PrayerEvent], mosqueName: String, formatTime: (Date) -> String) async {
        guard let center else { return }
        let events = Array(events.prefix(60))
        let ids = events.map(\.id)
        guard ids != lastScheduledIDs else { return }

        center.removeAllPendingNotificationRequests()
        lastScheduledIDs = ids
        guard !events.isEmpty, await authorization() == .authorized else { return }

        for event in events {
            let content = UNMutableNotificationContent()
            content.sound = .default
            content.threadIdentifier = "prayer-times"
            switch event.kind {
            case .adhan:
                content.title = "\(event.prayer.displayName) · \(event.prayer.displayArabicName)"
                content.body = event.prayer.iqama.map { "It's time for \(event.prayer.displayName). Iqama at \(formatTime($0))." }
                    ?? "It's time for \(event.prayer.displayName)."
            case .iqama:
                content.title = "Iqama · \(event.prayer.displayName)"
                content.body = "The prayer is starting now."
            }
            content.subtitle = mosqueName

            let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: event.date)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            do {
                try await center.add(UNNotificationRequest(identifier: event.id, content: content, trigger: trigger))
            } catch {
                Logger.app.error("Couldn't schedule notification: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func cancelAll() {
        center?.removeAllPendingNotificationRequests()
        lastScheduledIDs = []
    }

    static func openSystemSettings() {
        let id = Bundle.main.bundleIdentifier ?? ""
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(id)") {
            NSWorkspace.shared.open(url)
        }
    }
}

/// Shows banners even while the panel is open (the app counts as frontmost then).
private final class ForegroundPresenter: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .list])
    }
}
