//! Settings, the timetable cache and the login item, in the XDG base directories:
//! `~/.config/salatwidget/settings`, `~/.cache/salatwidget/<mosque>.json` and
//! `~/.config/autostart/salatwidget.desktop`.

use std::fs;
use std::io;
use std::path::{Path, PathBuf};

use jiff::Timestamp;
use mawakit::{MosqueTimetable, mawaqit};

const USER_AGENT: &str = concat!("SalatWidget/", env!("CARGO_PKG_VERSION"), " (Linux)");
/// Refetch at least this often: Mawaqit's "today" times may carry manual tweaks.
pub const REFRESH_INTERVAL_SECONDS: i64 = 6 * 3600;

/// An XDG base directory, e.g. `$XDG_CONFIG_HOME` or `~/.config`.
fn xdg_dir(variable: &str, fallback: &str) -> Option<PathBuf> {
    std::env::var_os(variable)
        .map(PathBuf::from)
        .filter(|p| p.is_absolute())
        .or_else(|| std::env::var_os("HOME").map(|home| PathBuf::from(home).join(fallback)))
}

fn config_dir() -> Option<PathBuf> {
    xdg_dir("XDG_CONFIG_HOME", ".config").map(|dir| dir.join("salatwidget"))
}

fn cache_dir() -> Option<PathBuf> {
    xdg_dir("XDG_CACHE_HOME", ".cache").map(|dir| dir.join("salatwidget"))
}

/// User preferences, stored as `key=value` lines.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct Settings {
    /// The selected mosque's Mawaqit slug, e.g. `assunna-hannover`.
    pub mosque: Option<String>,
    /// Desktop notification at each adhan.
    pub notify_adhan: bool,
    /// Desktop notification at each iqama.
    pub notify_iqama: bool,
}

impl Settings {
    pub fn load() -> Self {
        config_dir()
            .and_then(|dir| fs::read_to_string(dir.join("settings")).ok())
            .map(|text| Self::parse(&text))
            .unwrap_or_default()
    }

    pub fn save(&self) -> io::Result<()> {
        let dir = config_dir().ok_or_else(|| io::Error::other("no home directory"))?;
        fs::create_dir_all(&dir)?;
        fs::write(dir.join("settings"), self.serialize())
    }

    fn parse(text: &str) -> Self {
        let mut settings = Self::default();
        for line in text.lines() {
            let Some((key, value)) = line.split_once('=') else {
                continue;
            };
            let value = value.trim();
            match key.trim() {
                "mosque" => settings.mosque = mawaqit::mosque_slug(value),
                "notify-adhan" => settings.notify_adhan = value == "true",
                "notify-iqama" => settings.notify_iqama = value == "true",
                _ => {}
            }
        }
        settings
    }

    fn serialize(&self) -> String {
        let mut text = String::new();
        if let Some(mosque) = &self.mosque {
            text.push_str(&format!("mosque={mosque}\n"));
        }
        text.push_str(&format!("notify-adhan={}\n", self.notify_adhan));
        text.push_str(&format!("notify-iqama={}\n", self.notify_iqama));
        text
    }

    /// The kinds of events to notify about.
    pub fn notification_kinds(&self) -> Vec<mawakit::PrayerEventKind> {
        let mut kinds = Vec::new();
        if self.notify_adhan {
            kinds.push(mawakit::PrayerEventKind::Adhan);
        }
        if self.notify_iqama {
            kinds.push(mawakit::PrayerEventKind::Iqama);
        }
        kinds
    }
}

/// Starting the tray app at login, via an XDG autostart entry. (The XFCE panel plugin
/// doesn't need this: it starts with the panel.)
pub mod autostart {
    use super::*;

    fn path() -> Option<PathBuf> {
        xdg_dir("XDG_CONFIG_HOME", ".config")
            .map(|dir| dir.join("autostart").join("salatwidget.desktop"))
    }

    pub fn is_enabled() -> bool {
        path()
            .and_then(|p| fs::read_to_string(p).ok())
            .is_some_and(|entry| !entry.lines().any(|line| line.trim() == "Hidden=true"))
    }

    /// Creates the entry for the running executable, or removes it.
    pub fn set_enabled(enabled: bool) -> io::Result<()> {
        let path = path().ok_or_else(|| io::Error::other("no home directory"))?;
        if enabled {
            let exe = std::env::current_exe()?;
            if let Some(dir) = path.parent() {
                fs::create_dir_all(dir)?;
            }
            fs::write(&path, entry(&exe))
        } else {
            match fs::remove_file(&path) {
                Err(error) if error.kind() == io::ErrorKind::NotFound => Ok(()),
                other => other,
            }
        }
    }

    /// The desktop entry, with the executable quoted as the Desktop Entry spec requires.
    pub(crate) fn entry(exe: &Path) -> String {
        let quoted = exe
            .to_string_lossy()
            .replace('\\', "\\\\")
            .replace('"', "\\\"")
            .replace('`', "\\`")
            .replace('$', "\\$");
        format!(
            "[Desktop Entry]\nType=Application\nName=SalatWidget\nComment=Time left until the next prayer\n\
             Exec=\"{quoted}\"\nIcon=appointment-soon\nTerminal=false\nX-GNOME-Autostart-enabled=true\n"
        )
    }
}

/// A downloaded timetable: the mosque's raw configuration and when it was fetched.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Cached {
    pub slug: String,
    pub fetched_at: Timestamp,
    configuration_json: String,
}

impl Cached {
    /// Downloads the mosque's page from mawaqit.net (blocking).
    pub fn fetch(slug: &str) -> Result<Self, String> {
        let html = ureq::get(&mawaqit::page_url(slug))
            .header("User-Agent", USER_AGENT)
            .call()
            .map_err(|e| match e {
                ureq::Error::StatusCode(404) => "No mosque was found at that address.".to_owned(),
                ureq::Error::StatusCode(code) => {
                    format!("Mawaqit responded with an error ({code}).")
                }
                other => format!("Couldn't reach mawaqit.net: {other}"),
            })?
            .body_mut()
            .read_to_string()
            .map_err(|e| e.to_string())?;
        let configuration_json = mawaqit::extract_conf_data(&html)
            .map_err(|e| e.to_string())?
            .to_owned();
        // Validate now rather than when it's first shown.
        mawaqit::MosqueConfiguration::from_json(&configuration_json).map_err(|e| e.to_string())?;
        Ok(Self {
            slug: slug.to_owned(),
            fetched_at: Timestamp::now(),
            configuration_json,
        })
    }

    pub fn load(slug: &str) -> Option<Self> {
        let text = fs::read_to_string(cache_dir()?.join(format!("{slug}.json"))).ok()?;
        let value: serde_json::Value = serde_json::from_str(&text).ok()?;
        Some(Self {
            slug: slug.to_owned(),
            fetched_at: Timestamp::from_second(value.get("fetchedAt")?.as_i64()?).ok()?,
            configuration_json: value.get("configuration")?.as_str()?.to_owned(),
        })
    }

    pub fn save(&self) -> io::Result<()> {
        let dir = cache_dir().ok_or_else(|| io::Error::other("no home directory"))?;
        fs::create_dir_all(&dir)?;
        let json = serde_json::json!({
            "fetchedAt": self.fetched_at.as_second(),
            "configuration": self.configuration_json,
        });
        // Write atomically so a crash never leaves a half-written cache.
        let path = dir.join(format!("{}.json", self.slug));
        let partial = path.with_extension("json.partial");
        fs::write(&partial, json.to_string())?;
        fs::rename(partial, path)
    }

    pub fn timetable(&self) -> Option<MosqueTimetable> {
        MosqueTimetable::from_configuration_json(&self.configuration_json, self.fetched_at).ok()
    }

    /// Too old, or fetched on another day (Mawaqit's "today" times apply only then).
    pub fn is_stale(&self, now: Timestamp, timetable: &MosqueTimetable) -> bool {
        let tz = timetable.time_zone().clone();
        let age = now.as_second() - self.fetched_at.as_second();
        age > REFRESH_INTERVAL_SECONDS
            || self.fetched_at.to_zoned(tz.clone()).date() != now.to_zoned(tz).date()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn settings_round_trip() {
        let settings = Settings {
            mosque: Some("assunna-hannover".into()),
            notify_adhan: true,
            notify_iqama: false,
        };
        assert_eq!(Settings::parse(&settings.serialize()), settings);
        assert_eq!(Settings::parse(""), Settings::default());
    }

    #[test]
    fn settings_accept_links_and_ignore_junk() {
        let parsed = Settings::parse(
            "# comment\nmosque = https://mawaqit.net/de/assunna-hannover\nother=1\n",
        );
        assert_eq!(parsed.mosque.as_deref(), Some("assunna-hannover"));
        assert_eq!(Settings::parse("mosque=not a slug").mosque, None);
    }

    #[test]
    fn notification_settings() {
        let parsed = Settings::parse("notify-adhan=true\nnotify-iqama=false\n");
        assert!(parsed.notify_adhan && !parsed.notify_iqama);
        assert_eq!(
            parsed.notification_kinds(),
            vec![mawakit::PrayerEventKind::Adhan]
        );
        // Off unless switched on.
        assert!(Settings::parse("").notification_kinds().is_empty());
    }

    #[test]
    fn autostart_entry_quotes_the_executable() {
        let entry = autostart::entry(Path::new("/home/me/my apps/salat\"widget$"));
        assert!(entry.starts_with("[Desktop Entry]\nType=Application\n"));
        assert!(
            entry.contains("Exec=\"/home/me/my apps/salat\\\"widget\\$\"\n"),
            "{entry}"
        );
    }
}
