#!/usr/bin/env bash
# Builds a universal (Apple silicon + Intel) SalatWidget.app into ./build using
# SwiftPM, no Xcode project required. Run `make app` so MawaKit is built first.
#   scripts/build-app.sh            # release build
#   CONFIG=debug scripts/build-app.sh
#   ARCHS="arm64" scripts/build-app.sh   # one architecture only (faster)
set -euo pipefail

cd "$(dirname "$0")/.."
fallback_sdk="$(scripts/toolchain.sh)"
[[ -n "$fallback_sdk" ]] && export SDKROOT="$fallback_sdk"
CONFIG="${CONFIG:-release}"
APP="build/SalatWidget.app"

read -r -a ARCHS <<<"${ARCHS:-arm64 x86_64}"

binaries=()
for arch in "${ARCHS[@]}"; do
    # A scratch folder per architecture: they would otherwise share one output folder.
    options=(-c "$CONFIG" --triple "$arch-apple-macosx14.0" --scratch-path ".build/$arch")
    swift build "${options[@]}"
    binaries+=("$(swift build "${options[@]}" --show-bin-path)/SalatWidget")
done

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
lipo -create "${binaries[@]}" -output "$APP/Contents/MacOS/SalatWidget"
cp Support/Info.plist "$APP/Contents/Info.plist"
[[ -f Support/AppIcon.icns ]] && cp Support/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Ad-hoc signature so Gatekeeper, the Keychain and login items accept the bundle
# locally. Use a Developer ID identity (SIGN_IDENTITY=...) and notarize to distribute.
codesign --force --options runtime --timestamp=none --sign "${SIGN_IDENTITY:--}" "$APP"

echo "Built $APP ($(lipo -archs "$APP/Contents/MacOS/SalatWidget"))"
