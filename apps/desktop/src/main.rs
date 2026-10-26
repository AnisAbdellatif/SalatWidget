//! SalatWidget for the desktop: the next prayer and a countdown in the system tray.
//!
//!   salatwidget                    start (in the tray)
//!   salatwidget --mosque <link>    select a mosque by Mawaqit link or slug, then start

mod font;
mod icon;
mod store;
mod view;

#[cfg(target_os = "linux")]
mod linux;

fn main() {
    let mut args = std::env::args().skip(1);
    let mut mosque = None;
    let mut open_panel = false;
    let mut close_panel_after: Option<u64> = None;
    while let Some(arg) = args.next() {
        match arg.as_str() {
            "--mosque" => mosque = args.next(),
            // Debug builds: open the popup at launch, for testing without clicking the tray.
            "--open-panel" if cfg!(debug_assertions) => open_panel = true,
            "--close-panel-after" if cfg!(debug_assertions) => {
                close_panel_after = args.next().and_then(|s| s.parse().ok());
            }
            "--version" => {
                println!("salatwidget {}", env!("CARGO_PKG_VERSION"));
                return;
            }
            other => {
                eprintln!(
                    "salatwidget: unknown argument {other:?}\nusage: salatwidget [--mosque <mawaqit link or slug>]"
                );
                std::process::exit(2);
            }
        }
    }

    #[cfg(target_os = "linux")]
    if let Err(error) = linux::run(mosque, open_panel, close_panel_after) {
        eprintln!("salatwidget: {error}");
        std::process::exit(1);
    }

    #[cfg(not(target_os = "linux"))]
    {
        let _ = (mosque, open_panel, close_panel_after);
        eprintln!(
            "salatwidget: only Linux is supported so far (macOS has its own app in apps/macos)"
        );
        std::process::exit(1);
    }
}
