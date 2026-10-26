#!/usr/bin/env bash
# Prints the SDK to build with, or nothing when the default SDK works.
#
# From the macOS 27 SDK on, SwiftUI's @State is a macro whose compiler plugin ships
# only with Xcode. With just the Command Line Tools installed, building against that
# SDK fails, so fall back to the newest older SDK that the Command Line Tools still
# include. Installing Xcode (or a fixed Command Line Tools) makes this a no-op.
#
#   export SDKROOT="$(scripts/toolchain.sh)"     # empty = keep the default
set -euo pipefail

clt=/Library/Developer/CommandLineTools
[[ "$(xcode-select -p 2>/dev/null)" == "$clt" ]] || exit 0

default_major=$(xcrun --show-sdk-version 2>/dev/null | cut -d. -f1)
[[ -n "$default_major" && "$default_major" -ge 27 ]] || exit 0

# Is the SwiftUI macro plugin available after all?
if find "$clt/usr/lib/swift/host/plugins" "$clt/usr/local/lib/swift/host/plugins" \
        -name '*SwiftUIMacros*' 2>/dev/null | grep -q .; then
    exit 0
fi

# Newest real (non-symlink) SDK older than 27, e.g. MacOSX26.5.sdk.
best=""
best_version=""
for sdk in "$clt"/SDKs/MacOSX[0-9]*.sdk; do
    [[ -L "$sdk" ]] && continue
    version=$(basename "$sdk" .sdk | sed 's/^MacOSX//')
    [[ "${version%%.*}" -lt 27 ]] || continue
    if [[ -z "$best_version" ]] || [[ "$(printf '%s\n%s\n' "$best_version" "$version" | sort -V | tail -1)" == "$version" ]]; then
        best="$sdk"
        best_version="$version"
    fi
done
echo "$best"
