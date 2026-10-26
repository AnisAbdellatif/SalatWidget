import Foundation
import Testing
@testable import SalatCore

/// Guards against performance regressions in two ways:
///
/// - **Work budgets** (deterministic): simulate a full day and count how often the
///   menu bar clock wakes up and how often the panel redraws. These numbers depend
///   only on the logic, not on the machine, so tight limits are safe.
/// - **Time budgets**: the hot functions must stay well within a generous wall-clock
///   limit, set roughly 10× above what they take in a debug build, which catches
///   order-of-magnitude regressions without flaking on a busy machine.
///
/// The runtime behaviour of the app itself (CPU and wakeups with the panel open and
/// closed) is covered by `make perf`.
@Suite("Performance budgets")
struct PerformanceTests {
    let scheduler: PrayerScheduler
    /// Friday 23 October 2026: has Jumu'a, four iqamas and an Isha that rolls over to Fajr.
    let dayStart = Fixture.date(2026, 10, 23, 0, 0)
    let dayEnd = Fixture.date(2026, 10, 24, 0, 0)

    init() throws {
        scheduler = PrayerScheduler(timetable: try Fixture.timetable())
    }

    // MARK: - Work budgets

    /// What the menu bar shows, reduced to what can change.
    private func label(at date: Date, showsCountdown: Bool) -> String {
        guard let status = scheduler.status(at: date) else { return "-" }
        let base = "\(status.phase) \(status.prayer.prayer) \(status.target)"
        return showsCountdown ? "\(base) \(CountdownFormatter.compact(status.remaining(at: date)))" : base
    }

    /// Runs the menu bar clock over one day: returns how often it woke up and how
    /// many of those wake-ups found the label unchanged (wasted work).
    private func simulateMenuBarClock(showsCountdown: Bool) -> (wakeups: Int, wasted: Int) {
        var now = dayStart
        var shown = label(at: now, showsCountdown: showsCountdown)
        var wakeups = 0
        var wasted = 0
        while now < dayEnd {
            let status = scheduler.status(at: now)
            now += MenuBarClock.refreshInterval(for: status, at: now, showsCountdown: showsCountdown)
            wakeups += 1
            let next = label(at: now, showsCountdown: showsCountdown)
            if next == shown { wasted += 1 }
            shown = next
        }
        return (wakeups, wasted)
    }

    @Test func menuBarCountdownWakesOnlyWhenItsTextChanges() {
        let result = simulateMenuBarClock(showsCountdown: true)
        print("⚙︎ menu bar wake-ups per day (countdown): \(result.wakeups), wasted: \(result.wasted)")
        // Once a minute, plus once a second during the final minute before each of the
        // day's 9 countdown targets (5 adhans incl. Jumu'a, 4 iqamas): ≈ 1440 + 9 × 59.
        #expect(result.wakeups <= 2_000, "menu bar woke \(result.wakeups) times in a day")
        #expect(result.wasted == 0, "\(result.wasted) wake-ups found the label unchanged")
    }

    @Test func menuBarWithoutCountdownWakesOnlyAtStatusChanges() {
        let result = simulateMenuBarClock(showsCountdown: false)
        print("⚙︎ menu bar wake-ups per day (no countdown): \(result.wakeups)")
        // Status changes ~9 times a day; the only other wake-ups are the 15-minute
        // safety ticks that check for a due refresh (at most 96 a day).
        #expect(result.wakeups <= 9 + 96, "menu bar woke \(result.wakeups) times in a day")
    }

    @Test func panelRedrawsOnlyAtPrayerBoundaries() {
        var now = dayStart
        var redraws = 0
        while now < dayEnd {
            now = scheduler.nextBoundary(after: now)
            redraws += 1
        }
        print("⚙︎ panel timetable redraws per day: \(redraws)")
        // 6 adhans/sunrise + 4 iqamas + midnight.
        #expect(redraws <= 11, "panel timetable redrew \(redraws) times in a day")
    }

    @Test func notificationWindowFitsTheSystemLimit() {
        // macOS keeps at most 64 pending notifications per app.
        let events = scheduler.events(after: dayStart, kinds: [.adhan, .iqama])
        #expect(events.count <= 60, "\(events.count) notifications would be scheduled")
    }

    // MARK: - Time budgets

    /// Median wall-clock time of `body`, over several runs after a warm-up.
    private func median(runs: Int = 7, _ body: () throws -> Void) rethrows -> Duration {
        try body()
        let clock = ContinuousClock()
        var samples: [Duration] = []
        for _ in 0..<runs {
            samples.append(try clock.measure(body))
        }
        return samples.sorted()[runs / 2]
    }

    private func expectWithin(_ budget: Duration, _ measured: Duration, _ what: String) {
        print("⏱ \(what): \(measured.formatted(.units(allowed: [.milliseconds, .microseconds], width: .narrow, fractionalPart: .show(length: 2)))) (budget \(budget))")
        #expect(measured <= budget, "\(what) took \(measured), budget \(budget)")
    }

    @Test func statusForEveryMinuteOfADay() {
        // What the menu bar computes on each tick, done 1440 times.
        let measured = median {
            var t = dayStart
            while t < dayEnd {
                _ = scheduler.status(at: t)
                t += 60
            }
        }
        expectWithin(.milliseconds(700), measured, "status × 1440")
    }

    @Test func boundariesForAWeek() {
        let weekEnd = dayStart.addingTimeInterval(7 * 86_400)
        let measured = median {
            var t = dayStart
            while t < weekEnd { t = scheduler.nextBoundary(after: t) }
        }
        expectWithin(.milliseconds(80), measured, "nextBoundary for a week")
    }

    @Test func scheduleForEveryDayOfAYear() {
        let measured = median {
            for offset in 0..<365 {
                _ = scheduler.schedule(for: dayStart.addingTimeInterval(Double(offset) * 86_400))
            }
        }
        expectWithin(.milliseconds(120), measured, "schedule × 365")
    }

    @Test func parsingAMosquePage() throws {
        let html = try Fixture.html
        let measured = try median {
            let json = try ConfDataExtractor.extractJSON(from: html)
            _ = try JSONDecoder().decode(MosqueConfiguration.self, from: json)
        }
        expectWithin(.milliseconds(60), measured, "extract + decode page")
    }

    @Test func notificationEventsForTwoDays() {
        let measured = median {
            _ = scheduler.events(after: dayStart, kinds: [.adhan, .iqama])
        }
        expectWithin(.milliseconds(3), measured, "events for 3 days")
    }
}
