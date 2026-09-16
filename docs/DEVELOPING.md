# Developing Tardy

## Table of Contents

- [Prerequisites](#prerequisites)
- [Build and run](#build-and-run)
- [Tests](#tests)
- [Signing and notarization](#signing-and-notarization)
- [In-app updates](#in-app-updates)
- [Cutting a release](#cutting-a-release)
- [The website](#the-website)
- [Troubleshooting](#troubleshooting)

## Prerequisites

- macOS 14+ and Xcode 16+ (Swift 6 toolchain). No Xcode project is needed; Tardy is a Swift package.
- For signed builds, an Apple Developer account.

## Build and run

```bash
swift test                       # core logic tests
scripts/build-app.sh             # build/Tardy Debug.app (arm64, dev-signed)
open "build/Tardy Debug.app"
```

The debug app uses a separate bundle ID (`net.vpetkov.tardy.debug`) and name, has no
update feed, and keeps its own Calendar permission and settings, so it can run next to an
installed release. It's signed with your first "Apple Development" identity when one exists:
an ad-hoc signature changes on every build and macOS would ask for Calendar access again
each time.

App icon: `scripts/make-icon.sh source.png` rebuilds `Resources/AppIcon.icns` and
`docs/images/tardy-icon.png` from a square PNG. `scripts/compose-icon.py` clips the artwork to
Apple's exact tile (824 px, radius 185, in a 1024 px canvas): macOS 26 shrinks any icon that
doesn't match that shape onto a gray plate.

Verbose logging (tick scheduling):

```bash
open --env TARDY_DEBUG=1 --stderr /tmp/tardy.err "build/Tardy Debug.app"
```

## Tests

`Sources/TardyCore` holds everything that doesn't need AppKit: alert thresholds, primary
meeting selection, tick scheduling, formatting and meeting-link parsing. `swift test` runs
the suites in `Tests/TardyCoreTests` (Swift Testing). Menu, hotkey and status bar
behavior has to be checked by running the app.

## Signing and notarization

Three separate checks decide whether a downloaded app runs:

| Check | Question | Fails as |
|---|---|---|
| Code signature | Is the bundle intact and signed? | "damaged and can't be opened" |
| Notarization | Has Apple scanned this build? | "Apple cannot check it for malicious software" |
| Entitlements | May the hardened runtime use the calendar? | EventKit silently returns nothing |

`scripts/build-app.sh --release` builds a universal binary, assembles the bundle and
signs **inside-out**: every nested Mach-O in `Sparkle.framework` individually (its
`Autoupdate` is a bare executable that `--deep --strict` verification skips and
notarization rejects), then the XPC services and `Updater.app`, then the framework, then
the app with `Resources/Tardy.entitlements`. All with `-o runtime --timestamp`.

One-time setup:

```bash
# Developer ID Application certificate: create in the Apple Developer portal, install in the login keychain
security find-identity -v -p codesigning

# Notary credentials stored in the keychain
xcrun notarytool store-credentials "<profile-name>" --apple-id "<apple-id>" --team-id "<team-id>"
```

## In-app updates

Tardy updates itself with [Sparkle](https://sparkle-project.org).

| Piece | Where it lives | Public? |
|---|---|---|
| `SUFeedURL` | `Resources/Info.plist` → `https://tardy.vpetkov.net/appcast.xml` | yes |
| `SUPublicEDKey` | `Resources/Info.plist` | yes, the public half |
| EdDSA **private** key | login keychain, Sparkle account `tardy` | **never** |
| `appcast.xml`, DMGs, website | Cloudflare R2 bucket `tardy-mac-calendar-autoupdate`, custom domain `tardy.vpetkov.net` | yes |
| Past release archives | `~/tardy-releases` (`TARDY_RELEASE_DIR`) | local |

- **Guard the private key.** Every installed copy trusts the public key baked into it; lose the
  private key and those copies can never update again. Back it up once into a password manager:
  `.build/artifacts/sparkle/Sparkle/bin/generate_keys --account tardy -x tardy-sparkle-key.txt`,
  then delete the file.
- **Bump `CFBundleVersion` every release.** Sparkle orders releases by it, not by
  `CFBundleShortVersionString`.
- **Debug builds never check** (no `SUFeedURL`, `.debug` bundle ID).

## Cutting a release

1. Bump `CFBundleShortVersionString` and `CFBundleVersion` in `Resources/Info.plist`.
2. Run:

```bash
scripts/release.sh --dry-run            # build, sign, audit, DMG -- publishes nothing
scripts/release.sh --notes notes.md     # notarize, staple, appcast, publish
```

The release script tests, builds, audits every signature and the entitlements, builds and
signs the DMG, notarizes and staples it, checks it with `spctl`, regenerates the appcast
from the published feed plus local archives, and uploads the versioned DMG, `Tardy.dmg`
(always the newest) and finally `appcast.xml`. The feed goes last so nothing is advertised
before it can be downloaded.

A fork can publish under its own identity by setting `TARDY_SIGNING_IDENTITY`,
`TARDY_NOTARY_PROFILE`, `TARDY_SPARKLE_ACCOUNT`, `TARDY_BUCKET` and `TARDY_FEED_HOST`
(and changing `SUFeedURL`/`SUPublicEDKey`).

## The website

`site/index.html` is the landing page at `https://tardy.vpetkov.net`, served from the same
R2 bucket. `scripts/publish-site.sh` uploads it; it is deliberately separate from releases.
An R2 custom domain has no index document, so a Cloudflare rewrite rule on the zone maps `/`
to `/index.html`.

## Troubleshooting

- **"You have not agreed to the Xcode license agreements"** after an Xcode upgrade: run
  `sudo xcodebuild -license accept` in a terminal. The release script calls `notarytool`
  and `stapler` by path, but `swift build` still needs the license.
- **Notarization "Invalid":** `xcrun notarytool log <submission-id> --keychain-profile <profile>`
  names the offending binary; usually something nested wasn't signed.
- **`spctl` says "no usable signature"** on the DMG: the image itself wasn't signed (the app
  inside can be fine).
- **No events after installing:** check System Settings > Privacy & Security > Calendars, and
  that the calendars exist in the Mac Calendar app.
- **Release product path:** SwiftPM's universal build output moved between toolchains
  (`.build/apple` vs `.build/out`); the scripts ask `swift build --show-bin-path`.
