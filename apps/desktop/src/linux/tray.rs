//! The tray icon and its menu. On Linux (AppIndicator) clicking the icon opens the menu,
//! so the menu itself shows the countdown and the day's times.

use tray_icon::menu::{Menu, MenuEvent, MenuId, MenuItem, PredefinedMenuItem};
use tray_icon::{Icon, TrayIcon, TrayIconBuilder};

use super::{Indicator, IndicatorState};
use crate::icon::{self, Image};
use crate::view::{self, Row, RowState};

const ROWS: usize = 6;

pub struct Tray {
    icon: TrayIcon,
    header: MenuItem,
    mosque: MenuItem,
    rows: Vec<MenuItem>,
    // What is currently shown, so only changes are sent to the panel (over D-Bus).
    shown_icon: String,
    shown_label: Option<String>,
    shown_rows: Vec<(String, bool)>,
}

pub mod ids {
    pub const OPEN: &str = "open";
    pub const REFRESH: &str = "refresh";
    pub const QUIT: &str = "quit";
}

impl Tray {
    pub fn new() -> Result<Self, Box<dyn std::error::Error>> {
        let header = MenuItem::new("SalatWidget", false, None);
        let mosque = MenuItem::new("", false, None);
        let rows: Vec<MenuItem> = (0..ROWS).map(|_| MenuItem::new("", false, None)).collect();

        let menu = Menu::new();
        menu.append(&header)?;
        menu.append(&mosque)?;
        menu.append(&PredefinedMenuItem::separator())?;
        for row in &rows {
            menu.append(row)?;
        }
        menu.append(&PredefinedMenuItem::separator())?;
        menu.append(&MenuItem::with_id(
            ids::OPEN,
            "Open SalatWidget…",
            true,
            None,
        ))?;
        menu.append(&MenuItem::with_id(
            ids::REFRESH,
            "Refresh Times",
            true,
            None,
        ))?;
        menu.append(&PredefinedMenuItem::separator())?;
        menu.append(&MenuItem::with_id(ids::QUIT, "Quit", true, None))?;

        let icon = TrayIconBuilder::new()
            // A stable ID, or the panel remembers a new tray item on every launch.
            .with_id("salatwidget")
            .with_icon(to_icon(icon::crescent())?)
            .with_menu(Box::new(menu))
            .with_tooltip("SalatWidget")
            .build()?;

        Ok(Self {
            icon,
            header,
            mosque,
            rows,
            shown_icon: "crescent".into(),
            shown_label: None,
            shown_rows: Vec::new(),
        })
    }
}

impl Indicator for Tray {
    /// Shows `status` (or the idle state) in the icon, the label and the menu.
    fn show(&mut self, state: IndicatorState<'_>) {
        let IndicatorState {
            status,
            now,
            rows,
            mosque_name,
            needs_mosque,
        } = state;
        // Icon: countdown badge, or the crescent when there's nothing to count down to.
        let (icon_key, image) = match status {
            Some(status) => {
                let text = view::tiny_countdown(status.remaining(now));
                let tone = view::tone(status);
                (format!("{text}/{tone:?}"), Some((text, tone)))
            }
            None => ("crescent".to_owned(), None),
        };
        if icon_key != self.shown_icon {
            let rendered = match image {
                Some((text, tone)) => icon::badge(&text, tone),
                None => icon::crescent(),
            };
            match to_icon(rendered).map(|icon| self.icon.set_icon(Some(icon))) {
                Ok(Ok(())) => self.shown_icon = icon_key,
                Ok(Err(error)) => eprintln!("salatwidget: icon: {error}"),
                Err(error) => eprintln!("salatwidget: icon: {error}"),
            }
        }

        // Label (shown next to the icon by desktops that support it) and menu header.
        let label = status.map(|s| view::label(s, now));
        if label != self.shown_label {
            self.icon.set_title(label.as_deref());
            let header = match (status, needs_mosque) {
                (Some(s), _) => view::sentence(s, now),
                (None, true) => "Choose a mosque to get started".to_owned(),
                (None, false) => "Loading prayer times…".to_owned(),
            };
            self.header.set_text(header);
            self.shown_label = label;
        }
        self.mosque.set_text(mosque_name.unwrap_or("SalatWidget"));

        // Timetable rows: the next prayer marked, past ones greyed out.
        let texts: Vec<(String, bool)> = (0..ROWS)
            .map(|i| match rows.and_then(|r| r.get(i)) {
                Some(row) => (row_text(row), row.state != RowState::Past),
                None => ("–".to_owned(), false),
            })
            .collect();
        if texts != self.shown_rows {
            for (item, (text, enabled)) in self.rows.iter().zip(&texts) {
                item.set_text(text);
                item.set_enabled(*enabled);
            }
            self.shown_rows = texts;
        }
    }
}

fn row_text(row: &Row) -> String {
    let marker = if row.state == RowState::Current {
        "▸ "
    } else {
        "    "
    };
    match &row.iqama {
        Some(iqama) => format!("{marker}{}  {}   ·   Iqama {iqama}", row.name, row.adhan),
        None => format!("{marker}{}  {}", row.name, row.adhan),
    }
}

fn to_icon(image: Image) -> Result<Icon, tray_icon::BadIcon> {
    Icon::from_rgba(image.rgba, image.size, image.size)
}

/// Routes menu clicks (delivered on GTK's thread) to the app.
pub fn install_menu_handler() {
    MenuEvent::set_event_handler(Some(|event: MenuEvent| {
        let id: &MenuId = &event.id;
        match id.0.as_str() {
            ids::OPEN => super::with_app(super::show_panel),
            ids::REFRESH => super::with_app(super::refresh),
            ids::QUIT => super::quit(),
            _ => {}
        }
    }));
}
