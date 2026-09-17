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
#   - a logged-in gh, when origin is a GitHub repository  (gh auth login)
#   - a logged-in wrangler                       (npx wrangler@4.133.0 login)
#
# Every setting below can be overridden from the environment, so a fork can
# publish under its own identity, bucket and domain.

set -euo pipefail
trap 'echo "release.sh: line $LINENO failed (exit $?): $BASH_COMMAND" >&2' ERR

readonly IDENTITY="${TARDY_SIGNING_IDENTITY:-Developer ID Application: Ventzislav Petkov (8J9W3ZG4ZN)}"
readonly NOTARY_PROFILE="${TARDY_NOTARY_PROFILE:-moo-notary}"
readonly SPARKLE_ACCOUNT="${TARDY_SPARKLE_ACCOUNT:-tardy}"
readonly BUCKET="${TARDY_BUCKET:-tardy-mac-calendar-autoupdate}"
readonly FEED_HOST="${TARDY_FEED_HOST:-https://tardy.vpetkov.net}"
readonly TEAM_ID="${TARDY_TEAM_ID:-8J9W3ZG4ZN}"

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

# Pinned, with npm install scripts off: this runs on the machine that holds the
# signing identity, notary profile and Sparkle key, so a newly published (possibly
# hijacked) wrangler must never run here unreviewed. Bump the pin deliberately.
readonly WRANGLER_VERSION="${TARDY_WRANGLER_VERSION:-4.133.0}"
wrangler() {
    CI=1 WRANGLER_SEND_METRICS=false npm_config_ignore_scripts=true \
        npx --yes "wrangler@$WRANGLER_VERSION" "$@"
}
if [[ $dry_run -eq 0 ]]; then
    for tool in "$notarytool" "$stapler"; do
        [[ -x "$tool" ]] || { echo "not found: $tool" >&2; exit 1; }
    done
    "$notarytool" history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1 \
        || { echo "notarytool profile '$NOTARY_PROFILE' is missing or invalid" >&2; exit 1; }
    wrangler whoami >/dev/null 2>&1 \
        || { echo "wrangler is not logged in -- run: npx wrangler@$WRANGLER_VERSION login" >&2; exit 1; }
fi

# The GitHub release tags the commit the app is built from, so a real release
# needs a clean checkout whose HEAD is already on origin. A repository with no
# GitHub remote skips the GitHub release rather than failing.
build_commit=$(git rev-parse HEAD)
github_repo=""
if [[ $dry_run -eq 0 ]]; then
    tracked_changes=$(git status --porcelain --untracked-files=no)
    [[ -z "$tracked_changes" ]] \
        || { echo "uncommitted changes -- commit or stash them so the release matches its tag" >&2; exit 1; }
    # SwiftPM compiles every file under Sources/, tracked or not
    untracked_inputs=$(git status --porcelain --untracked-files=all -- Sources Resources Package.swift Package.resolved)
    [[ -z "$untracked_inputs" ]] \
        || { echo "untracked build inputs would ship without being in the tag:" >&2; echo "$untracked_inputs" >&2; exit 1; }
    origin_url=$(git remote get-url origin 2>/dev/null || true)
    if [[ "$origin_url" == *github.com* ]]; then
        gh auth status >/dev/null 2>&1 \
            || { echo "gh is not logged in -- run: gh auth login" >&2; exit 1; }
        github_repo=$(gh repo view "$origin_url" --json nameWithOwner --jq .nameWithOwner)
        git fetch --quiet origin
        pushed=$(git branch -r --contains "$build_commit")
        [[ -n "$pushed" ]] \
            || { echo "$build_commit is not on origin -- push it before releasing" >&2; exit 1; }
    fi
fi

# --- Version checks ----------------------------------------------------------
# Against the local master feed, before spending a build: a version that isn't
# new would overwrite a published DMG (whose signature the feed records) or ship
# a build Sparkle never offers.

plist_version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist)
plist_build=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" Resources/Info.plist)
[[ "$plist_build" =~ ^[0-9]+$ ]] || { echo "CFBundleVersion must be an integer, got '$plist_build'" >&2; exit 1; }

master_feed="$release_dir/appcast.xml"
if [[ -f "$master_feed" ]]; then
    newest_build=$(sed -n 's:.*<sparkle\:version>\([0-9][0-9]*\)</sparkle\:version>.*:\1:p' "$master_feed" | sort -n | tail -1)
    if [[ -n "$newest_build" && "$plist_build" -le "$newest_build" ]]; then
        echo "CFBundleVersion $plist_build is not above the newest published build $newest_build -- bump it" >&2
        exit 1
    fi
    if grep -q "<sparkle:shortVersionString>$plist_version</sparkle:shortVersionString>" "$master_feed"; then
        echo "version $plist_version is already in the feed -- bump CFBundleShortVersionString" >&2
        exit 1
    fi
fi

if [[ $dry_run -eq 0 ]]; then
    # The published feed must be the one this machine last wrote. Anything else
    # means the bucket was changed elsewhere, and generate_appcast would carry
    # (and, with a signed feed, sign) whatever is in it.
    if [[ -f "$master_feed" ]]; then
        live_feed=$(mktemp "${TMPDIR:-/tmp}/tardy-live-appcast.XXXXXX")
        curl -fsS "$FEED_HOST/appcast.xml" -o "$live_feed" \
            || { command rm -f "$live_feed"; echo "could not fetch $FEED_HOST/appcast.xml" >&2; exit 1; }
        if ! cmp -s "$live_feed" "$master_feed"; then
            command rm -f "$live_feed"
            echo "the live appcast differs from $master_feed -- find out why before releasing" >&2
            exit 1
        fi
        command rm -f "$live_feed"
    fi
    if curl -fsI "$FEED_HOST/Tardy-$plist_version.dmg" >/dev/null 2>&1; then
        echo "Tardy-$plist_version.dmg is already published -- bump the version" >&2
        exit 1
    fi
fi

# --- Build + sign ------------------------------------------------------------

swift test
TARDY_SIGNING_IDENTITY="$IDENTITY" scripts/build-app.sh --release
app="build/Tardy.app"

version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$app/Contents/Info.plist")
build_number=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$app/Contents/Info.plist")

# Checked before notarizing, not after publishing: a version already released
# on GitHub means CFBundleShortVersionString was not bumped.
if [[ -n "$github_repo" ]]; then
    existing=$(git ls-remote --tags origin "refs/tags/v$version")
    [[ -z "$existing" ]] \
        || { echo "v$version is already tagged on origin -- bump the version" >&2; exit 1; }
fi
say "Version $version (build $build_number), architectures: $(lipo -archs "$app/Contents/MacOS/Tardy")"

say "Auditing signatures"
unsigned=""
while IFS= read -r f; do
    description=$(file "$f")
    [[ "$description" == *Mach-O* ]] || continue
    signature=$(codesign -dvv "$f" 2>&1 || true)
    [[ "$signature" == *"Authority=Developer ID Application"* && "$signature" == *"TeamIdentifier=$TEAM_ID"* ]] \
        || unsigned+="$f"$'\n'
done < <(find "$app" -type f -perm +111)
[[ -z "$unsigned" ]] || { echo "not Developer ID signed by team $TEAM_ID:" >&2; printf '%s' "$unsigned" >&2; exit 1; }

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
# Built on the local master feed (checked against the live one in preflight) so
# earlier releases keep their entries.

say "Generating appcast"
"$sparkle_bin/generate_appcast" \
    --account "$SPARKLE_ACCOUNT" \
    --download-url-prefix "$FEED_HOST/" \
    --maximum-versions 5 \
    "$release_dir"

# The app sets SURequireSignedFeed, so an unsigned feed would strand every copy
# of this build: it could never see another update.
grep -q "sparkle-signatures:" "$master_feed" \
    || { echo "generate_appcast did not sign $master_feed -- not publishing" >&2; exit 1; }

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
echo "  local:    $dmg"

# --- GitHub release ----------------------------------------------------------
# The same notarized disk image the feed serves, attached to a tag at the
# commit it was built from. Last, like the feed: one more place that
# advertises the build.

if [[ -z "$github_repo" ]]; then
    say "No GitHub remote -- skipping the GitHub release"
    exit 0
fi

tag="v$version"
say "Creating GitHub release $tag ($github_repo)"

checksum=$(shasum -a 256 "$dmg")
checksum=${checksum%% *}
# Outside release_dir: generate_appcast treats notes files there as its own.
# An explicit XXXXXX template: `mktemp -t prefix` is BSD-only, and GNU coreutils'
# mktemp (first on PATH with Homebrew) rejects it -- that failed the 1.0.0 release.
github_notes=$(mktemp "${TMPDIR:-/tmp}/tardy-github-notes.XXXXXX")
{
    if [[ -n "$notes_file" ]]; then
        cat "$notes_file"
        printf '\n'
    fi
    cat <<NOTES
## Install

Download **$(basename "$dmg")** below, open it, and drag Tardy to Applications.
It is signed with a Developer ID and notarized by Apple, and it updates itself
from then on. Tardy watches the calendars in the Mac Calendar app, so add your
accounts there first.

## Verify

\`\`\`
spctl --assess --type open --context context:primary-signature -vv $(basename "$dmg")
shasum -a 256 $(basename "$dmg")
# $checksum
\`\`\`
NOTES
} > "$github_notes"

gh release create "$tag" "$dmg" \
    --repo "$github_repo" \
    --target "$build_commit" \
    --title "Tardy $version" \
    --notes-file "$github_notes" \
    --latest

echo "  github:   https://github.com/$github_repo/releases/tag/$tag"
