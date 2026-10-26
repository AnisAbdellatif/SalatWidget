import Foundation
@_exported import MawaKit

// The prayer-time logic lives in MawaKit (Rust). Its types (Prayer, PrayerTime,
// DaySchedule, PrayerStatus, PrayerEvent) are re-exported as they are; this file
// adapts them to the app's existing API.

extension PrayerStatus {
    public typealias Phase = PrayerPhase
}

extension PrayerEvent {
    public typealias Kind = PrayerEventKind
}

extension Prayer {
    /// SF Symbol that hints at the position of the sun.
    public var symbolName: String {
        switch self {
        case .fajr: "sun.horizon"
        case .sunrise: "sunrise"
        case .dhuhr: "sun.max"
        case .asr: "sun.min"
        case .maghrib: "sunset"
        case .isha: "moon.stars"
        }
    }
}

/// Turns a cached Mawaqit timetable into concrete dates, using MawaKit.
public struct PrayerScheduler: Sendable {
    public let timetable: Timetable
    /// Gregorian calendar in the mosque's time zone, for date comparisons in the UI.
    public let calendar: Calendar
    private let core: MosqueTimetable?

    public init(timetable: Timetable) {
        self.timetable = timetable
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timetable.timeZone
        self.calendar = calendar

        // The configuration crosses into Rust as JSON, using Mawaqit's own key names.
        let json = (try? JSONEncoder().encode(timetable.configuration)).flatMap { String(data: $0, encoding: .utf8) }
        core = json.flatMap { try? MosqueTimetable.fromConfigurationJson(configurationJson: $0, fetchedAt: timetable.fetchedAt) }
    }

    /// The timetable of the day containing `date` (in the mosque's time zone).
    public func schedule(for date: Date) -> DaySchedule? {
        core?.scheduleFor(date: date)
    }

    /// The countdown to show at `now`: the iqama while it is pending, otherwise the
    /// next adhan.
    public func status(at now: Date) -> PrayerStatus? {
        core?.statusAt(now: now)
    }

    /// The day worth showing: tomorrow once today's last prayer has passed.
    public func displayedSchedule(at now: Date) -> DaySchedule? {
        core?.displayedSchedule(now: now)
    }

    /// The next moment a timetable view looks different.
    public func nextBoundary(after date: Date) -> Date {
        core?.nextBoundary(after: date) ?? date.addingTimeInterval(3600)
    }

    /// Adhan and/or iqama moments after `now`, for today and the next `days` days.
    public func events(after now: Date, days: Int = 2, kinds: Set<PrayerEvent.Kind>) -> [PrayerEvent] {
        core?.eventsAfter(now: now, days: UInt32(max(0, days)), kinds: Array(kinds)) ?? []
    }
}
