//! SalatWidget for the desktop: the next prayer and a countdown in the system tray.
//!
//!   salatwidget                    start (in the tray)
//!   salatwidget --mosque <link>    select a mosque by Mawaqit link or slug, then start
//!   salatwidget --search <name>    list matching mosques (needs MAWAQIT_API_TOKEN), then exit

#[cfg(target_os = "linux")]
use salatwidget::linux;

fn main() {
    let mut args = std::env::args().skip(1);
    let mut mosque = None;
    let mut open_panel = false;
    let mut close_panel_after: Option<u64> = None;
    let mut notify_test = false;
    while let Some(arg) = args.next() {
        match arg.as_str() {
            "--mosque" => mosque = args.next(),
            "--search" => return search(args.next().unwrap_or_default()),
            // Debug builds: open the popup at launch, for testing without clicking the tray.
            "--open-panel" if cfg!(debug_assertions) => open_panel = true,
            // Debug builds: send the next prayer's notification right away.
            "--notify-test" if cfg!(debug_assertions) => notify_test = true,
            "--close-panel-after" if cfg!(debug_assertions) => {
                close_panel_after = args.next().and_then(|s| s.parse().ok());
            }
            "--version" => {
                println!("salatwidget {}", env!("CARGO_PKG_VERSION"));
                return;
            }
            other => {
                eprintln!(
                    "salatwidget: unknown argument {other:?}\nusage: salatwidget [--mosque <mawaqit link or slug>] [--search <name>]"
                );
                std::process::exit(2);
            }
        }
    }

    #[cfg(target_os = "linux")]
    if let Err(error) = linux::run(mosque, open_panel, close_panel_after, notify_test) {
        eprintln!("salatwidget: {error}");
        std::process::exit(1);
    }

    #[cfg(not(target_os = "linux"))]
    {
        let _ = (mosque, open_panel, close_panel_after, notify_test);
        eprintln!(
            "salatwidget: only Linux is supported so far (macOS has its own app in apps/macos)"
        );
        std::process::exit(1);
    }
}

/// Prints the mosques matching `word`, one per line: `<slug>  <name>  <place>`.
fn search(word: String) {
    let Ok(token) = std::env::var("MAWAQIT_API_TOKEN") else {
        eprintln!("salatwidget: set MAWAQIT_API_TOKEN to your Mawaqit API access token");
        std::process::exit(2);
    };
    match salatwidget::store::search_mosques(&word, &token) {
        Ok(results) => {
            for r in results {
                println!("{}  {}  {}", r.slug, r.label, r.place);
            }
        }
        Err(error) => {
            eprintln!("salatwidget: {error}");
            std::process::exit(1);
        }
    }
}
