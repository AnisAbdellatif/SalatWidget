# SalatWidget

Prayer-time widgets for the desktop: the next prayer and a countdown in the menu bar or tray, for your mosque.

| App | Folder | Status |
| --- | --- | --- |
| macOS menu bar | [`apps/macos`](apps/macos) | Working (SwiftUI) |
| Windows tray | `apps/desktop` | Planned: one Rust tray app for Windows and Linux |
| Linux tray / top bar | `apps/desktop` | Planned |

All apps use [MawaKit](../MawaKit), the shared prayer-time core written in Rust. It lives in its own repository so
other apps can use it too. MawaKit owns the behaviour, verified by its shared spec. The apps here own everything
platform-specific: UI, networking, storage, notifications, and launching at login.

```bash
make test       # tests for every app
make perf       # runtime performance check (macOS)
make hooks      # run tests before commits and the perf check before pushes
make run        # build and open the macOS app
```

Local setup: check out `MawaKit` next to this repository (`~/dev/MawaKit` and `~/dev/SalatWidget`) and install Rust
with `rustup`.

## License

[MIT](LICENSE). Prayer times are provided by MAWAQIT; this project isn't affiliated with MAWAQIT.
