//! Desktop notifications through the freedesktop notification service
//! (`org.freedesktop.Notifications` on the session bus), which XFCE, GNOME, KDE and
//! others implement. Uses GIO's D-Bus client, so no extra dependencies.

use std::collections::HashMap;
use std::fs::{File, OpenOptions};
use std::path::PathBuf;

use gtk::gio;
use gtk::glib::{ToVariant, Variant};

use crate::view::Notice;

/// Shows `notice` (fire and forget; failures are only logged).
pub fn send(notice: &Notice) {
    let connection = match gio::bus_get_sync(gio::BusType::Session, gio::Cancellable::NONE) {
        Ok(connection) => connection,
        Err(error) => {
            eprintln!("salatwidget: no session bus for notifications: {error}");
            return;
        }
    };

    let mut hints: HashMap<String, Variant> = HashMap::new();
    hints.insert("urgency".into(), 1u8.to_variant()); // normal
    hints.insert("desktop-entry".into(), "salatwidget".to_variant());
    hints.insert("sound-name".into(), "message-new-instant".to_variant());

    // Notify(app_name, replaces_id, app_icon, summary, body, actions, hints, expire_timeout)
    let parameters = (
        "SalatWidget",
        0u32,
        "appointment-soon",
        notice.summary.as_str(),
        notice.body.as_str(),
        Vec::<String>::new(),
        hints,
        -1i32,
    )
        .to_variant();

    connection.call(
        Some("org.freedesktop.Notifications"),
        "/org/freedesktop/Notifications",
        "org.freedesktop.Notifications",
        "Notify",
        Some(&parameters),
        None,
        gio::DBusCallFlags::NONE,
        5_000,
        gio::Cancellable::NONE,
        |result| {
            if let Err(error) = result {
                eprintln!("salatwidget: notification failed: {error}");
            }
        },
    );
}

/// Makes this process the one that sends notifications, if no other SalatWidget (tray
/// app or panel plugin) already is, so running both doesn't notify twice. Returns the
/// held lock; it is released when the process exits.
pub fn claim_sender() -> Option<File> {
    let dir = std::env::var_os("XDG_RUNTIME_DIR")
        .map(PathBuf::from)
        .or_else(|| std::env::var_os("HOME").map(|home| PathBuf::from(home).join(".cache")))?;
    let file = OpenOptions::new()
        .create(true)
        .truncate(false)
        .write(true)
        .open(dir.join("salatwidget-notifications.lock"))
        .ok()?;
    file.try_lock().ok().map(|()| file)
}
