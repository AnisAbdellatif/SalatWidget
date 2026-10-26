//! SalatWidget for the desktop: shared by the tray app (`src/main.rs`) and the XFCE
//! panel plugin (`xfce-plugin/`).

pub mod font;
pub mod icon;
pub mod store;
pub mod view;

#[cfg(target_os = "linux")]
pub mod linux;
