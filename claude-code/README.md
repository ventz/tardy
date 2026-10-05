# Tardy for Claude Code

A [Claude Code](https://code.claude.com) mod that shows Tardy's menu bar escalation as a band above the prompt, so a meeting can't sneak up on you while you're deep in a session. It reads the same calendars as the Tardy app and applies the same rules, so the band and the menu bar always agree.

## Contents

- [Install](#install)
- [What it shows](#what-it-shows)
- [Use](#use)
- [How it works](#how-it-works)
- [Develop](#develop)

## Install

Requires Claude Code 2.1.287 or later (mods) and Tardy 1.0.5 or later, which ships the calendar helper the mod reads.

```bash
claude plugin marketplace add ventz/tardy
claude plugin install tardy@tardy
```

Start a new session (or run `/reload-plugins`) and the band appears above the prompt. Calendar access belongs to the terminal app that runs Claude Code. If the band says it has no access, allow that terminal in **System Settings > Privacy & Security > Calendars**.

The band sits in Claude Code's above-prompt slot, which holds one mod at a time. Disable any other mod that draws there.

## What it shows

| Band | When |
| --- | --- |
| `● Next: Standup · 2:30-3:00pm (in 1h 12m) +2 more today` (dim) | Next meeting more than 30 min away |
| `● 2:30-3:00pm - Standup` | Within 30 min |
| `● 12m - Standup  [Join Zoom] [Dismiss]` (yellow) | Within 15 min |
| `● 4:59 - Standup (until 3:00pm)` (red, live) | Within 5 min; bold in the last minute |
| `⚠ LATE 1:23 - Standup` (red, flashing) | Started; clears itself after 5 min |
| `● Now: Standup (until 3:00pm)` (dim) | In a meeting with nothing after it |

The dot is blue for a Work calendar and red for a Personal one, as marked in Tardy's Settings > Calendars. Nothing shows once the day is done.

## Use

- **Join** opens the meeting link and dismisses the meeting; **Dismiss** hides it. With the band focused (ctrl+x tab), `j` and `d` press them. A dismissal applies in every session.
- `/tardy` lists today's remaining meetings. `/tardy join`, `/tardy dismiss`, `/tardy refresh`, `/tardy hide` and `/tardy show` do what they say.
- There are no sounds or notifications here: the Tardy app already does those.

## How it works

- **`tardy-events`** (`Sources/TardyEvents`) is a small command-line helper built on `TardyCore`, so declined and canceled invites, all-day events, title cleanup and the meeting-link allowlist are the app's own code. It reads the app's calendar choices (`disabledCalendarIDs`, `workCalendarIDs` in `net.vpetkov.tardy`) and prints today's remaining meetings as JSON, with times formatted in the Mac's time zone.
- **Tardy.app ships it** in `Contents/Helpers/tardy-events`, signed and notarized with the app, so installing the mod needs no build. The mod looks in `/Applications` and `~/Applications`.
- **The mod** runs the helper at session start and every 2 minutes. It ticks once a second only inside the 5-minute countdown and while LATE; otherwise it wakes at the next phase boundary, at most every 15 s, and redraws only when the text changes.
- **Join** opens only `https://` links the helper matched to a known provider (`MeetingLinks.isSafeToOpen`), and the mod checks the scheme again.

## Develop

Load the mod straight from a checkout:

```bash
claude plugin marketplace add ~/git/tardy   # or: claude --plugin-dir ~/git/tardy/claude-code
claude plugin install tardy@tardy
```

From a checkout, the mod prefers the checkout's own helper and builds it on first use (`swift build -c release --product tardy-events`, about a minute the first time; the band says so meanwhile). Rebuild after changing `TardyCore` or `Sources/TardyEvents`. Without a Swift toolchain it falls back to the installed app's helper.

```bash
claude plugin validate claude-code
claude plugin test claude-code        # 24 tests: phases, formatting, links, helper lookup, auto-build
```
