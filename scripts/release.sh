#!/bin/bash
#
# Cut a Tardy release: build, sign, package, notarize, staple, and publish the
# Sparkle appcast so installed copies update themselves.
#
# Usage:
#   scripts/release.sh                    # version from Resources/Info.plist
#   scripts/release.sh --notes notes.md   # release notes shown in the updater
#   scripts/release.sh --dry-run          # build and package, notarize/publish nothing
#
# Bump CFBundleVersion in Resources/Info.plist for every release: Sparkle orders
# releases by it, not by CFBundleShortVersionString.
#
# Requires, one time each (see docs/DEVELOPING.md):
#   - a Developer ID Application certificate in the login keychain
#   - a notarytool keychain profile              (xcrun notarytool store-credentials)
#   - the Sparkle EdDSA key for account "tardy"  (generate_keys --account tardy)
#   - a logged-in wrangler                       (npx wrangler@latest login)
#
# Every setting below can be overridden from the environment, so a fork can
# publish under its own identity, bucket and domain.

set -euo pipefail

readonly IDENTITY="${TARDY_SIGNING_IDENTITY:-Developer ID Application: Ventzislav Petkov (8J9W3ZG4ZN)}"
readonly NOTARY_PROFILE="${TARDY_NOTARY_PROFILE:-moo-notary}"
readonly SPARKLE_ACCOUNT="${TARDY_SPARKLE_ACCOUNT:-tardy}"
readonly BUCKET="${TARDY_BUCKET:-tardy-mac-calendar-autoupdate}"
readonly FEED_HOST="${TARDY_FEED_HOST:-https://tardy.vpetkov.net}"

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo_root"

# Past archives live outside the repo: generate_appcast needs the previous
# releases on hand to keep their entries in the feed.
release_dir="${TARDY_RELEASE_DIR:-$HOME/tardy-releases}"
notes_file=""
dry_run=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --notes) notes_file="$2"; shift 2 ;;
        --dry-run) dry_run=1; shift ;;
        -h|--help) sed -n '2,24p' "${BASH_SOURCE[0]}"; exit 0 ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
done

say() { printf '\n==> %s\n' "$*"; }

# --- Preflight ---------------------------------------------------------------

say "Checking prerequisites"

identities=$(security find-identity -v -p codesigning)
[[ "$identities" == *"$IDENTITY"* ]] \
    || { echo "missing signing identity: $IDENTITY" >&2; exit 1; }

# notarytool and stapler by their real paths: xcrun refuses to run anything
# until the Xcode license is accepted, which an Xcode upgrade silently resets.
developer_dir=$(xcode-select -p)
notarytool="$developer_dir/usr/bin/notarytool"
stapler="$developer_dir/usr/bin/stapler"

sparkle_bin=".build/artifacts/sparkle/Sparkle/bin"
[[ -x "$sparkle_bin/generate_appcast" ]] || swift package resolve
[[ -x "$sparkle_bin/generate_appcast" ]] \
    || { echo "generate_appcast not found under $sparkle_bin" >&2; exit 1; }

wrangler() { CI=1 WRANGLER_SEND_METRICS=false npx --yes wrangler@latest "$@"; }
if [[ $dry_run -eq 0 ]]; then
    for tool in "$notarytool" "$stapler"; do
        [[ -x "$tool" ]] || { echo "not found: $tool" >&2; exit 1; }
    done
    "$notarytool" history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1 \
        || { echo "notarytool profile '$NOTARY_PROFILE' is missing or invalid" >&2; exit 1; }
    wrangler whoami >/dev/null 2>&1 \
        || { echo "wrangler is not logged in -- run: npx wrangler@latest login" >&2; exit 1; }
fi

# --- Build + sign ------------------------------------------------------------

swift test
TARDY_SIGNING_IDENTITY="$IDENTITY" scripts/build-app.sh --release
app="build/Tardy.app"

version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$app/Contents/Info.plist")
build_number=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$app/Contents/Info.plist")
say "Version $version (build $build_number), architectures: $(lipo -archs "$app/Contents/MacOS/Tardy")"

say "Auditing signatures"
unsigned=""
while IFS= read -r f; do
    description=$(file "$f")
    [[ "$description" == *Mach-O* ]] || continue
    signature=$(codesign -dvv "$f" 2>&1 || true)
    [[ "$signature" == *"Authority=Developer ID Application"* ]] || unsigned+="$f"$'\n'
done < <(find "$app" -type f -perm +111)
[[ -z "$unsigned" ]] || { echo "not Developer ID signed:" >&2; printf '%s' "$unsigned" >&2; exit 1; }

# Notarization rejects get-task-allow; Calendar access needs its entitlement
# under the hardened runtime or EventKit fails silently.
entitlements=$(codesign -d --entitlements - --xml "$app" 2>/dev/null || true)
[[ "$entitlements" != *get-task-allow* ]] || { echo "app carries get-task-allow" >&2; exit 1; }
[[ "$entitlements" == *personal-information.calendars* ]] \
    || { echo "app is missing the calendars entitlement" >&2; exit 1; }

# --- Package -----------------------------------------------------------------

mkdir -p "$release_dir"
dmg="$release_dir/Tardy-$version.dmg"

say "Building $dmg"
command rm -f "$dmg"
scripts/create-dmg.sh "$app" "$dmg" "Tardy"

if [[ -n "$notes_file" ]]; then
    # generate_appcast attaches notes whose filename matches the archive
    cp "$notes_file" "$release_dir/Tardy-$version.${notes_file##*.}"
fi

# The disk image needs its own signature. Notarization and stapling both
# succeed on an unsigned image; only spctl catches it, as "no usable signature".
say "Signing the disk image"
codesign --force --sign "$IDENTITY" --timestamp "$dmg"

if [[ $dry_run -eq 1 ]]; then
    say "Dry run -- skipping notarization and publish"
    echo "built: $dmg"
    exit 0
fi

# --- Notarize ----------------------------------------------------------------

say "Notarizing (a few minutes at Apple)"
"$notarytool" submit "$dmg" --keychain-profile "$NOTARY_PROFILE" --wait
"$stapler" staple "$dmg"

# The only check that reflects what a recipient sees
spctl --assess --type open --context context:primary-signature -vv "$dmg"

# --- Appcast -----------------------------------------------------------------
# Pull the published feed first so earlier releases keep their entries.

say "Generating appcast"
if curl -fsS "$FEED_HOST/appcast.xml" -o "$release_dir/appcast.xml.remote" 2>/dev/null; then
    mv "$release_dir/appcast.xml.remote" "$release_dir/appcast.xml"
else
    command rm -f "$release_dir/appcast.xml.remote"
fi

"$sparkle_bin/generate_appcast" \
    --account "$SPARKLE_ACCOUNT" \
    --download-url-prefix "$FEED_HOST/" \
    --maximum-versions 5 \
    "$release_dir"

# --- Publish -----------------------------------------------------------------

say "Publishing to R2 ($BUCKET)"

# The versioned name is what the appcast points at and must never be
# overwritten: Sparkle checks the signature recorded for that exact file.
wrangler r2 object put "$BUCKET/$(basename "$dmg")" \
    --file "$dmg" --content-type application/x-apple-diskimage --remote

# Tardy.dmg is a copy of the newest release for links that don't go stale
wrangler r2 object put "$BUCKET/Tardy.dmg" \
    --file "$dmg" --content-type application/x-apple-diskimage \
    --cache-control "max-age=300" --remote

# The feed goes last: nothing should advertise a build that isn't downloadable
wrangler r2 object put "$BUCKET/appcast.xml" \
    --file "$release_dir/appcast.xml" --content-type application/xml \
    --cache-control "max-age=300" --remote

say "Published"
echo "  share:    $FEED_HOST/Tardy.dmg   (always the newest release)"
echo "  download: $FEED_HOST/$(basename "$dmg")"
echo "  appcast:  $FEED_HOST/appcast.xml"
