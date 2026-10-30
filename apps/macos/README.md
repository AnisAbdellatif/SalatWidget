# SalatWidget for macOS

A native menu bar app showing the time left until the next prayer at your mosque, using
the timetables mosques publish on [mawaqit.net](https://mawaqit.net).

- **Menu bar:** next prayer and countdown (`Asr 1h 23m`). After the adhan it counts down to the **iqama** instead.
- **Panel:** a large live countdown with progress, the Gregorian and Hijri dates, and the day's adhan and iqama
  times. On Fridays Dhuhr becomes Jumu'a. After Isha it shows tomorrow's times.
- **Mosque selection:** paste a mosque's Mawaqit link (no account needed), or search by name with a free Mawaqit account.
- **Notifications (optional):** an alert at each adhan and/or iqama, switched on in Settings.
- **Offline:** the full-year timetable is cached, so times keep working without a network connection.
- **Energy:** idles at 0% CPU. The menu bar only wakes when its text changes.

Requires macOS 14 or later. The build is universal (Apple silicon + Intel).

## Install
```sh
brew install --cask AnisAbdellatif/tap/salatwidget
```
Or download `SalatWidget-<version>.dmg` from the [releases](https://github.com/AnisAbdellatif/SalatWidget/releases)
and drag the app to Applications. The app is ad-hoc signed, not notarized, so the cask clears the quarantine flag for
you. After a manual download, right-click the app and choose Open the first time.

## Build and run

The prayer-time logic comes from [MawaKit](../../MawaKit), the shared Rust core. It's a git submodule at the
repository root (`git clone --recurse-submodules`, or `git submodule update --init`), or point `MAWAKIT_PATH` at
another checkout. You also
need Rust (`rustup`). Every `make` target rebuilds MawaKit's Swift artifacts first.

```bash
make run        # build build/SalatWidget.app (universal) and open it
make dmg        # build/SalatWidget-<version>.dmg and its SHA-256, for a release
make install    # copy it to /Applications and open it (needed for "Open at login")
make test       # unit tests, including performance budgets
make perf       # runtime performance check (≈1 min)
```

**Command Line Tools only (no Xcode):** from the macOS 27 SDK on, SwiftUI needs a compiler plugin that ships only
with Xcode. `scripts/toolchain.sh` then picks the newest older SDK automatically, and the Makefile passes the
swift-testing paths. With Xcode installed, neither workaround is used.

## Project layout

```
Sources/SalatCore/      Swift layer over MawaKit: Apple networking (URLSession), the cached
                        timetable model, Hijri dates, SF Symbols, and the app's existing API
Sources/SalatWidget/    SwiftUI app: MenuBarExtra, panel pages, Keychain, cache, notifications
Tests/SalatCoreTests/   End-to-end tests through the Rust core, plus performance budgets
Support/                Info.plist (LSUIElement) and app icon
scripts/                build-app.sh (universal bundle + signing), perf-check.sh, toolchain.sh
```

## Where the data comes from

| What | Source | Account? |
| --- | --- | --- |
| Prayer and iqama times | The public mosque page (`mawaqit.net/en/<slug>`), which embeds the mosque's full configuration (`confData`) | No |
| Mosque search | `GET /api/2.0/mosque/search`, with the `Api-Access-Token` from `GET /api/2.0/me` | Yes, free |

The password goes to Mawaqit only once; the app keeps only the returned token, in the login Keychain.

## Performance checks

Two layers guard against regressions. Both run from the monorepo's git hooks (`make hooks` at the root): tests before
commits that touch the app, the runtime check before pushes.

- **`make test`** includes `PerformanceTests`. A full-day simulation gives deterministic limits: ≤ 2,000 menu bar
  wakeups with a countdown (1,971 today, none wasted), ≤ 105 without one, and ≤ 11 timetable redraws. There are also
  generous time limits on the hot calls into the Rust core.
- **`make perf`** launches the app with isolated state and measures its own CPU time, idle wakeups and view redraws
  with the panel closed, open and closed again:

  | Phase | CPU | Wakeups/s | Countdown redraws/s |
  | --- | --- | --- | --- |
  | Closed | ≤ 0.5% | ≤ 1 | ≤ 0.1 |
  | Open | ≤ 2% | ≤ 6 | 0.5 to 1.5 |
  | Closed again | ≤ 0.5% | ≤ 1 | ≤ 0.1 |

  Since macOS 27 the menu bar item can't be opened programmatically, so the open phase shows the same panel in a
  stand-in window. It still catches the per-frame digit animation (26% CPU) and a timer left running after closing.

Debug builds include tools for reviewing the app without clicking through it:

```bash
swift run SalatWidget --snapshot /tmp/snapshots       # render panel pages to PNG (light + dark)
swift run SalatWidget --perf-report /tmp/perf.json    # what `make perf` runs
```

## Distribution

`scripts/build-app.sh` signs the app ad hoc, which works on this Mac. To share the app, sign it with a Developer ID
(`SIGN_IDENTITY="Developer ID Application: …" make app`) and notarize it with `xcrun notarytool`.

Prayer times are provided by MAWAQIT. This project isn't affiliated with MAWAQIT.

## Releasing
1. Bump `CFBundleShortVersionString` (and `CFBundleVersion`) in `Support/Info.plist`.
2. `make dmg`, then upload `build/SalatWidget-<version>.dmg` to a GitHub release tagged `v<version>`.
3. Set `version` and `sha256` in `Casks/salatwidget.rb` of [AnisAbdellatif/homebrew-tap](https://github.com/AnisAbdellatif/homebrew-tap).
   Hash the uploaded file: a rebuilt DMG has a different hash.
