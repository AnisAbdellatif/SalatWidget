import Foundation
import Testing
@testable import SalatCore

@Suite("Prayer scheduler")
struct PrayerSchedulerTests {
    let scheduler: PrayerScheduler

    init() throws {
        scheduler = PrayerScheduler(timetable: try Fixture.timetable())
    }

    private func date(_ day: Int, _ hour: Int, _ minute: Int, month: Int = 10) -> Date {
        Fixture.date(2026, month, day, hour, minute)
    }

    // MARK: Day schedule

    @Test func buildsFridayScheduleWithJumua() throws {
        let schedule = try #require(scheduler.schedule(for: date(23, 12, 0)))
        #expect(schedule.times.map(\.prayer) == Prayer.allCases)

        let fajr = try #require(schedule.time(for: .fajr))
        #expect(fajr.adhan == date(23, 6, 15))
        #expect(fajr.iqama == date(23, 6, 45))

        let sunrise = try #require(schedule.time(for: .sunrise))
        #expect(sunrise.adhan == date(23, 7, 55))
        #expect(sunrise.iqama == nil)

        let dhuhr = try #require(schedule.time(for: .dhuhr))
        #expect(dhuhr.isJumua)
        #expect(dhuhr.displayName == "Jumu'a")
        #expect(dhuhr.adhan == date(23, 13, 20))
        #expect(dhuhr.iqama == nil)

        let isha = try #require(schedule.time(for: .isha))
        #expect(isha.adhan == date(23, 19, 44))
        #expect(isha.iqama == date(23, 19, 49))
    }

    @Test func showsJumuaOnFridaysOnly() throws {
        var day = Fixture.date(2026, 1, 1, 12, 0)
        let end = Fixture.date(2027, 1, 1, 12, 0)
        var fridays = 0
        while day < end {
            let dhuhr = try #require(scheduler.schedule(for: day)?.time(for: .dhuhr))
            let isFriday = scheduler.calendar.component(.weekday, from: day) == 6
            #expect(dhuhr.isJumua == isFriday, "\(day)")
            if isFriday { fridays += 1 }
            day = scheduler.calendar.date(byAdding: .day, value: 1, to: day)!
        }
        #expect(fridays == 52)
    }

    @Test func displaysTodayUntilTheLastPrayerHasPassed() throws {
        let afternoon = try #require(scheduler.displayedSchedule(at: date(23, 14, 0)))
        #expect(afternoon.day == date(23, 0, 0))
        #expect(afternoon.time(for: .dhuhr)?.isJumua == true)

        // During Isha's iqama wait, Friday is still current.
        #expect(scheduler.displayedSchedule(at: date(23, 19, 46))?.day == date(23, 0, 0))
    }

    @Test func displaysTomorrowAfterIsha() throws {
        // Friday evening after the Isha iqama: Saturday's times, so no Jumu'a.
        let evening = try #require(scheduler.displayedSchedule(at: date(23, 22, 0)))
        #expect(evening.day == date(24, 0, 0))
        #expect(evening.time(for: .dhuhr)?.isJumua == false)
        #expect(evening.time(for: .fajr)?.adhan == date(24, 6, 15))

        // Still Saturday after midnight.
        #expect(scheduler.displayedSchedule(at: date(24, 0, 30))?.day == date(24, 0, 0))
    }

    @Test func usesRegularDhuhrOnOtherDays() throws {
        let schedule = try #require(scheduler.schedule(for: date(24, 12, 0)))
        let dhuhr = try #require(schedule.time(for: .dhuhr))
        #expect(!dhuhr.isJumua)
        #expect(dhuhr.iqama == dhuhr.adhan.addingTimeInterval(15 * 60))
    }

    @Test func readsCalendarInLocalTimeAcrossDaylightSavingChange() throws {
        // Berlin leaves summer time on 25 October 2026; the calendar is wall-clock time.
        let before = try #require(scheduler.schedule(for: date(24, 12, 0))?.time(for: .dhuhr))
        let after = try #require(scheduler.schedule(for: date(25, 12, 0))?.time(for: .dhuhr))
        #expect(before.adhan == date(24, 13, 5))
        #expect(after.adhan == date(25, 12, 5))
        // One hour earlier on the clock, but exactly 24 hours later since the night lasts 25 hours.
        #expect(after.adhan.timeIntervalSince(before.adhan) == 24 * 3600)
    }

    @Test func supportsFixedIqamaTimes() throws {
        // On 26 October the Dhuhr iqama is set to a fixed 13:00 instead of an offset.
        let dhuhr = try #require(scheduler.schedule(for: date(26, 9, 0))?.time(for: .dhuhr))
        #expect(dhuhr.iqama == date(26, 13, 0))
    }

    @Test func todayTimesOverrideCalendarOnlyOnFetchDay() throws {
        var configuration = try Fixture.configuration
        configuration.times = ["06:20", "13:10", "15:45", "18:20", "19:50"]
        configuration.shuruq = "07:58"
        let timetable = Timetable(slug: "x", configuration: configuration, fetchedAt: date(23, 9, 0))
        let scheduler = PrayerScheduler(timetable: timetable)

        let today = try #require(scheduler.schedule(for: date(23, 12, 0)))
        #expect(today.time(for: .fajr)?.adhan == date(23, 6, 20))
        #expect(today.time(for: .sunrise)?.adhan == date(23, 7, 58))

        let tomorrow = try #require(scheduler.schedule(for: date(24, 12, 0)))
        #expect(tomorrow.time(for: .fajr)?.adhan == date(24, 6, 15))
    }

    @Test func omitsIqamaWhenDisabled() throws {
        var configuration = try Fixture.configuration
        configuration.iqamaEnabled = false
        let scheduler = PrayerScheduler(timetable: Timetable(slug: "x", configuration: configuration, fetchedAt: date(23, 9, 0)))
        let schedule = try #require(scheduler.schedule(for: date(24, 12, 0)))
        #expect(schedule.times.allSatisfy { $0.iqama == nil })
    }

    @Test func jumuaAsDuhrKeepsDhuhrTime() throws {
        var configuration = try Fixture.configuration
        configuration.jumuaAsDuhr = true
        let scheduler = PrayerScheduler(timetable: Timetable(slug: "x", configuration: configuration, fetchedAt: date(23, 9, 0)))
        let dhuhr = try #require(scheduler.schedule(for: date(23, 12, 0))?.time(for: .dhuhr))
        #expect(dhuhr.isJumua)
        #expect(dhuhr.adhan == date(23, 13, 7))
    }

    @Test func appliesEachKindOfIqamaRule() throws {
        // Saturday 24 October: Fajr 06:15, Dhuhr 13:05, Asr 15:39, Maghrib 18:11, Isha 19:41.
        var configuration = try Fixture.configuration
        configuration.iqamaCalendar[9]["24"] = ["+10", "14:00", "15:00", "+0", ""]
        let scheduler = PrayerScheduler(timetable: Timetable(slug: "x", configuration: configuration, fetchedAt: date(23, 9, 0)))
        let schedule = try #require(scheduler.schedule(for: date(24, 12, 0)))

        #expect(schedule.time(for: .fajr)?.iqama == date(24, 6, 25))   // offset
        #expect(schedule.time(for: .dhuhr)?.iqama == date(24, 14, 0))  // fixed time
        #expect(schedule.time(for: .asr)?.iqama == nil)                // fixed time before the adhan
        #expect(schedule.time(for: .maghrib)?.iqama == nil)            // zero offset
        #expect(schedule.time(for: .isha)?.iqama == nil)               // empty rule
    }

    // MARK: Status

    @Test func countsDownToNextAdhan() throws {
        let now = date(23, 14, 0)
        let status = try #require(scheduler.status(at: now))
        #expect(status.phase == .adhan)
        #expect(status.prayer.prayer == .asr)
        #expect(status.target == date(23, 15, 41))
        // The interval starts at the previous prayer (Jumu'a, no iqama).
        #expect(status.intervalStart == date(23, 13, 20))
        #expect(status.remaining(at: now) == 101 * 60)
    }

    @Test func countsDownToIqamaAfterAdhan() throws {
        let status = try #require(scheduler.status(at: date(23, 15, 43)))
        #expect(status.phase == .iqama)
        #expect(status.prayer.prayer == .asr)
        // Asr iqama is 10 minutes after the adhan.
        #expect(status.target == date(23, 15, 51))
        #expect(status.intervalStart == date(23, 15, 41))
    }

    @Test func movesOnOnceIqamaHasPassed() throws {
        let status = try #require(scheduler.status(at: date(23, 15, 51)))
        #expect(status.phase == .adhan)
        #expect(status.prayer.prayer == .maghrib)
        #expect(status.intervalStart == date(23, 15, 51))
    }

    @Test func skipsSunrise() throws {
        let status = try #require(scheduler.status(at: date(23, 7, 0)))
        #expect(status.prayer.prayer == .dhuhr)
        #expect(status.prayer.isJumua)
    }

    @Test func rollsOverToTomorrowsFajrAfterIsha() throws {
        let status = try #require(scheduler.status(at: date(23, 22, 0)))
        #expect(status.phase == .adhan)
        #expect(status.prayer.prayer == .fajr)
        #expect(status.target == date(24, 6, 15))
        #expect(status.intervalStart == date(23, 19, 49))
    }

    @Test func afterMidnightIntervalStartsAtYesterdaysIsha() throws {
        let status = try #require(scheduler.status(at: date(24, 0, 30)))
        #expect(status.prayer.prayer == .fajr)
        #expect(status.intervalStart == date(23, 19, 49))
        let progress = status.progress(at: date(24, 0, 30))
        #expect(progress > 0.4 && progress < 0.5)
    }

    // MARK: Boundaries

    @Test(arguments: [
        // (now, expected next boundary) on Friday 23 October
        ((6, 50), (7, 55)),    // after Fajr iqama → sunrise (its row dims)
        ((13, 0), (13, 20)),   // Jumu'a
        ((13, 20), (15, 41)),  // Jumu'a has no iqama → Asr adhan
        ((15, 41), (15, 51)),  // Asr adhan → Asr iqama
        ((14, 0), (15, 41)),
    ])
    func findsNextBoundary(now: (Int, Int), expected: (Int, Int)) {
        #expect(scheduler.nextBoundary(after: date(23, now.0, now.1)) == date(23, expected.0, expected.1))
    }

    @Test func nextBoundaryAfterIshaIsMidnight() {
        #expect(scheduler.nextBoundary(after: date(23, 20, 0)) == date(24, 0, 0))
        #expect(scheduler.nextBoundary(after: date(24, 0, 0)) == date(24, 6, 15))
    }

    // MARK: Events

    @Test func listsUpcomingAdhanAndIqamaEvents() throws {
        let events = scheduler.events(after: date(23, 14, 0), kinds: [.adhan, .iqama])
        let first = events.prefix(4).map { "\($0.kind) \($0.prayer.prayer)" }
        #expect(first == ["adhan asr", "iqama asr", "adhan maghrib", "iqama maghrib"])
        #expect(events[0].date == date(23, 15, 41))
        #expect(events[1].date == date(23, 15, 51))
        #expect(events.allSatisfy { $0.prayer.prayer != .sunrise })
        #expect(events == events.sorted { $0.date < $1.date })
        // Rest of today (3 prayers) plus two full days (5 prayers each), adhan and iqama.
        #expect(events.count == (3 + 5 + 5) * 2)
        #expect(Set(events.map(\.id)).count == events.count)
    }

    @Test func filtersEventsByKind() throws {
        let adhans = scheduler.events(after: date(23, 14, 0), kinds: [.adhan])
        #expect(adhans.allSatisfy { $0.kind == .adhan })
        #expect(scheduler.events(after: date(23, 14, 0), kinds: []).isEmpty)
    }

    @Test func jumuaHasNoIqamaEvent() throws {
        let events = scheduler.events(after: date(23, 12, 0), days: 0, kinds: [.adhan, .iqama])
        let jumua = events.filter { $0.prayer.isJumua }
        #expect(jumua.map(\.kind) == [.adhan])
        #expect(jumua.first?.date == date(23, 13, 20))
    }

    @Test func excludesEventsAtOrBeforeNow() throws {
        let events = scheduler.events(after: date(23, 15, 41), kinds: [.adhan, .iqama])
        #expect(events.first?.kind == .iqama)
        #expect(events.first?.date == date(23, 15, 51))
    }

    @Test func handlesYearRollover() throws {
        let status = try #require(scheduler.status(at: Fixture.date(2026, 12, 31, 23, 0)))
        #expect(status.prayer.prayer == .fajr)
        #expect(Calendar.current.dateComponents(in: Fixture.berlin, from: status.target).year == 2027)
    }
}
