#!/bin/bash
#
# Build Tardy.app from the Swift package and sign it.
#
# Usage:
#   scripts/build-app.sh            # debug: arm64, "Tardy Debug" (net.vpetkov.tardy.debug), no updates
#   scripts/build-app.sh --release  # universal, Developer ID, hardened runtime + timestamp
#
# Output: build/Tardy.app (release) or build/Tardy Debug.app (debug)

set -euo pipefail

readonly RELEASE_IDENTITY="${TARDY_SIGNING_IDENTITY:-Developer ID Application: Ventzislav Petkov (8J9W3ZG4ZN)}"

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo_root"

release=0
[[ "${1:-}" == "--release" ]] && release=1

say() { printf '\n==> %s\n' "$*"; }

if [[ $release -eq 1 ]]; then
    say "Building release (universal)"
    swift build -c release --arch arm64 --arch x86_64
    # The product path differs across toolchains (.build/apple vs .build/out); ask SwiftPM
    binary="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/Tardy"
    app="build/Tardy.app"
    identity="$RELEASE_IDENTITY"
    timestamp="--timestamp"
else
    say "Building debug"
    swift build
    binary="$(swift build --show-bin-path)/Tardy"
    app="build/Tardy Debug.app"
    # A stable development identity keeps the Calendar permission across rebuilds;
    # ad-hoc signatures change every build and macOS asks again each time.
    identities=$(security find-identity -v -p codesigning)
    identity=$(printf '%s\n' "$identities" | awk -F'"' '/Apple Development: / && !found {print $2; found = 1}')
    [[ -n "$identity" ]] || identity="-"
    timestamp="--timestamp=none"
fi

[[ -x "$binary" ]] || { echo "build produced no binary at $binary" >&2; exit 1; }
framework=".build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
[[ -d "$framework" ]] || { echo "Sparkle.framework not found at $framework (run: swift package resolve)" >&2; exit 1; }

say "Assembling $app"
command rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$app/Contents/Frameworks"
cp "$binary" "$app/Contents/MacOS/Tardy"
ditto "$framework" "$app/Contents/Frameworks/Sparkle.framework"
cp Resources/Info.plist "$app/Contents/Info.plist"
[[ -f Resources/AppIcon.icns ]] && cp Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"

plist="$app/Contents/Info.plist"
if [[ $release -eq 1 ]]; then
    key=$(/usr/libexec/PlistBuddy -c "Print :SUPublicEDKey" "$plist")
    [[ "$key" != __* ]] || { echo "SUPublicEDKey is still a placeholder in Resources/Info.plist" >&2; exit 1; }
else
    # Separate identity and no feed: a debug build never updates or shares a
    # Calendar permission with the installed release
    /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier net.vpetkov.tardy.debug" "$plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleName Tardy Debug" "$plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName Tardy Debug" "$plist"
    /usr/libexec/PlistBuddy -c "Delete :SUFeedURL" "$plist"
fi

say "Signing with: $identity"

# Output captured into variables, never piped into grep -q: under pipefail an
# early-exiting reader kills the writer with SIGPIPE and fails the check at random.
is_mach_o() {
    local description
    description=$(file "$1")
    [[ "$description" == *Mach-O* ]]
}

sign() { codesign --force --sign "$identity" -o runtime $timestamp "$@"; }

# Inside-out. Every nested Mach-O individually -- Sparkle's Autoupdate is a bare
# executable that --deep --strict ignores and notarization rejects.
while IFS= read -r f; do
    is_mach_o "$f" && sign "$f"
done < <(find "$app/Contents/Frameworks" -type f -perm +111)

while IFS= read -r p; do
    sign "$p"
done < <(find "$app/Contents/Frameworks" \( -name "*.xpc" -o -name "*.app" \) | sort -r)

for v in "$app/Contents/Frameworks/"*.framework/Versions/[A-Z]; do
    [[ -d "$v" ]] && sign "$v"
done

sign --entitlements Resources/Tardy.entitlements "$app"
codesign --verify --deep --strict "$app"

say "Built $app ($(lipo -archs "$app/Contents/MacOS/Tardy"))"
