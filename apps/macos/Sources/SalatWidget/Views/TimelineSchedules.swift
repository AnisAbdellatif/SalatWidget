import SalatCore
import SwiftUI

/// Updates only at the moments a timetable looks different: each adhan, iqama,
/// sunrise and midnight. Between those, nothing on the page except the countdown
/// changes, so nothing is redrawn.
struct PrayerBoundarySchedule: TimelineSchedule {
    let scheduler: PrayerScheduler

    func entries(from startDate: Date, mode: TimelineScheduleMode) -> UnfoldFirstSequence<Date> {
        sequence(first: startDate) { [scheduler] in scheduler.nextBoundary(after: $0) }
    }
}

/// Ticks on whole seconds, which is exactly when a countdown to a whole-minute
/// target changes. (`.periodic(from: .now, by: 1)` would tick at arbitrary
/// fractions of a second and restart on every redraw of the parent.)
struct WholeSecondSchedule: TimelineSchedule {
    /// When paused, the view is drawn once and then left alone.
    var isPaused = false

    func entries(from startDate: Date, mode: TimelineScheduleMode) -> UnfoldFirstSequence<Date> {
        if isPaused { return sequence(first: startDate) { _ in nil } }
        // With reduced update frequency (e.g. the display is dimmed), once a minute is plenty.
        let step: TimeInterval = mode == .lowFrequency ? 60 : 1
        let firstTick = Date(timeIntervalSinceReferenceDate: (startDate.timeIntervalSinceReferenceDate / step).rounded(.up) * step)
        return sequence(first: startDate) { $0 < firstTick ? firstTick : $0.addingTimeInterval(step) }
    }
}
