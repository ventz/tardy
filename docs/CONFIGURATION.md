# Configuration

Open **Settings…** from the Tardy menu (or press ⌘, while the menu is open). Settings are
stored in macOS defaults under `net.vpetkov.tardy` (`net.vpetkov.tardy.debug` for
development builds):

```bash
defaults read net.vpetkov.tardy
```

## Table of Contents

- [Panes](#panes)
- [Import and export](#import-and-export)
- [Defaults keys](#defaults-keys)
- [Resetting](#resetting)

## Panes

| Pane | Settings |
|---|---|
| General | Mute sounds and notifications, launch at login, keyboard shortcut, version |
| Calendars | Watch each calendar from the Mac Calendar app; mark it Personal (red) or Work (blue) |
| Clock | Menu bar clock on or off; seconds, AM/PM, 24-hour, day of week, date; live preview |
| Shortcuts | Record the global open/close shortcut (default ⇧⌘M) or turn it off; lists the in-menu shortcuts |
| Updates | Automatic update checks, check now, last check |
| Import & Export | Export to a file, import from a file, reset everything |

Calendars are stored as *disabled* rather than enabled, so a calendar added to the Mac
Calendar app later is watched automatically. The menu bar dot takes the color of the
**next meeting that hasn't started**; a meeting in progress gets no dot.

A new shortcut needs ⌘, ⌥ or ⌃. If another app already registered the combination, macOS
refuses it and Tardy keeps the previous one; shortcuts macOS reserves for itself (such as
⌘Space) can't be detected.

Menu bar seconds wake the Mac every second; without them the clock updates once a minute.
The menu's own clock always shows seconds.

## Import and export

**Settings > Import & Export > Export…** writes a JSON file:

```json
{
  "calendars" : [
    { "id" : "0DEAFB13-…", "kind" : "work", "source" : "iCloud", "title" : "Work", "watched" : true }
  ],
  "clock" : { "ampm" : true, "date" : true, "enabled" : false, "seconds" : false, "twentyFourHour" : false, "weekday" : true },
  "exportedAt" : "2026-09-16T21:40:00Z",
  "format" : "tardy-settings",
  "muteSounds" : false,
  "version" : 1
}
```

The file also carries the shortcut (`"shortcut": {"enabled": …, "shortcut": {…}}`); files
exported before shortcuts were configurable simply leave it unchanged.

**Import…** asks before replacing every setting. Calendar identifiers differ between Macs,
so each calendar is matched by identifier first, then by account and title; calendars the
file doesn't mention go back to watched and Personal, and any that can't be found are listed.
A file from a newer Tardy is refused rather than half-applied, and clock options missing from
an older file take their defaults.

## Defaults keys

| Key | Type | Default |
|---|---|---|
| `disabledCalendarIDs` | array of calendar IDs | empty (every calendar watched) |
| `workCalendarIDs` | array of calendar IDs | empty (every calendar Personal) |
| `clock` | JSON data | menu bar clock off |
| `muteSounds` | bool | `false` |
| `menuShortcut` | JSON data (Carbon key code, modifiers, label) | ⇧⌘M |
| `menuShortcutEnabled` | bool | `true` |
| `didRegisterLoginItem` | bool | state, not a setting: launch at login was turned on at first launch |

Launch at login itself is managed by macOS (`SMAppService`), not stored in defaults.

## Resetting

Use **Settings > Import & Export > Reset…**, or from Terminal:

```bash
killall Tardy
defaults delete net.vpetkov.tardy
open -a Tardy
```

Calendar and notification permissions are separate, in **System Settings > Privacy &
Security > Calendars** and **System Settings > Notifications > Tardy**.
