#!/usr/bin/env bash
# Packages build/SalatWidget.app (from `make app`) into build/SalatWidget-<version>.dmg,
# a drag-to-Applications disk image, and prints its SHA-256 for the Homebrew cask.
set -euo pipefail

cd "$(dirname "$0")/.."
APP="build/SalatWidget.app"
[[ -d "$APP" ]] || { echo "Missing $APP: run 'make app' first." >&2; exit 1; }

version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
dmg="build/SalatWidget-$version.dmg"

stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
cp -R "$APP" "$stage/"
ln -s /Applications "$stage/Applications"

rm -f "$dmg"
hdiutil create -quiet -volname "SalatWidget" -srcfolder "$stage" -format UDZO -ov "$dmg"

echo "Built $dmg"
shasum -a 256 "$dmg"
