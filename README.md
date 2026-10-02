<div align="center">

<img src="docs/images/tardy-icon.png" alt="Tardy logo: a calendar page headed LATE with a ringing red alarm clock" width="160">

<h1>Tardy</h1>

<p>
A macOS menu bar app that makes meetings impossible to miss. Tardy watches the calendars in the
Mac Calendar app and escalates as a meeting gets closer, from a quiet dot to a flashing
<b>LATE</b> counter, with one-click join for Zoom, Teams, Google Meet and more.
</p>

<a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="License: MIT"></a>
<img src="https://img.shields.io/badge/macOS-14%2B-lightgrey.svg" alt="macOS 14+">
<img src="https://img.shields.io/badge/Swift-6-orange.svg" alt="Swift 6">

</div>

## Table of Contents

- [Overview](#overview)
- [Quick Install](#quick-install)
- [Features](#features)
- [Supported Meeting Providers](#supported-meeting-providers)
- [Usage](#usage)
- [Documentation](#documentation)
- [Contributing](#contributing)
- [License](#license)

## Overview

Calendar alerts on macOS, iOS and Apple Watch all look and sound the same, and
they are easy to swipe away. A meeting 15 minutes out gets the same treatment as
one starting in 30 seconds.

Tardy escalates instead. The menu bar shows today's date and a dot for your next
meeting, adds the time as it approaches, sounds an alert at 10, 5 and 2 minutes with one
more sound each time (you pick the times and counts), runs a live countdown, and flashes
a LATE counter once the meeting has started until you join or dismiss it.

> [!IMPORTANT]
> **Tardy works with the native Mac Calendar app.** It reads events through
> macOS's calendar store, so every calendar you want watched (iCloud, Google,
> Exchange/Microsoft 365, CalDAV, subscriptions) must be added to Calendar.app
> first: **Calendar > Settings > Accounts**. Calendars that only live in a web
> app or another calendar client are invisible to Tardy.

Everything runs locally. Tardy makes no network calls except checking
`tardy.vpetkov.net` for app updates.

## Quick Install

```bash
curl -fLO https://tardy.vpetkov.net/Tardy.dmg
open Tardy.dmg
# Drag Tardy to Applications, then launch it and allow Calendar access
```

Requires macOS 14 (Sonoma) or later. The app is signed and notarized by Apple
(`spctl -a -vv -t install Tardy.dmg` should name team `8J9W3ZG4ZN`), and
every version is also on the [Releases page](https://github.com/ventz/tardy/releases).
To build from source, see [docs/DEVELOPING.md](docs/DEVELOPING.md).

## Features

- **Escalating alerts:** up to 5 sound alerts with notifications (default 10, 5 and 2 minutes, playing 1, 2 and 3 sounds), a live countdown from 5 minutes, and a flashing LATE counter that auto-clears after 5 minutes
- **Live date icon:** today's weekday and date, plus a red (personal) or blue (work) dot for your next meeting
- **One-click join:** a large Join button when a meeting with a link is close, or click any meeting in the list
- **Meeting list:** Now / Starts in … / Later today, with each meeting's time and provider
- **Work and Personal calendars:** mark each calendar Work or Personal; the dot colors follow
- **Settings window** with import and export, so a setup moves between Macs in one file
- **Menu bar clock:** optional, with seconds, AM/PM, 24-hour time, day and date; the dropdown always shows a live clock
- **Always running:** "Run as a service" (on by default) starts Tardy at login and reopens it within seconds if it quits or crashes
- **Keyboard shortcut:** ⇧⌘M opens and closes the menu from anywhere; change it in Settings > Shortcuts
- **Light on battery:** wakes only when something on screen needs to change, and refreshes when your calendars change instead of polling
- **Automatic updates** through [Sparkle](https://sparkle-project.org)

## Supported Meeting Providers

Tardy finds an https meeting link in an event's location, URL or notes (in that order)
and recognizes these providers. Only those hosts get a Join button, and invites you've
declined or that were canceled are left out entirely:

| Provider | Example link |
|---|---|
| Zoom (including ZoomGov) | `https://company.zoom.us/j/123456789` |
| Microsoft Teams (work and personal) | `https://teams.microsoft.com/l/meetup-join/…` |
| Google Meet | `https://meet.google.com/abc-defg-hij` |
| Webex | `https://company.webex.com/meet/name` |
| GoTo Meeting | `https://meet.goto.com/123456789` |
| Amazon Chime | `https://chime.aws/1234567890` |
| Slack Huddles | `https://app.slack.com/huddle/…` |
| Whereby | `https://whereby.com/room` |
| Jitsi Meet | `https://meet.jit.si/room` |
| Discord | `https://discord.gg/invite` |
| RingCentral Video | `https://v.ringcentral.com/join/…` |
| Zoho Meeting | `https://meeting.zoho.com/…` |

Only `https://` links are ever opened. A meeting without a recognized link still
gets every alert; clicking it opens Calendar.

## Usage

| Menu bar | When |
|---|---|
| `[WED 16] ●` | Next meeting more than 30 min away |
| `[WED 16] ● 2:30-3:00pm` | Within 30 min |
| `[WED 16] 12m - Standup` | 15 min |
| `🔴 4:59 - Standup (until 3:00pm)` | 5 min, live countdown |
| `⚠ LATE 1:23` (flashing) | Started |

Sound alerts run on their own schedule, set in **Settings > Alerts**:

| Default alert | Sounds | Notification |
|---|---|---|
| 10 min before | 1 Sonar | "Meeting in 10 minutes" |
| 5 min before | 2 Sonar | "Meeting in 5 minutes" |
| 2 min before | 3 Sonar | "Meeting in 2 minutes" |

With **Progressive sounds** on, each alert plays one more sound than the one before; turn
it off to choose each count. Add up to 5 alerts, 1 to 60 minutes before. **Skip sounds for
meetings without a meeting link** (off by default) keeps in-person and phone meetings quiet:
their notifications still appear, and the menu bar still counts down.

- **Click** the icon for today's meetings, Join and Dismiss, Mute Sounds and **Settings…** (⌘,).
  With Run as a service on, **Quit Tardy** reopens it a few seconds later; turn the service off
  in Settings > General to quit for good.
- **Settings** has panes for General (launch at login, run as a service), Alerts (mute, sound schedule, skip meetings without a link),
  Calendars (watch each one, Personal or Work), Clock, Shortcuts, Updates, and Import & Export.
- **⇧⌘M** (configurable) toggles the menu. Leave it open to watch the live clock.

Settings can be exported to a file and imported on another Mac; see
[docs/CONFIGURATION.md](docs/CONFIGURATION.md).

## Documentation

- [docs/CONFIGURATION.md](docs/CONFIGURATION.md): every setting and its `defaults` key
- [docs/DEVELOPING.md](docs/DEVELOPING.md): building, signing, notarizing, releasing and updates
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md): how alerts, scheduling and the menu work, and the macOS pitfalls behind them

## Contributing

[Issues](https://github.com/ventz/tardy/issues) and pull requests are welcome. See
[CONTRIBUTING.md](CONTRIBUTING.md).

## License

[MIT](LICENSE) © Ventz Petkov
