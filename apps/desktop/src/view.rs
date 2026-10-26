//! What the tray, menu, popup and panel plugin display, as plain values. Kept free of
//! any toolkit so it can be unit-tested and shared across platforms.

use jiff::Timestamp;
use jiff::tz::TimeZone;
use mawakit::{
    DaySchedule, MosqueTimetable, PrayerEvent, PrayerEventKind, PrayerPhase, PrayerStatus,
    PrayerTime, countdown,
};

use crate::icon::Tone;

/// Countdown short enough for a 22-pixel tray icon (at most four narrow characters):
/// `45s`, `23m`, `1:23`, `2h`, `11h`. Rounded up like the other countdowns.
pub fn tiny_countdown(seconds: f64) -> String {
    let seconds = seconds.max(0.0);
    if seconds <= 59.0 {
        return format!("{}s", seconds.ceil() as i64);
    }
    let total_minutes = (seconds / 60.0).ceil() as i64;
    let (hours, minutes) = (total_minutes / 60, total_minutes % 60);
    match (hours, minutes) {
        (0, m) => format!("{m}m"),
        (h, 0) => format!("{h}h"),
        (h, m) if h < 10 => format!("{h}:{m:02}"),
        // No room for minutes: round the hours up, like every other countdown here.
        (h, _) => format!("{}h", h + 1),
    }
}

/// Seconds until [`tiny_countdown`] shows different text: like the compact countdown,
/// except that from ten hours on only whole hours are shown.
pub fn tiny_valid_for(seconds: f64) -> f64 {
    if seconds > 10.0 * 3600.0 {
        let hours = (seconds / 3600.0).ceil();
        return (seconds - (hours - 1.0) * 3600.0).max(0.0);
    }
    countdown::time_until_compact_change(seconds)
}

/// The status line: `Asr 1h 23m`, or `Iqama 4m` while waiting for the iqama.
pub fn label(status: &PrayerStatus, now: Timestamp) -> String {
    format!(
        "{} {}",
        phase_name(status),
        countdown::compact(status.remaining(now))
    )
}

/// A sentence for menus and tooltips: `Asr in 1h 23m`, `Iqama in 4m`.
pub fn sentence(status: &PrayerStatus, now: Timestamp) -> String {
    format!(
        "{} in {}",
        phase_name(status),
        countdown::compact(status.remaining(now))
    )
}

fn phase_name(status: &PrayerStatus) -> &'static str {
    match status.phase {
        PrayerPhase::Iqama => "Iqama",
        PrayerPhase::Adhan => status.prayer.display_name(),
    }
}

pub fn tone(status: &PrayerStatus) -> Tone {
    match status.phase {
        PrayerPhase::Adhan => Tone::Adhan,
        PrayerPhase::Iqama => Tone::Iqama,
    }
}

/// `15:41` in the mosque's time zone.
pub fn clock_time(at: Timestamp, tz: &TimeZone) -> String {
    at.to_zoned(tz.clone()).strftime("%H:%M").to_string()
}

/// `Mon, 26 Oct`, prefixed with `Tomorrow, ` when the shown day isn't today.
pub fn date_line(day: Timestamp, now: Timestamp, tz: &TimeZone) -> String {
    let zoned = day.to_zoned(tz.clone());
    let date = zoned.strftime("%a, %-d %b").to_string();
    if zoned.date() == now.to_zoned(tz.clone()).date() {
        date
    } else {
        format!("Tomorrow, {date}")
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RowState {
    Past,
    Current,
    Upcoming,
}

/// One line of the timetable.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Row {
    pub name: &'static str,
    pub arabic: &'static str,
    pub adhan: String,
    pub iqama: Option<String>,
    pub state: RowState,
    pub is_sunrise: bool,
}

pub fn rows(
    schedule: &DaySchedule,
    status: Option<&PrayerStatus>,
    now: Timestamp,
    tz: &TimeZone,
) -> Vec<Row> {
    schedule
        .times
        .iter()
        .map(|time| Row {
            name: time.display_name(),
            arabic: time.display_arabic_name(),
            adhan: clock_time(time.adhan, tz),
            iqama: time.iqama.map(|t| clock_time(t, tz)),
            state: row_state(time, status, now),
            is_sunrise: !time.prayer.is_obligatory(),
        })
        .collect()
}

fn row_state(time: &PrayerTime, status: Option<&PrayerStatus>, now: Timestamp) -> RowState {
    if status.is_some_and(|s| &s.prayer == time) {
        return RowState::Current;
    }
    let end = if time.prayer.is_obligatory() {
        time.start()
    } else {
        time.adhan
    };
    if end <= now {
        RowState::Past
    } else {
        RowState::Upcoming
    }
}

/// The big countdown card.
#[derive(Debug, Clone, PartialEq)]
pub struct Card {
    pub heading: &'static str,
    pub name: &'static str,
    pub arabic: &'static str,
    pub clock: String,
    pub progress: f64,
    pub detail: String,
    pub tone: Tone,
}

pub fn card(status: &PrayerStatus, now: Timestamp, timetable: &MosqueTimetable) -> Card {
    let tz = timetable.time_zone();
    let prayer = &status.prayer;
    let detail = match status.phase {
        PrayerPhase::Iqama => format!(
            "Adhan was at {} · Iqama at {}",
            clock_time(prayer.adhan, tz),
            clock_time(status.target, tz)
        ),
        PrayerPhase::Adhan => {
            let is_tomorrow =
                prayer.adhan.to_zoned(tz.clone()).date() != now.to_zoned(tz.clone()).date();
            let when = if is_tomorrow { "Tomorrow" } else { "Adhan" };
            let mut text = format!("{when} at {}", clock_time(prayer.adhan, tz));
            if let Some(iqama) = prayer.iqama {
                text.push_str(&format!(" · Iqama {}", clock_time(iqama, tz)));
            }
            text
        }
    };
    Card {
        heading: if status.phase == PrayerPhase::Iqama {
            "UNTIL IQAMA"
        } else {
            "NEXT PRAYER"
        },
        name: prayer.display_name(),
        arabic: prayer.display_arabic_name(),
        clock: countdown::clock(status.remaining(now)),
        progress: status.progress(now),
        detail,
        tone: tone(status),
    }
}

/// Events further in the past than this are dropped rather than notified, so waking
/// the computer after hours of suspend doesn't fire a burst of stale alerts.
pub const NOTIFY_GRACE_SECONDS: i64 = 5 * 60;

/// The adhan/iqama events of `kinds` that became due in (`since`, `now`], minus those
/// more than [`NOTIFY_GRACE_SECONDS`] late.
pub fn due_events(
    timetable: &MosqueTimetable,
    since: Timestamp,
    now: Timestamp,
    kinds: &[PrayerEventKind],
) -> Vec<PrayerEvent> {
    if now <= since || kinds.is_empty() {
        return Vec::new();
    }
    let grace_start = now
        .checked_sub(jiff::SignedDuration::from_secs(NOTIFY_GRACE_SECONDS))
        .unwrap_or(now);
    timetable
        .events_after(since.max(grace_start), 1, kinds.to_vec())
        .into_iter()
        .filter(|event| event.date <= now)
        .collect()
}

/// A desktop notification's title and text.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Notice {
    pub summary: String,
    pub body: String,
}

/// `Asr · العصر` / `It's time for Asr. Iqama at 15:51.`, or `Iqama · Asr` /
/// `The prayer is starting now.`
pub fn notice(event: &PrayerEvent, tz: &TimeZone) -> Notice {
    let prayer = &event.prayer;
    let name = prayer.display_name();
    match event.kind {
        PrayerEventKind::Adhan => Notice {
            summary: format!("{name} · {}", prayer.display_arabic_name()),
            body: match prayer.iqama {
                Some(iqama) => format!("It's time for {name}. Iqama at {}.", clock_time(iqama, tz)),
                None => format!("It's time for {name}."),
            },
        },
        PrayerEventKind::Iqama => Notice {
            summary: format!("Iqama · {name}"),
            body: "The prayer is starting now.".to_owned(),
        },
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use mawakit::mawaqit;

    const FIXTURE: &str = include_str!("../../../../MawaKit/spec/fixtures/assunna-hannover.html");

    fn ts(s: &str) -> Timestamp {
        s.parse().unwrap_or_else(|e| unreachable!("{e}"))
    }

    fn timetable() -> MosqueTimetable {
        let configuration = mawaqit::MosqueConfiguration::from_page(FIXTURE)
            .unwrap_or_else(|e| unreachable!("{e}"));
        MosqueTimetable::new(configuration, ts("2026-10-23T08:00:00Z"))
    }

    #[test]
    fn tiny_countdown_fits_a_tray_icon() {
        let cases = [
            (0.0, "0s"),
            (45.0, "45s"),
            (59.0, "59s"),
            (59.5, "1m"),
            (60.0, "1m"),
            (61.0, "2m"),
            (23.0 * 60.0, "23m"),
            (3600.0, "1h"),
            (3601.0, "1:01"),
            (5000.0, "1:24"),
            (9.0 * 3600.0 + 59.0 * 60.0, "9:59"),
            (10.0 * 3600.0 + 1.0, "11h"),
            (36000.0, "10h"),
        ];
        for (seconds, expected) in cases {
            assert_eq!(tiny_countdown(seconds), expected, "{seconds}s");
            assert!(
                crate::font::text_width(expected) <= 20,
                "{expected} too wide"
            );
        }
    }

    #[test]
    fn tiny_valid_for_predicts_the_next_change() {
        for seconds in [
            1.5,
            58.7,
            60.5,
            3599.0,
            5000.0,
            9.0 * 3600.0,
            10.5 * 3600.0,
            11.2 * 3600.0,
        ] {
            let wait = tiny_valid_for(seconds);
            assert!(wait > 0.0, "{seconds}");
            assert_eq!(
                tiny_countdown(seconds - wait + 0.001),
                tiny_countdown(seconds),
                "unchanged during wait ({seconds})"
            );
        }
    }

    #[test]
    fn labels_follow_the_phase() {
        let t = timetable();
        let now = ts("2026-10-23T12:00:00Z"); // 14:00 in Hannover, before Asr at 15:41
        let status = t.status_at(now).unwrap_or_else(|| unreachable!());
        assert_eq!(label(&status, now), "Asr 1h 41m");
        assert_eq!(sentence(&status, now), "Asr in 1h 41m");

        let during_iqama = ts("2026-10-23T13:43:00Z"); // 15:43, Asr iqama at 15:51
        let status = t.status_at(during_iqama).unwrap_or_else(|| unreachable!());
        assert_eq!(label(&status, during_iqama), "Iqama 8m");
        assert_eq!(tone(&status), Tone::Iqama);
    }

    #[test]
    fn rows_mark_past_current_and_upcoming() {
        let t = timetable();
        let now = ts("2026-10-23T12:00:00Z");
        let schedule = t.displayed_schedule(now).unwrap_or_else(|| unreachable!());
        let rows = rows(&schedule, t.status_at(now).as_ref(), now, t.time_zone());
        let summary: Vec<_> = rows
            .iter()
            .map(|r| (r.name, r.adhan.as_str(), r.state))
            .collect();
        assert_eq!(
            summary,
            vec![
                ("Fajr", "06:15", RowState::Past),
                ("Shuruq", "07:55", RowState::Past),
                ("Jumu'a", "13:20", RowState::Past),
                ("Asr", "15:41", RowState::Current),
                ("Maghrib", "18:14", RowState::Upcoming),
                ("Isha", "19:44", RowState::Upcoming),
            ]
        );
        assert_eq!(rows[3].iqama.as_deref(), Some("15:51"));
        assert!(rows[1].is_sunrise);
    }

    #[test]
    fn card_and_date_after_isha_point_to_tomorrow() {
        let t = timetable();
        let now = ts("2026-10-23T20:00:00Z"); // 22:00 Friday
        let status = t.status_at(now).unwrap_or_else(|| unreachable!());
        let card = card(&status, now, &t);
        assert_eq!(card.name, "Fajr");
        assert_eq!(card.heading, "NEXT PRAYER");
        assert_eq!(card.detail, "Tomorrow at 06:15 · Iqama 06:45");
        assert_eq!(card.clock, "8:15:00");

        let shown = t.displayed_schedule(now).unwrap_or_else(|| unreachable!());
        assert_eq!(
            date_line(shown.day, now, t.time_zone()),
            "Tomorrow, Sat, 24 Oct"
        );
    }

    #[test]
    fn notifies_events_that_just_became_due() {
        let t = timetable();
        let both = [PrayerEventKind::Adhan, PrayerEventKind::Iqama];
        // Asr: adhan 15:41, iqama 15:51 (13:41 / 13:51 UTC).
        let due = due_events(
            &t,
            ts("2026-10-23T13:40:00Z"),
            ts("2026-10-23T13:41:00Z"),
            &both,
        );
        assert_eq!(due.len(), 1);
        assert_eq!(due[0].kind, PrayerEventKind::Adhan);
        assert_eq!(due[0].prayer.display_name(), "Asr");

        // Nothing new between two ticks without an event.
        assert!(
            due_events(
                &t,
                ts("2026-10-23T13:41:00Z"),
                ts("2026-10-23T13:45:00Z"),
                &both
            )
            .is_empty()
        );

        // Only the kinds asked for.
        let iqama_only = due_events(
            &t,
            ts("2026-10-23T13:40:00Z"),
            ts("2026-10-23T13:52:00Z"),
            &[PrayerEventKind::Iqama],
        );
        assert_eq!(
            iqama_only.iter().map(|e| e.kind).collect::<Vec<_>>(),
            vec![PrayerEventKind::Iqama]
        );
        assert!(
            due_events(
                &t,
                ts("2026-10-23T13:40:00Z"),
                ts("2026-10-23T13:52:00Z"),
                &[]
            )
            .is_empty()
        );
    }

    #[test]
    fn drops_events_missed_long_ago() {
        let t = timetable();
        let both = [PrayerEventKind::Adhan, PrayerEventKind::Iqama];
        // Waking at 15:54 after a suspend since the morning: only the Asr iqama (15:51) is
        // recent enough; the Fajr, Jumu'a and Asr adhan alerts are dropped.
        let due = due_events(
            &t,
            ts("2026-10-23T04:00:00Z"),
            ts("2026-10-23T13:54:00Z"),
            &both,
        );
        assert_eq!(due.len(), 1);
        assert_eq!(due[0].kind, PrayerEventKind::Iqama);
    }

    #[test]
    fn notification_text() {
        let t = timetable();
        let events = t.events_after(
            ts("2026-10-23T13:00:00Z"),
            0,
            vec![PrayerEventKind::Adhan, PrayerEventKind::Iqama],
        );
        let adhan = notice(&events[0], t.time_zone());
        assert_eq!(adhan.summary, "Asr · العصر");
        assert_eq!(adhan.body, "It's time for Asr. Iqama at 15:51.");
        let iqama = notice(&events[1], t.time_zone());
        assert_eq!(iqama.summary, "Iqama · Asr");
        assert_eq!(iqama.body, "The prayer is starting now.");

        // Jumu'a has no iqama time.
        let friday = t.events_after(ts("2026-10-23T11:00:00Z"), 0, vec![PrayerEventKind::Adhan]);
        assert_eq!(
            notice(&friday[0], t.time_zone()).body,
            "It's time for Jumu'a."
        );
    }
}
