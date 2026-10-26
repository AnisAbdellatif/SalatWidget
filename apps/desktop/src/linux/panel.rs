//! The popup panel (GTK 3, XFCE's own toolkit): a live countdown card and the day's
//! times, plus a page for choosing the mosque. Opened from the tray menu.

use std::cell::{Cell, RefCell};
use std::rc::Rc;
use std::time::Duration;

use gtk::prelude::*;
use gtk::{gdk, glib};
use jiff::Timestamp;
use mawakit::{MosqueTimetable, PrayerStatus, mawaqit};

use super::LoadState;
use crate::icon::Tone;
use crate::view::{self, RowState};

const WIDTH: i32 = 340;
const CSS: &str = r#"
.salat-panel { padding: 14px; }
.salat-mosque { font-weight: bold; font-size: 11pt; }
.salat-dim { opacity: 0.65; }
.salat-card {
    border-radius: 12px; padding: 14px; color: white;
    background-image: linear-gradient(135deg, #1aa88a, #055a5e);
}
.salat-card.iqama { background-image: linear-gradient(135deg, #ee8c29, #c44f1e); }
.salat-card label { color: white; }
.salat-heading { font-size: 8pt; font-weight: bold; opacity: 0.85; }
.salat-name { font-size: 15pt; font-weight: bold; }
.salat-clock { font-size: 22pt; font-weight: bold; font-feature-settings: "tnum"; }
.salat-card progressbar trough {
    min-height: 4px; border: none; border-radius: 2px; box-shadow: none;
    background-image: none; background-color: rgba(255,255,255,0.25);
}
.salat-card progressbar progress {
    min-height: 4px; border: none; border-radius: 2px; box-shadow: none;
    background-image: none; background-color: white;
}
.salat-row { padding: 4px 8px; border-radius: 6px; }
.salat-row label { font-feature-settings: "tnum"; }
.salat-row.current { background-color: alpha(#0d8f78, 0.22); }
.salat-row.current label { font-weight: bold; }
.salat-row.past label, .salat-row.sunrise label { opacity: 0.5; }
.salat-error { color: #e0533d; }
"#;

pub fn install_css() {
    let provider = gtk::CssProvider::new();
    if let Err(error) = provider.load_from_data(CSS.as_bytes()) {
        eprintln!("salatwidget: css: {error}");
        return;
    }
    if let Some(screen) = gdk::Screen::default() {
        gtk::StyleContext::add_provider_for_screen(
            &screen,
            &provider,
            gtk::STYLE_PROVIDER_PRIORITY_APPLICATION,
        );
    }
}

/// What the panel shows, handed over by the app.
pub struct Snapshot {
    pub timetable: Option<Rc<MosqueTimetable>>,
    pub load_state: LoadState,
    pub fetched_at: Option<Timestamp>,
    pub has_mosque: bool,
    pub slug: Option<String>,
    pub can_quit: bool,
}

struct RowWidgets {
    container: gtk::Box,
    name: gtk::Label,
    arabic: gtk::Label,
    adhan: gtk::Label,
    iqama: gtk::Label,
}

struct Inner {
    window: gtk::Window,
    stack: gtk::Stack,
    mosque: gtk::Label,
    date: gtk::Label,
    card: gtk::Box,
    heading: gtk::Label,
    card_arabic: gtk::Label,
    name: gtk::Label,
    clock: gtk::Label,
    progress: gtk::ProgressBar,
    detail: gtk::Label,
    rows: Vec<RowWidgets>,
    footer: gtk::Label,
    quit: gtk::Button,
    placeholder: gtk::Label,
    times_content: gtk::Box,
    picker_entry: gtk::Entry,
    picker_message: gtk::Label,
    picker_back: gtk::Button,
    picker_use: gtk::Button,
    timetable: RefCell<Option<Rc<MosqueTimetable>>>,
    status: RefCell<Option<PrayerStatus>>,
    shown_day: Cell<Option<i64>>,
    slug: RefCell<Option<String>>,
    /// Incremented on every show/hide; per-second timers of older generations stop.
    live_generation: Cell<u64>,
}

/// Cheap to clone: all clones share the same window.
#[derive(Clone)]
pub struct Panel(Rc<Inner>);

impl Default for Panel {
    fn default() -> Self {
        Self::new()
    }
}

impl Panel {
    pub fn new() -> Self {
        let window = gtk::Window::new(gtk::WindowType::Toplevel);
        window.set_title("SalatWidget");
        window.set_decorated(false);
        window.set_resizable(false);
        window.set_skip_taskbar_hint(true);
        window.set_skip_pager_hint(true);
        window.set_keep_above(true);
        window.set_type_hint(gdk::WindowTypeHint::Utility);
        window.set_default_size(WIDTH, -1);
        window.set_size_request(WIDTH, -1);

        let stack = gtk::Stack::new();
        stack.set_transition_type(gtk::StackTransitionType::Crossfade);
        stack.set_vhomogeneous(false);
        stack.set_interpolate_size(true);
        window.add(&stack);

        // ── Times page ────────────────────────────────────────────────────────
        let times = gtk::Box::new(gtk::Orientation::Vertical, 12);
        times.style_context().add_class("salat-panel");

        let header = gtk::Box::new(gtk::Orientation::Horizontal, 6);
        let titles = gtk::Box::new(gtk::Orientation::Vertical, 2);
        let mosque = label("", 0.0, &["salat-mosque"]);
        mosque.set_line_wrap(true);
        mosque.set_max_width_chars(28);
        let date = label("", 0.0, &["salat-dim"]);
        titles.pack_start(&mosque, false, false, 0);
        titles.pack_start(&date, false, false, 0);
        header.pack_start(&titles, true, true, 0);
        let change = icon_button("go-home-symbolic", "Change mosque");
        let close = icon_button("window-close-symbolic", "Close");
        header.pack_end(&close, false, false, 0);
        header.pack_end(&change, false, false, 0);
        times.pack_start(&header, false, false, 0);

        let card = gtk::Box::new(gtk::Orientation::Vertical, 8);
        card.style_context().add_class("salat-card");
        let top = gtk::Box::new(gtk::Orientation::Horizontal, 6);
        let heading = label("NEXT PRAYER", 0.0, &["salat-heading"]);
        let card_arabic = label("", 1.0, &[]);
        top.pack_start(&heading, true, true, 0);
        top.pack_end(&card_arabic, false, false, 0);
        let middle = gtk::Box::new(gtk::Orientation::Horizontal, 6);
        let name = label("", 0.0, &["salat-name"]);
        name.set_valign(gtk::Align::Baseline);
        let clock = label("", 1.0, &["salat-clock"]);
        clock.set_valign(gtk::Align::Baseline);
        middle.pack_start(&name, true, true, 0);
        middle.pack_end(&clock, false, false, 0);
        let progress = gtk::ProgressBar::new();
        let detail = label("", 0.0, &[]);
        detail.set_opacity(0.9);
        card.pack_start(&top, false, false, 0);
        card.pack_start(&middle, false, false, 0);
        card.pack_start(&progress, false, false, 0);
        card.pack_start(&detail, false, false, 0);

        let table = gtk::Box::new(gtk::Orientation::Vertical, 2);
        let columns = gtk::Box::new(gtk::Orientation::Horizontal, 8);
        columns.set_margin_start(8);
        columns.set_margin_end(8);
        columns.pack_start(&label("", 0.0, &[]), true, true, 0);
        let adhan_heading = label("ADHAN", 1.0, &["salat-heading", "salat-dim"]);
        adhan_heading.set_width_chars(6);
        let iqama_heading = label("IQAMA", 1.0, &["salat-heading", "salat-dim"]);
        iqama_heading.set_width_chars(6);
        columns.pack_start(&adhan_heading, false, false, 0);
        columns.pack_start(&iqama_heading, false, false, 0);
        table.pack_start(&columns, false, false, 0);
        let rows: Vec<RowWidgets> = (0..6)
            .map(|_| {
                let container = gtk::Box::new(gtk::Orientation::Horizontal, 8);
                container.style_context().add_class("salat-row");
                let name = label("", 0.0, &[]);
                let arabic = label("", 0.0, &["salat-dim"]);
                let adhan = label("", 1.0, &[]);
                adhan.set_width_chars(6);
                let iqama = label("", 1.0, &["salat-dim"]);
                iqama.set_width_chars(6);
                container.pack_start(&name, false, false, 0);
                container.pack_start(&arabic, true, true, 0);
                container.pack_start(&adhan, false, false, 0);
                container.pack_start(&iqama, false, false, 0);
                table.pack_start(&container, false, false, 0);
                RowWidgets {
                    container,
                    name,
                    arabic,
                    adhan,
                    iqama,
                }
            })
            .collect();

        let placeholder = label("Loading prayer times…", 0.5, &["salat-dim"]);
        placeholder.set_margin_top(40);
        placeholder.set_margin_bottom(40);
        placeholder.set_line_wrap(true);

        let times_content = gtk::Box::new(gtk::Orientation::Vertical, 12);
        times_content.pack_start(&card, false, false, 0);
        times_content.pack_start(&table, false, false, 0);
        times.pack_start(&times_content, false, false, 0);
        times.pack_start(&placeholder, false, false, 0);

        times.pack_start(
            &gtk::Separator::new(gtk::Orientation::Horizontal),
            false,
            false,
            0,
        );
        let footer_box = gtk::Box::new(gtk::Orientation::Horizontal, 4);
        let footer = label("", 0.0, &["salat-dim"]);
        footer.set_ellipsize(gtk::pango::EllipsizeMode::End);
        footer_box.pack_start(&footer, true, true, 0);
        let refresh = icon_button("view-refresh-symbolic", "Refresh");
        let web = icon_button("web-browser-symbolic", "Open on mawaqit.net");
        let quit = icon_button("application-exit-symbolic", "Quit SalatWidget");
        footer_box.pack_start(&refresh, false, false, 0);
        footer_box.pack_start(&web, false, false, 0);
        footer_box.pack_start(&quit, false, false, 0);
        times.pack_start(&footer_box, false, false, 0);
        stack.add_named(&times, "times");

        // ── Mosque page ───────────────────────────────────────────────────────
        let picker = gtk::Box::new(gtk::Orientation::Vertical, 10);
        picker.style_context().add_class("salat-panel");
        let picker_header = gtk::Box::new(gtk::Orientation::Horizontal, 6);
        let picker_back = icon_button("go-previous-symbolic", "Back");
        picker_header.pack_start(&picker_back, false, false, 0);
        picker_header.pack_start(
            &label("Choose Mosque", 0.0, &["salat-mosque"]),
            true,
            true,
            0,
        );
        picker.pack_start(&picker_header, false, false, 0);
        let intro = label(
            "Open your mosque's page on mawaqit.net and paste its address here. No account needed.",
            0.0,
            &["salat-dim"],
        );
        intro.set_line_wrap(true);
        intro.set_max_width_chars(40);
        picker.pack_start(&intro, false, false, 0);
        let entry_row = gtk::Box::new(gtk::Orientation::Horizontal, 6);
        let picker_entry = gtk::Entry::new();
        picker_entry.set_placeholder_text(Some("mawaqit.net/de/your-mosque"));
        let picker_use = gtk::Button::with_label("Use");
        picker_use.style_context().add_class("suggested-action");
        entry_row.pack_start(&picker_entry, true, true, 0);
        entry_row.pack_start(&picker_use, false, false, 0);
        picker.pack_start(&entry_row, false, false, 0);
        let picker_message = label("", 0.0, &[]);
        picker_message.set_line_wrap(true);
        picker_message.set_max_width_chars(40);
        picker.pack_start(&picker_message, false, false, 0);
        stack.add_named(&picker, "mosque");

        let panel = Panel(Rc::new(Inner {
            window,
            stack,
            mosque,
            date,
            card,
            heading,
            card_arabic,
            name,
            clock,
            progress,
            detail,
            rows,
            footer,
            quit: quit.clone(),
            placeholder,
            times_content,
            picker_entry,
            picker_message,
            picker_back,
            picker_use,
            timetable: RefCell::new(None),
            status: RefCell::new(None),
            shown_day: Cell::new(None),
            slug: RefCell::new(None),
            live_generation: Cell::new(0),
        }));

        // ── Behaviour ─────────────────────────────────────────────────────────
        let inner = &panel.0;
        inner
            .window
            .connect_delete_event(|window, _| window.hide_on_delete());
        inner.window.connect_focus_out_event(|window, _| {
            window.hide();
            glib::Propagation::Proceed
        });
        inner.window.connect_key_press_event(|window, event| {
            if event.keyval() == gdk::keys::constants::Escape {
                window.hide();
                return glib::Propagation::Stop;
            }
            glib::Propagation::Proceed
        });
        let weak = Rc::downgrade(&panel.0);
        inner.window.connect_hide(move |_| {
            if let Some(inner) = weak.upgrade() {
                // Stops the per-second countdown while hidden.
                inner.live_generation.set(inner.live_generation.get() + 1);
            }
        });
        let weak = Rc::downgrade(&panel.0);
        inner.window.connect_show(move |_| {
            if let Some(inner) = weak.upgrade() {
                Panel(inner).start_live_updates();
            }
        });

        close.connect_clicked({
            let window = inner.window.clone();
            move |_| window.hide()
        });
        change.connect_clicked({
            let panel = panel.clone();
            move |_| panel.show_picker(true)
        });
        refresh.connect_clicked(|_| super::with_app(super::refresh));
        quit.connect_clicked(|_| super::quit());
        web.connect_clicked({
            let panel = panel.clone();
            move |_| {
                if let Some(slug) = panel.0.slug.borrow().as_deref()
                    && let Err(error) = std::process::Command::new("xdg-open")
                        .arg(mawaqit::page_url(slug))
                        .spawn()
                {
                    eprintln!("salatwidget: couldn't open the browser: {error}");
                }
            }
        });
        picker_back_handler(&panel);
        let submit = {
            let panel = panel.clone();
            move || panel.submit_picker()
        };
        inner.picker_use.connect_clicked({
            let submit = submit.clone();
            move |_| submit()
        });
        inner.picker_entry.connect_activate(move |_| submit());
        inner.picker_entry.connect_changed({
            let message = inner.picker_message.clone();
            move |_| message.set_text("")
        });

        panel
    }

    /// Shows the panel above other windows: under `anchor` (the indicator's position)
    /// if known, otherwise near the top-right corner of the screen.
    pub fn present(&self, anchor: Option<gdk::Rectangle>) {
        let window = &self.0.window;
        window.show_all();
        self.apply_visibility();
        let display = gdk::Display::default();
        let monitor = display.as_ref().and_then(|display| match &anchor {
            Some(a) => display.monitor_at_point(a.x(), a.y()),
            None => display.primary_monitor().or_else(|| display.monitor(0)),
        });
        if let Some(area) = monitor.map(|m| m.workarea()) {
            let (width, height) = window.size();
            let (x, y) = match anchor {
                // Below a top panel, above a bottom one, aligned with the indicator.
                Some(a) => {
                    let x = (a.x() + a.width() - width).max(area.x() + 8);
                    let below = a.y() + a.height() + 4;
                    let y = if below + height <= area.y() + area.height() {
                        below
                    } else {
                        a.y() - height - 4
                    };
                    (x, y)
                }
                None => (area.x() + area.width() - width - 8, area.y() + 8),
            };
            window.move_(x, y);
        }
        window.present();
    }

    pub fn hide(&self) {
        self.0.window.hide();
    }

    pub fn is_visible(&self) -> bool {
        self.0.window.is_visible()
    }

    pub fn show_times(&self) {
        self.0.stack.set_visible_child_name("times");
    }

    /// Switches to the mosque page; `can_go_back` is false while no mosque is chosen.
    pub fn show_picker(&self, can_go_back: bool) {
        self.0.picker_back.set_visible(can_go_back);
        self.0.picker_message.set_text("");
        self.0.stack.set_visible_child_name("mosque");
        self.0.picker_entry.grab_focus();
    }

    fn submit_picker(&self) {
        let input = self.0.picker_entry.text().to_string();
        if input.trim().is_empty() {
            return;
        }
        let mut result = Ok(());
        super::with_app(|app| result = super::select_mosque(app, &input));
        match result {
            Ok(()) => self.set_picker_message("Loading…", false),
            Err(message) => self.set_picker_message(&message, true),
        }
    }

    fn set_picker_message(&self, text: &str, is_error: bool) {
        let message = &self.0.picker_message;
        message.set_text(text);
        let style = message.style_context();
        if is_error {
            style.add_class("salat-error")
        } else {
            style.remove_class("salat-error")
        }
    }

    /// Takes in new state from the app.
    pub fn update(&self, snapshot: Snapshot) {
        let inner = &self.0;
        *inner.timetable.borrow_mut() = snapshot.timetable.clone();
        *inner.slug.borrow_mut() = snapshot.slug.clone();
        inner.shown_day.set(None);

        inner
            .footer
            .set_text(&match (&snapshot.load_state, snapshot.fetched_at) {
                (LoadState::Loading, _) => "Updating…".to_owned(),
                (LoadState::Failed(_), Some(_)) => "Offline · showing saved times".to_owned(),
                (LoadState::Failed(message), None) => message.clone(),
                (LoadState::Idle, Some(at)) => format!("Updated {}", local_time(at)),
                (LoadState::Idle, None) => "mawaqit.net".to_owned(),
            });

        // Errors while choosing a mosque are shown on the picker page.
        if inner.stack.visible_child_name().as_deref() == Some("mosque") {
            match &snapshot.load_state {
                LoadState::Failed(message) => self.set_picker_message(message, true),
                LoadState::Loading => self.set_picker_message("Loading…", false),
                LoadState::Idle => {}
            }
        }
        if !snapshot.has_mosque {
            inner.picker_back.set_visible(false);
        }
        inner.quit.set_visible(snapshot.can_quit);
        inner.quit.set_no_show_all(!snapshot.can_quit);
        self.apply_visibility();
        self.refresh(Timestamp::now());
    }

    /// Shows either the times or a placeholder, depending on whether there's a timetable.
    fn apply_visibility(&self) {
        let has_timetable = self.0.timetable.borrow().is_some();
        self.0.times_content.set_visible(has_timetable);
        self.0.placeholder.set_visible(!has_timetable);
    }

    /// Redraws everything (cheap enough at prayer boundaries).
    fn refresh(&self, now: Timestamp) {
        let inner = &self.0;
        let Some(timetable) = inner.timetable.borrow().clone() else {
            inner.mosque.set_text("SalatWidget");
            inner.date.set_text("");
            return;
        };
        let status = timetable.status_at(now);
        let tz = timetable.time_zone();
        inner
            .mosque
            .set_text(timetable.configuration().display_name());

        let Some(schedule) = timetable.displayed_schedule(now) else {
            inner
                .placeholder
                .set_text("This mosque hasn't published a timetable for today.");
            inner.times_content.set_visible(false);
            inner.placeholder.set_visible(true);
            return;
        };
        inner.date.set_text(&view::date_line(schedule.day, now, tz));
        inner.shown_day.set(Some(schedule.day.as_second()));

        for (widgets, row) in inner
            .rows
            .iter()
            .zip(view::rows(&schedule, status.as_ref(), now, tz))
        {
            widgets.name.set_text(row.name);
            widgets.arabic.set_text(row.arabic);
            widgets.adhan.set_text(&row.adhan);
            widgets.iqama.set_text(row.iqama.as_deref().unwrap_or(""));
            let style = widgets.container.style_context();
            for class in ["current", "past", "sunrise"] {
                style.remove_class(class);
            }
            match row.state {
                RowState::Current => style.add_class("current"),
                RowState::Past => style.add_class("past"),
                RowState::Upcoming => {}
            }
            if row.is_sunrise {
                style.add_class("sunrise");
            }
        }

        inner.card.set_visible(status.is_some());
        if let Some(status) = &status {
            let card = view::card(status, now, &timetable);
            inner.heading.set_text(card.heading);
            inner.card_arabic.set_text(card.arabic);
            inner.name.set_text(card.name);
            inner.detail.set_text(&card.detail);
            let style = inner.card.style_context();
            if card.tone == Tone::Iqama {
                style.add_class("iqama")
            } else {
                style.remove_class("iqama")
            }
        }
        *inner.status.borrow_mut() = status;
        self.tick(now);
    }

    /// Updates just the clock and progress; redraws all when the status changes.
    fn tick(&self, now: Timestamp) {
        let inner = &self.0;
        let current = inner.status.borrow().clone();
        let Some(timetable) = inner.timetable.borrow().clone() else {
            return;
        };
        let fresh = timetable.status_at(now);
        if fresh != current {
            self.refresh(now);
            return;
        }
        if let Some(status) = &current {
            inner
                .clock
                .set_text(&mawakit::countdown::clock(status.remaining(now)));
            inner.progress.set_fraction(status.progress(now));
        }
    }

    /// Ticks on whole seconds while the panel is visible, and stops when it hides.
    fn start_live_updates(&self) {
        let generation = self.0.live_generation.get() + 1;
        self.0.live_generation.set(generation);
        self.refresh(Timestamp::now());
        self.schedule_live_tick(generation);
    }

    fn schedule_live_tick(&self, generation: u64) {
        let now = Timestamp::now();
        let until_next_second = 1.0 - f64::from(now.subsec_nanosecond()) / 1e9 + 0.005;
        let panel = self.clone();
        glib::timeout_add_local_once(Duration::from_secs_f64(until_next_second), move || {
            if panel.0.live_generation.get() == generation && panel.0.window.is_visible() {
                panel.tick(Timestamp::now());
                panel.schedule_live_tick(generation);
            }
        });
    }
}

fn picker_back_handler(panel: &Panel) {
    let target = panel.clone();
    panel
        .0
        .picker_back
        .connect_clicked(move |_| target.show_times());
}

fn label(text: &str, xalign: f32, classes: &[&str]) -> gtk::Label {
    let label = gtk::Label::new(Some(text));
    label.set_xalign(xalign);
    let style = label.style_context();
    for class in classes {
        style.add_class(class);
    }
    label
}

fn icon_button(icon: &str, tooltip: &str) -> gtk::Button {
    let button = gtk::Button::from_icon_name(Some(icon), gtk::IconSize::Button);
    button.set_relief(gtk::ReliefStyle::None);
    button.set_tooltip_text(Some(tooltip));
    button.set_valign(gtk::Align::Center);
    button
}

/// `18:23` in the computer's own time zone (for "Updated …").
fn local_time(at: Timestamp) -> String {
    at.to_zoned(jiff::tz::TimeZone::system())
        .strftime("%H:%M")
        .to_string()
}
