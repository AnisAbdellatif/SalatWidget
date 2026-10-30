#!/usr/bin/env bash
# Sets one version for the macOS app and the Linux crates, ready to tag as v<version>.
#   scripts/bump-version.sh 1.2.0
set -euo pipefail

version="${1:?usage: scripts/bump-version.sh <version, e.g. 1.2.0>}"
cd "$(dirname "$0")/.."

plist=apps/macos/Support/Info.plist
build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$plist")"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $version" -c "Set :CFBundleVersion $((build + 1))" "$plist"

for manifest in apps/desktop/Cargo.toml apps/desktop/xfce-plugin/Cargo.toml; do
    sed -i '' "1,/^version = /s/^version = .*/version = \"$version\"/" "$manifest"
done
(cd apps/desktop && cargo update --workspace --quiet)

echo "Now at $version. Commit, then: git tag v$version && git push origin v$version"
