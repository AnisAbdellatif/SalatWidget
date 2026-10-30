#!/usr/bin/env bash
# Builds two Debian packages into target/deb (run on Debian or Ubuntu, with the packages
# from README.md installed): salatwidget (the tray app) and salatwidget-xfce-plugin
# (the XFCE panel plugin, kept separate so GNOME and KDE don't pull in XFCE's libraries).
#   scripts/build-deb.sh              # version from Cargo.toml
#   VERSION=1.2.0 scripts/build-deb.sh
set -euo pipefail

cd "$(dirname "$0")/.."
version="${VERSION:-$(sed -n 's/^version = "\(.*\)"/\1/p' Cargo.toml | head -1)}"
arch="$(dpkg --print-architecture)"
multiarch="$(dpkg-architecture -qDEB_HOST_MULTIARCH)"
out="$PWD/target/deb"
rm -rf "$out"
mkdir -p "$out"

cargo build --release --locked -p salatwidget -p salatwidget-xfce

# pack <package> <staged tree> <description> <extra depends> <binary to scan for libraries>
pack() {
    local name="$1" root="$2" description="$3" extra="$4" binary="$5" shlibs
    # dpkg-shlibdeps wants a debian/control to exist; an empty one will do.
    mkdir -p "$out/scan/debian"
    : >"$out/scan/debian/control"
    shlibs="$(cd "$out/scan" && dpkg-shlibdeps -O -e"$root/$binary" 2>/dev/null | sed 's/^shlibs:Depends=//')"
    mkdir -p "$root/DEBIAN"
    cat >"$root/DEBIAN/control" <<CONTROL
Package: $name
Version: $version
Architecture: $arch
Maintainer: Anis Abdellatif <AnisAbdellatif@users.noreply.github.com>
Section: utils
Priority: optional
Homepage: https://github.com/AnisAbdellatif/SalatWidget
Depends: ${shlibs}${extra:+, $extra}
Description: $description
 Shows the next prayer and a countdown, from the timetable your mosque
 publishes on mawaqit.net.
CONTROL
    dpkg-deb --root-owner-group --build "$root" "$out/${name}_${version}_${arch}.deb" >/dev/null
}

app="$out/salatwidget"
install -Dm755 target/release/salatwidget "$app/usr/bin/salatwidget"
strip --strip-unneeded "$app/usr/bin/salatwidget"
# The AppIndicator library is loaded at run time, so shlibdeps can't see it.
pack salatwidget "$app" "Prayer times in your tray" "libayatana-appindicator3-1" usr/bin/salatwidget

plugin="$out/salatwidget-xfce-plugin"
lib="usr/lib/$multiarch/xfce4/panel/plugins/libsalatwidget.so"
install -Dm644 target/release/libsalatwidget_xfce.so "$plugin/$lib"
strip --strip-unneeded "$plugin/$lib"
install -Dm644 xfce-plugin/data/salatwidget.desktop "$plugin/usr/share/xfce4/panel/plugins/salatwidget.desktop"
pack salatwidget-xfce-plugin "$plugin" "Prayer times in the XFCE panel" "" "$lib"

rm -rf "$out/scan" "$app" "$plugin"
ls -1 "$out"
