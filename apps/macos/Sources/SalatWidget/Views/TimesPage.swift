import AppKit
import SalatCore
import SwiftUI

/// The main page: next-prayer countdown and today's timetable.
///
/// Updates are split by how often each part changes. Each section is its own view, so
/// SwiftUI's observation tracking only redraws the parts whose inputs changed:
/// - header, card layout and table redraw at prayer boundaries (`PrayerBoundarySchedule`)
/// - only the countdown digits and progress bar redraw every second (`WholeSecondSchedule`)
/// - the footer redraws only when the loading state changes
struct TimesPage: View {
    @Environment(AppModel.self) private var model
    let onChangeMosque: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            if let scheduler = model.scheduler {
                TimelineView(PrayerBoundarySchedule(scheduler: scheduler)) { context in
                    TimetableContent(scheduler: scheduler, now: context.date, onChangeMosque: onChangeMosque)
                }
            } else {
                TimesHeader(day: .now, onChangeMosque: onChangeMosque)
                LoadingPlaceholder()
            }

            Divider()
            TimesFooter(onOpenSettings: onOpenSettings)
        }
    }
}

/// Everything that only changes at prayer boundaries.
private struct TimetableContent: View {
    let scheduler: PrayerScheduler
    let now: Date
    let onChangeMosque: () -> Void

    var body: some View {
        #if DEBUG
        let _ = RenderCounter.count(.timetable)
        #endif
        let status = scheduler.status(at: now)
        // After the day's last prayer this is tomorrow's timetable.
        let shown = scheduler.displayedSchedule(at: now)
        let showsTomorrow = shown.map { !scheduler.calendar.isDate($0.day, inSameDayAs: now) } ?? false

        TimesHeader(day: shown?.day ?? now, isTomorrow: showsTomorrow, onChangeMosque: onChangeMosque)

        if let status {
            CountdownCard(status: status, isTomorrow: scheduler.calendar.isDateInTomorrow(status.prayer.adhan))
        }

        if let shown {
            PrayerTable(schedule: shown, status: status, now: now)
        } else {
            ContentUnavailableView(
                "No times for today",
                systemImage: "calendar.badge.exclamationmark",
                description: Text("This mosque hasn't published a timetable for today.")
            )
        }
    }
}

// MARK: - Header

private struct TimesHeader: View {
    @Environment(AppModel.self) private var model
    /// The day whose timetable is shown.
    let day: Date
    var isTomorrow = false
    let onChangeMosque: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.mosqueName ?? "Loading…")
                    .font(.headline)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(dateLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button(action: onChangeMosque) {
                Image(systemName: "building.columns")
            }
            .buttonStyle(IconButtonStyle())
            .help("Change mosque")
        }
    }

    private var dateLine: String {
        let timeZone = model.timetable?.timeZone ?? .current
        var gregorian = Date.FormatStyle().weekday(.abbreviated).day().month(.abbreviated)
        gregorian.timeZone = timeZone
        let hijri = HijriDate.string(
            for: day,
            adjustment: model.timetable?.configuration.hijriAdjustment ?? 0,
            timeZone: timeZone
        )
        let date = "\(day.formatted(gregorian)) · \(hijri)"
        return isTomorrow ? "Tomorrow, \(date)" : date
    }
}

private struct LoadingPlaceholder: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 8) {
            if case let .failed(message) = model.loadState {
                ContentUnavailableView {
                    Label("Couldn't load times", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(message)
                } actions: {
                    Button("Try Again") { Task { await model.refresh() } }
                }
            } else {
                ProgressView()
                    .controlSize(.small)
                Text("Loading prayer times…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 160)
    }
}

// MARK: - Footer

private struct TimesFooter: View {
    @Environment(AppModel.self) private var model
    let onOpenSettings: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            status
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 4)

            Button {
                Task { await model.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(IconButtonStyle())
            .disabled(model.loadState == .loading)
            .help("Refresh")
            .keyboardShortcut("r")

            if let url = model.timetable?.pageURL {
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    Image(systemName: "safari")
                }
                .buttonStyle(IconButtonStyle())
                .help("Open on mawaqit.net")
            }

            Button(action: onOpenSettings) {
                Image(systemName: "gearshape")
            }
            .buttonStyle(IconButtonStyle())
            .help("Settings")
            .keyboardShortcut(",")

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
            .buttonStyle(IconButtonStyle())
            .help("Quit SalatWidget")
            .keyboardShortcut("q")
        }
    }

    @ViewBuilder
    private var status: some View {
        switch model.loadState {
        case .loading:
            HStack(spacing: 4) {
                ProgressView().controlSize(.mini)
                Text("Updating…")
            }
        case .failed where model.timetable != nil:
            Label("Offline · saved times", systemImage: "icloud.slash")
                .help("Showing the last downloaded timetable")
        case .idle, .failed:
            if let lastUpdated = model.lastUpdated {
                // An absolute time stays correct without a timer, unlike "5 minutes ago".
                Text("Updated \(updatedText(lastUpdated))")
            } else {
                Text("mawaqit.net")
            }
        }
    }

    private func updatedText(_ date: Date) -> String {
        Calendar.current.isDateInToday(date)
            ? date.formatted(date: .omitted, time: .shortened)
            : date.formatted(.dateTime.day().month(.abbreviated))
    }
}

// MARK: - Countdown card

private struct CountdownCard: View {
    @Environment(AppModel.self) private var model
    @Environment(\.isPanelVisible) private var isPanelVisible
    let status: PrayerStatus
    let isTomorrow: Bool

    private var isIqama: Bool { status.phase == .iqama }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(isIqama ? "Until iqama" : "Next prayer", systemImage: isIqama ? "hourglass" : "bell")
                    .font(.caption.weight(.semibold))
                    .textCase(.uppercase)
                    .opacity(0.85)
                Spacer()
                Text(status.prayer.displayArabicName)
                    .font(.callout.weight(.medium))
                    .opacity(0.9)
            }

            // The only part of the page that changes every second.
            TimelineView(WholeSecondSchedule(isPaused: !isPanelVisible)) { context in
                LiveCountdown(status: status, now: context.date, title: status.prayer.displayName)
            }

            Text(subtitle)
                .font(.caption)
                .opacity(0.9)
        }
        .padding(14)
        .foregroundStyle(.white)
        .background(
            LinearGradient(
                colors: isIqama ? [.iqama, .iqamaDeep] : [.brand, .brandDeep],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .shadow(color: (isIqama ? Color.iqamaDeep : .brandDeep).opacity(0.25), radius: 8, y: 3)
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String {
        let prayer = status.prayer
        if isIqama {
            return "Adhan was at \(model.formattedTime(prayer.adhan)) · Iqama at \(model.formattedTime(status.target))"
        }
        var text = "\(isTomorrow ? "Tomorrow" : "Adhan") at \(model.formattedTime(prayer.adhan))"
        if let iqama = prayer.iqama {
            text += " · Iqama \(model.formattedTime(iqama))"
        }
        return text
    }
}

/// Prayer name, ticking clock and progress bar. Kept free of model access so the
/// per-second redraw stays as small as possible.
private struct LiveCountdown: View {
    let status: PrayerStatus
    let now: Date
    let title: String

    var body: some View {
        let remaining = status.remaining(at: now)
        #if DEBUG
        let _ = RenderCounter.count(.countdown)
        #endif

        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.title2.weight(.semibold))
                Spacer()
                // No `.contentTransition(.numericText())` here: inside a MenuBarExtra
                // window it re-measures the whole window every animation frame, which
                // kept the app at ~20% CPU even after the panel was closed.
                Text(CountdownFormatter.clock(remaining))
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .accessibilityLabel("\(CountdownFormatter.compact(remaining)) remaining")
            }
            CapsuleProgress(value: status.progress(at: now))
        }
    }
}

// MARK: - Timetable

private struct PrayerTable: View {
    @Environment(AppModel.self) private var model
    let schedule: DaySchedule
    let status: PrayerStatus?
    let now: Date

    private var showsIqama: Bool {
        schedule.times.contains { $0.iqama != nil }
    }

    var body: some View {
        VStack(spacing: 2) {
            HStack {
                Spacer()
                Text("Adhan").frame(width: 58, alignment: .trailing)
                if showsIqama {
                    Text("Iqama").frame(width: 58, alignment: .trailing)
                }
            }
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .padding(.horizontal, 10)

            ForEach(schedule.times) { time in
                PrayerRow(time: time, state: state(of: time), showsIqama: showsIqama)
            }

            if !schedule.additionalJumua.isEmpty {
                Text("Further Jumu'a: " + schedule.additionalJumua.map(model.formattedTime).joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.horizontal, 10)
                    .padding(.top, 2)
            }
        }
    }

    private func state(of time: PrayerTime) -> PrayerRow.RowState {
        if let status, status.prayer == time { return .current }
        let end = time.prayer.isObligatory ? time.start : time.adhan
        return end <= now ? .past : .upcoming
    }
}

private struct PrayerRow: View {
    enum RowState { case past, current, upcoming }

    @Environment(AppModel.self) private var model
    let time: PrayerTime
    let state: RowState
    let showsIqama: Bool

    private var isSunrise: Bool { !time.prayer.isObligatory }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: time.prayer.symbolName)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(state == .current ? Color.brand : .secondary)
                .frame(width: 20)

            Text(time.displayName)
                .fontWeight(state == .current ? .semibold : .regular)
                .foregroundStyle(isSunrise ? .secondary : .primary)

            Text(time.displayArabicName)
                .font(.caption)
                .foregroundStyle(.tertiary)

            Spacer(minLength: 4)

            Text(model.formattedTime(time.adhan))
                .fontWeight(state == .current ? .semibold : .regular)
                .frame(width: 58, alignment: .trailing)

            if showsIqama {
                Text(time.iqama.map(model.formattedTime) ?? "")
                    .foregroundStyle(.secondary)
                    .frame(width: 58, alignment: .trailing)
            }
        }
        .monospacedDigit()
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background {
            if state == .current {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.brand.opacity(0.14))
            }
        }
        .opacity(state == .past ? 0.45 : 1)
        .accessibilityElement(children: .combine)
    }
}
