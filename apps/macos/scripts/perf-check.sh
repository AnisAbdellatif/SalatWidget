#!/usr/bin/env bash
# Runtime performance check.
#
# Launches a debug build with isolated state, lets it measure its own CPU time and
# idle wakeups with the panel closed, open and closed again (see DebugTools), and
# fails if any phase goes over budget. Needs a logged-in macOS session (the panel is
# a real window) and network access (to load a timetable).
#
#   scripts/perf-check.sh                 # 15 s per phase, about a minute in total
#   PERF_SECONDS=30 scripts/perf-check.sh
#
# Don't click the app's menu bar item while this runs. It would change the scenario,
# and the check reports that as an invalid run rather than a regression.
set -euo pipefail
cd "$(dirname "$0")/.."
fallback_sdk="$(scripts/toolchain.sh)"
[[ -n "$fallback_sdk" ]] && export SDKROOT="$fallback_sdk"
export LC_ALL=C  # printf/awk number formats must not follow the user's locale

PHASE_SECONDS="${PERF_SECONDS:-15}"
REPORT="$(mktemp -t salatwidget-perf)"

# Budgets per phase: max CPU %, max idle wakeups/s, expected panel state, and the
# allowed range of countdown redraws per second.
# Typical values on an Apple-silicon Mac: closed ~0.05% / ~0.2, open ~0.4% / 1–2.
# The margins absorb noise but catch regressions such as a timer left running
# after the panel closes (~1–2 wakeups/s) or a per-frame animation (~20% CPU).
# The redraw range proves the countdown really ticks once a second while open,
# neither frozen nor redrawn every frame, and stops when closed.
BUDGETS=(
    "closed      0.5  1.0  false  0    0.1"
    "open        2.0  6.0  true   0.5  1.5"
    "closedAgain 0.5  1.0  false  0    0.1"
)
# The timetable redraws only at prayer boundaries: at most one per phase, or two
# if a phase happens to span one.
MAX_TIMETABLE_RENDERS=2

swift build >/dev/null
BINARY="$(swift build --show-bin-path)/SalatWidget"

"$BINARY" --perf-report "$REPORT" --perf-seconds "$PHASE_SECONDS" >/dev/null &
APP_PID=$!
# Watchdog in case the app hangs: the scenario takes 6 s + 3 phases + 2 × 2 s settling.
( sleep $((PHASE_SECONDS * 3 + 40)) && kill "$APP_PID" 2>/dev/null ) &
WATCHDOG_PID=$!
if ! wait "$APP_PID"; then
    echo "✘ The perf run didn't finish (crash, timeout or no timetable)." >&2
    exit 1
fi
kill "$WATCHDOG_PID" 2>/dev/null || true
wait "$WATCHDOG_PID" 2>/dev/null || true

value() { plutil -extract "$1.$2" raw -o - "$REPORT"; }
within() { awk -v value="$1" -v limit="$2" 'BEGIN { exit !(value <= limit) }'; }

failed=0
invalid=0
printf "  %-12s %8s %8s %11s %8s %13s %11s %10s\n" \
    "phase" "cpu %" "budget" "wakeups/s" "budget" "countdown/s" "range" "timetable"
for budget in "${BUDGETS[@]}"; do
    read -r phase max_cpu max_wakeups expected_visible min_ticks max_ticks <<<"$budget"
    cpu=$(value "$phase" cpuPercent)
    wakeups=$(value "$phase" wakeupsPerSecond)
    visible=$(value "$phase" panelVisible)
    ticks=$(value "$phase" countdownRendersPerSecond)
    tables=$(value "$phase" timetableRenders)

    mark="✔"
    if [[ "$visible" != "$expected_visible" ]]; then
        mark="?"
        invalid=1
    elif ! within "$cpu" "$max_cpu" || ! within "$wakeups" "$max_wakeups" \
        || ! within "$min_ticks" "$ticks" || ! within "$ticks" "$max_ticks" \
        || ! within "$tables" "$MAX_TIMETABLE_RENDERS"; then
        mark="✘"
        failed=1
    fi
    printf "%s %-12s %8.2f %8s %11.2f %8s %13.2f %11s %10s\n" "$mark" "$phase" \
        "$cpu" "≤ $max_cpu" "$wakeups" "≤ $max_wakeups" "$ticks" "$min_ticks–$max_ticks" "$tables ≤ $MAX_TIMETABLE_RENDERS"
done

if [[ "$(plutil -extract open.panelSource raw -o - "$REPORT" 2>/dev/null)" == "standIn" ]]; then
    echo "ℹ︎ The open phase used a stand-in window showing the same panel: since macOS 27 the" \
         "menu bar item can't be opened programmatically."
fi

if (( invalid )); then
    echo "? Invalid run: the panel wasn't in the expected state. Was the menu bar item clicked during the run? Try again." >&2
    exit 2
fi
if (( failed )); then
    echo "✘ Runtime performance is over budget (report: $REPORT)." >&2
    exit 1
fi
echo "✔ Runtime performance within budget."
rm -f "$REPORT"
