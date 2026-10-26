# SalatWidget for Linux

The next prayer and a countdown in your panel, for your mosque, using the timetables mosques publish on
[mawaqit.net](https://mawaqit.net). Built in Rust on [MawaKit](../../../MawaKit), the shared prayer-time core.

It comes in two forms, sharing the same code:

| | XFCE panel plugin | Tray app |
| --- | --- | --- |
| In the panel | The countdown as real text: `Asr 1h 23m` | A badge icon with the time left (`23m`, `1:23`, `45s`): emerald before the adhan, amber before the iqama. Also a text label where the desktop shows one. |
| On click | Opens the popup | Opens a menu with the countdown and the day's times; "Open SalatWidget…" opens the popup |
| Desktops | XFCE (Xubuntu) | Any panel with AppIndicator / StatusNotifier support: XFCE, Ubuntu GNOME, KDE, MATE, Budgie, Cinnamon |

The **popup** shows a live countdown card, the day's adhan and iqama times (Jumu'a on Fridays, tomorrow's times
after Isha), and a page for choosing your mosque by pasting its Mawaqit link.

Where the tray label text appears:

| Desktop | Text next to the tray icon |
| --- | --- |
| Ubuntu GNOME (AppIndicator extension), MATE, Budgie | Yes |
| XFCE Status Tray (Xubuntu default), KDE Plasma | No: icon only, so on XFCE use the panel plugin |

## Requirements

Rust (`rustup`) and these packages (Debian and Ubuntu names):

```bash
sudo apt-get install build-essential pkg-config libgtk-3-dev libayatana-appindicator3-dev libxdo-dev \
    libxkbcommon-dev libxcb-render0-dev libxcb-shape0-dev libxcb-xfixes0-dev \
    libxfce4panel-2.0-dev libxfce4ui-2-dev      # the last two only for the XFCE plugin
```

MawaKit must be checked out next to this repository (`~/dev/MawaKit` beside `~/dev/SalatWidget`).

## Install

**XFCE panel plugin.** Installs into your home folder, so no `sudo` is needed:

```bash
cargo build --release -p salatwidget-xfce
install -Dm644 target/release/libsalatwidget_xfce.so \
    ~/.local/lib/$(gcc -dumpmachine)/xfce4/panel/plugins/libsalatwidget.so
install -Dm644 xfce-plugin/data/salatwidget.desktop ~/.local/share/xfce4/panel/plugins/salatwidget.desktop
xfce4-panel -r
```

Then add it through *Panel → Add New Items → SalatWidget*. The panel looks for the `.desktop` file under
`~/.local/share` and for the library under `~/.local/lib/<multiarch>`, e.g. `aarch64-linux-gnu`.

**Tray app:**

```bash
cargo build --release
target/release/salatwidget --mosque https://mawaqit.net/de/your-mosque
```

To start it at login, add it in *Session and Startup → Application Autostart*.

Settings and the cached timetable live in `~/.config/salatwidget/` and `~/.cache/salatwidget/`.

## Development on a VM

`scripts/vm.sh` develops against a Linux VM over SSH (e.g. Xubuntu in UTM) from your Mac. It syncs both repositories,
builds on the VM, and runs things in the VM's desktop session. It needs key-based SSH (`ssh-copy-id`) and expects the
VM at `SALATWIDGET_VM` (default `xubuntu@192.168.64.2`).

```bash
scripts/vm.sh run                                  # build and (re)start the tray app
APP_ARGS="--open-panel" scripts/vm.sh run          # …and open the popup (debug builds)
scripts/vm.sh plugin                               # build, install and (re)load the XFCE plugin
scripts/vm.sh shot /tmp/vm.png                     # screenshot of the VM screen
scripts/vm.sh ssh 'cargo test --workspace'         # any command, with the desktop environment set
```

## Layout

```
src/view.rs, icon.rs, font.rs   what is shown, as plain values; the badge icon with a built-in pixel font
src/store.rs                    settings and the timetable cache (XDG directories)
src/linux/                      the app logic shared by tray and plugin, the tray, the GTK popup
xfce-plugin/                    the panel plugin: a C shim for XFCE's registration macro, the rest in Rust
```

The tray and the plugin are both an `Indicator` driven by the same code in `src/linux/mod.rs`, which handles ticking,
loading and choosing the mosque. The plugin is a separate crate, so the tray app never links `libxfce4panel`.

## Performance

Updates happen only when the shown text changes, at most once a minute so the countdown stays right after
suspend. The popup ticks every second only while it's visible. Measured on Xubuntu:

| | CPU | Context switches/s |
| --- | --- | --- |
| Tray app, popup closed | 0.02% | 0.17 |
| Tray app, popup open | 0.13% | 7 |
| Panel plugin, popup closed | 0.00% | 0.03 (same as XFCE's own notification plugin) |
| Panel plugin, popup open | 0.15% | 11 |
