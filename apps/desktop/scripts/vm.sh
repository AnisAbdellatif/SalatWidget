#!/usr/bin/env bash
# Develop and test the Linux app on a VM over SSH (e.g. Xubuntu in UTM).
#
#   scripts/vm.sh sync        copy MawaKit and SalatWidget to the VM (no build outputs)
#   scripts/vm.sh build       sync, then cargo build on the VM
#   scripts/vm.sh run         sync, build, and (re)start the app in the VM's desktop session
#   scripts/vm.sh stop        stop the app
#   scripts/vm.sh log         show the app's output
#   scripts/vm.sh shot [out]  screenshot of the VM screen, copied here (default: ./vm-shot.png)
#   scripts/vm.sh ssh <cmd>   run a command on the VM with the desktop environment set
#
# Configure with SALATWIDGET_VM (default xubuntu@192.168.64.2). The VM needs Rust (rustup)
# and the packages listed in apps/desktop/README.md. Set up key-based SSH first
# (ssh-copy-id), since this script never asks for passwords.
set -euo pipefail

VM="${SALATWIDGET_VM:-xubuntu@192.168.64.2}"
HERE="$(cd "$(dirname "$0")/.." && pwd)"           # apps/desktop
MONOREPO="$(cd "$HERE/../.." && pwd)"              # SalatWidget
MAWAKIT="${MAWAKIT_PATH:-$MONOREPO/../MawaKit}"
REMOTE_DIR='~/dev'
SSH=(ssh -o BatchMode=yes -o ConnectTimeout=8 "$VM")

# Run a command in the VM's graphical session: its X display and session D-Bus.
remote() {
    "${SSH[@]}" "export DISPLAY=:0 XAUTHORITY=\$HOME/.Xauthority DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/\$(id -u)/bus PATH=\$HOME/.cargo/bin:\$PATH; $*"
}

sync() {
    local excludes=(--exclude target/ --exclude .build/ --exclude build/ --exclude .git/ --exclude '*.xcframework' --exclude .DS_Store)
    "${SSH[@]}" "mkdir -p $REMOTE_DIR"
    rsync -az --delete "${excludes[@]}" "$MAWAKIT/" "$VM:$REMOTE_DIR/MawaKit/"
    rsync -az --delete "${excludes[@]}" "$MONOREPO/" "$VM:$REMOTE_DIR/SalatWidget/"
}

build() {
    sync
    remote "cd $REMOTE_DIR/SalatWidget/apps/desktop && cargo build --quiet ${CARGO_FLAGS:-}"
}

stop() {
    remote "pkill -x salatwidget || true"
}

case "${1:-}" in
    sync) sync ;;
    build) build ;;
    run)
        build
        stop
        # Fully detached (own session, no inherited output), or SSH would wait for it.
        remote "cd $REMOTE_DIR/SalatWidget/apps/desktop || exit 1; setsid nohup target/debug/salatwidget ${APP_ARGS:-} >\$HOME/salatwidget.log 2>&1 < /dev/null & sleep 2; cat \$HOME/salatwidget.log"
        ;;
    stop) stop ;;
    log) remote "cat \$HOME/salatwidget.log" ;;
    shot)
        out="${2:-$PWD/vm-shot.png}"
        remote "rm -f /tmp/salatwidget-shot.png; xfce4-screenshooter --fullscreen --save /tmp/salatwidget-shot.png >/dev/null 2>&1"
        scp -q -o BatchMode=yes "$VM:/tmp/salatwidget-shot.png" "$out"
        echo "$out"
        ;;
    ssh) shift; remote "$*" ;;
    *) sed -n '2,13p' "$0"; exit 2 ;;
esac
