//! The Linux app logic, shared by the tray app and the XFCE panel plugin: ticking,
//! loading timetables, choosing a mosque and the GTK popup. What sits in the panel
//! (a tray icon with a menu, or a text label) is an [`Indicator`].

pub mod panel;
mod tray;

use std::cell::RefCell;
use std::rc::Rc;
use std::time::Duration;

use gtk::glib;
use jiff::Timestamp;
use mawakit::{MosqueTimetable, countdown, mawaqit};

use crate::store::{Cached, Settings};
use crate::view::{self, Row};

use panel::Panel;
use tray::Tray;

/// What an indicator shows: the countdown, today's rows and the mosque.
pub struct IndicatorState<'a> {
    pub status: Option<&'a mawakit::PrayerStatus>,
    pub now: Timestamp,
    pub rows: Option<&'a [Row]>,
    pub mosque_name: Option<&'a str>,
    pub needs_mosque: bool,
}

/// The part of the app that lives in the panel.
pub trait Indicator {
    fn show(&mut self, state: IndicatorState<'_>);

    /// Where the indicator is on screen, so the popup can open next to it.
    fn anchor(&self) -> Option<gtk::gdk::Rectangle> {
        None
    }
}

/// Wake at least this often. GLib timers use the monotonic clock, which stops during
/// suspend, so a cap keeps the countdown right after waking up (and is nearly free:
/// the label changes once a minute anyway).
const MAX_TICK: Duration = Duration::from_secs(60);
/// Back-off between automatic refresh attempts while offline.
const RETRY_SECONDS: i64 = 15 * 60;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum LoadState {
    Idle,
    Loading,
    Failed(String),
}

pub struct App {
    settings: Settings,
    cached: Option<Cached>,
    timetable: Option<Rc<MosqueTimetable>>,
    load_state: LoadState,
    last_attempt: Option<Timestamp>,
    indicator: Box<dyn Indicator>,
    panel: Option<Panel>,
    /// Whether "Quit" makes sense: true for the tray app, false inside the XFCE panel.
    can_quit: bool,
    /// Incremented whenever ticks are rescheduled; stale timers check it and stop.
    tick_generation: u64,
}

thread_local! {
    // Menu callbacks come from tray-icon without context but always on this (GTK's)
    // thread, so the app state lives here instead of being captured.
    static APP: RefCell<Option<Rc<RefCell<App>>>> = const { RefCell::new(None) };
}

/// Runs `f` with the app, unless it has quit.
fn with_app(f: impl FnOnce(&Rc<RefCell<App>>)) {
    let app = APP.with(|cell| cell.borrow().clone());
    if let Some(app) = app {
        f(&app);
    }
}

/// The tray app: initialises GTK, shows the tray icon and runs until "Quit".
pub fn run(
    mosque_argument: Option<String>,
    open_panel: bool,
    close_panel_after: Option<u64>,
) -> Result<(), Box<dyn std::error::Error>> {
    gtk::init()?;
    if let Some(input) = mosque_argument {
        let slug =
            mawaqit::mosque_slug(&input).ok_or("that doesn't look like a Mawaqit mosque link")?;
        Settings { mosque: Some(slug) }.save()?;
    }

    let app = start(Box::new(Tray::new()?), true);
    tray::install_menu_handler();
    if open_panel {
        show_panel(&app);
    }
    if let Some(seconds) = close_panel_after {
        // Debug builds: lets a script measure the app after the popup closes.
        let app = app.clone();
        glib::timeout_add_local_once(Duration::from_secs(seconds), move || {
            with_panel(&app, |panel| panel.hide());
        });
    }

    gtk::main();
    APP.with(|cell| cell.borrow_mut().take());
    Ok(())
}

/// Starts the app with `indicator` on an already running GTK main loop (the tray app's,
/// or the XFCE panel's). Opens the popup right away when no mosque is chosen yet.
pub fn start(indicator: Box<dyn Indicator>, can_quit: bool) -> Rc<RefCell<App>> {
    panel::install_css();
    let settings = Settings::load();
    let cached = settings.mosque.as_deref().and_then(Cached::load);
    let timetable = cached.as_ref().and_then(Cached::timetable).map(Rc::new);

    let app = Rc::new(RefCell::new(App {
        settings,
        cached,
        timetable,
        load_state: LoadState::Idle,
        last_attempt: None,
        indicator,
        panel: None,
        can_quit,
        tick_generation: 0,
    }));
    APP.with(|cell| *cell.borrow_mut() = Some(app.clone()));

    reschedule(&app);
    refresh_if_needed(&app);
    if app.borrow().settings.mosque.is_none() {
        show_panel(&app);
    }
    app
}

/// Opens the popup, or closes it if it's open (for indicators that receive clicks).
pub fn toggle_panel() {
    with_app(|app| {
        let visible = app.borrow().panel.as_ref().is_some_and(Panel::is_visible);
        if visible {
            with_panel(app, Panel::hide);
        } else {
            show_panel(app);
        }
    });
}

// MARK: Ticking

/// Brings the tray up to date and schedules the next update for when it would change.
fn reschedule(app: &Rc<RefCell<App>>) {
    let now = Timestamp::now();
    let (generation, sleep) = {
        let mut state = app.borrow_mut();
        state.tick_generation += 1;
        let timetable = state.timetable.clone();
        let status = timetable.as_ref().and_then(|t| t.status_at(now));
        let mosque_name = timetable
            .as_ref()
            .map(|t| t.configuration().display_name().to_owned());
        let rows = timetable.as_ref().and_then(|t| {
            let schedule = t.displayed_schedule(now)?;
            Some(view::rows(&schedule, status.as_ref(), now, t.time_zone()))
        });
        let needs_mosque = state.settings.mosque.is_none();
        state.indicator.show(IndicatorState {
            status: status.as_ref(),
            now,
            rows: rows.as_deref(),
            mosque_name: mosque_name.as_deref(),
            needs_mosque,
        });

        // Sleep until the label, the icon text or the timetable rows would change.
        let mut sleep = MAX_TICK.as_secs_f64();
        if let Some(status) = &status {
            sleep = sleep
                .min(countdown::refresh_interval(Some(status), now, true, sleep))
                .min(view::tiny_valid_for(status.remaining(now)) + 0.02);
        }
        if let Some(t) = &timetable {
            let boundary = t.next_boundary(now).as_second() - now.as_second();
            sleep = sleep.min(boundary.max(0) as f64 + 0.02);
        }
        (state.tick_generation, sleep.max(0.05))
    };

    let app = app.clone();
    glib::timeout_add_local_once(Duration::from_secs_f64(sleep), move || {
        if app.borrow().tick_generation == generation {
            reschedule(&app);
            refresh_if_needed(&app);
        }
    });
}

// MARK: Loading

fn refresh_if_needed(app: &Rc<RefCell<App>>) {
    let now = Timestamp::now();
    let due = {
        let state = app.borrow();
        if state.settings.mosque.is_none() || state.load_state == LoadState::Loading {
            false
        } else {
            let stale = match (&state.cached, &state.timetable) {
                (Some(cached), Some(timetable)) => cached.is_stale(now, timetable),
                _ => true,
            };
            let backing_off = matches!(state.load_state, LoadState::Failed(_))
                && state
                    .last_attempt
                    .is_some_and(|t| now.as_second() - t.as_second() < RETRY_SECONDS);
            stale && !backing_off
        }
    };
    if due {
        refresh(app);
    }
}

/// Downloads the selected mosque's timetable in the background.
fn refresh(app: &Rc<RefCell<App>>) {
    let Some(slug) = app.borrow().settings.mosque.clone() else {
        return;
    };
    load(app, slug, false);
}

/// Fetches `slug` off the main thread, then applies it (and saves it as the selected
/// mosque when `select` is true).
fn load(app: &Rc<RefCell<App>>, slug: String, select: bool) {
    {
        let mut state = app.borrow_mut();
        state.load_state = LoadState::Loading;
        state.last_attempt = Some(Timestamp::now());
    }
    update_panel(app);

    let app = app.clone();
    glib::MainContext::default().spawn_local(async move {
        let result = gtk::gio::spawn_blocking(move || Cached::fetch(&slug))
            .await
            .unwrap_or_else(|_| Err("the download stopped unexpectedly".to_owned()));
        match result {
            Ok(cached) => {
                if let Err(error) = cached.save() {
                    eprintln!("salatwidget: couldn't cache the timetable: {error}");
                }
                {
                    let mut state = app.borrow_mut();
                    if select {
                        state.settings.mosque = Some(cached.slug.clone());
                        if let Err(error) = state.settings.save() {
                            eprintln!("salatwidget: couldn't save settings: {error}");
                        }
                    }
                    // Keep the current timetable object if nothing changed, so views
                    // aren't rebuilt for nothing.
                    let unchanged = state.cached.as_ref().is_some_and(|c| c.slug == cached.slug)
                        && state.timetable.is_some()
                        && !select;
                    if !unchanged || state.timetable.is_none() {
                        state.timetable = cached.timetable().map(Rc::new);
                    }
                    state.cached = Some(cached);
                    state.load_state = LoadState::Idle;
                }
                if select {
                    with_panel(&app, |panel| panel.show_times());
                }
            }
            Err(message) => {
                eprintln!("salatwidget: {message}");
                app.borrow_mut().load_state = LoadState::Failed(message);
            }
        }
        reschedule(&app);
        update_panel(&app);
    });
}

/// Switches to the mosque in `input` (a Mawaqit link or slug).
fn select_mosque(app: &Rc<RefCell<App>>, input: &str) -> Result<(), String> {
    let slug =
        mawaqit::mosque_slug(input).ok_or("That doesn't look like a Mawaqit mosque link.")?;
    load(app, slug, true);
    Ok(())
}

// MARK: Panel

fn with_panel(app: &Rc<RefCell<App>>, f: impl FnOnce(&Panel)) {
    let panel = app.borrow().panel.clone();
    if let Some(panel) = panel {
        f(&panel);
    }
}

fn show_panel(app: &Rc<RefCell<App>>) {
    if app.borrow().panel.is_none() {
        let panel = Panel::new();
        app.borrow_mut().panel = Some(panel);
    }
    update_panel(app);
    let anchor = app.borrow().indicator.anchor();
    with_panel(app, |panel| {
        if app.borrow().settings.mosque.is_none() {
            panel.show_picker(false);
        }
        panel.present(anchor);
    });
}

/// Pushes the current state into the popup, if it exists.
fn update_panel(app: &Rc<RefCell<App>>) {
    let snapshot = {
        let state = app.borrow();
        panel::Snapshot {
            timetable: state.timetable.clone(),
            load_state: state.load_state.clone(),
            fetched_at: state.cached.as_ref().map(|c| c.fetched_at),
            has_mosque: state.settings.mosque.is_some(),
            slug: state.settings.mosque.clone(),
            can_quit: state.can_quit,
        }
    };
    with_panel(app, |panel| panel.update(snapshot));
}

fn quit() {
    gtk::main_quit();
}
