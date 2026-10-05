import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register, Timer } from 'claude-code'

import type { Meeting, View } from '../types'
import { agenda, isSafeLink, nextTick, parse, view } from './core'

const shown = atom({ plugin: 'tardy', key: 'view' } as const, null)

const DISMISSED_KEY = 'dismissed'
const HIDDEN_KEY = 'hidden'
// The calendar helper is re-run this often; Tardy itself refreshes on EventKit changes.
const REFRESH_MS = 2 * 60_000
const INSTALL = 'Install Tardy 1.0.5 or later, which ships the calendar helper: https://tardy.vpetkov.net'

// Tardy.app ships the helper; the first one that exists wins.
const FIND_APP_HELPER = [
  '/bin/sh',
  '-c',
  'for p in /Applications/Tardy.app "$HOME/Applications/Tardy.app"; do ' +
    'h="$p/Contents/Helpers/tardy-events"; [ -x "$h" ] && { printf %s "$h"; exit 0; }; done; exit 1',
]

// Module state; a reload starts it over, which only costs one lookup and helper run.
let meetings: Meeting[] = []
let error: string | null = null
let fetchedAt = 0
let timer: Timer | undefined
let helper: string | null = null
let building = false
let buildTried = false

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    const result = await next(e)
    await $.command.register({
      name: 'tardy',
      description: "Today's meetings; /tardy join | dismiss | refresh | hide | show",
    })
    await refresh($)
    await tick($)

    return result
  })

  on('command.run', { command: 'tardy' }, async ($, e) => {
    const arg = e.args.trim().toLowerCase()
    const now = await $.clock.now()

    if (arg === 'hide' || arg === 'show') {
      await $.store.set(HIDDEN_KEY, arg === 'hide')
      await tick($)
      return { text: arg === 'hide' ? 'Tardy band hidden.' : 'Tardy band shown.' }
    }
    if (arg === 'refresh') {
      await refresh($)
      await tick($)
      return { text: error ?? agenda(meetings, now) }
    }
    if (arg === 'join' || arg === 'dismiss') {
      const v = await read($, shown)
      if (v === null || v.kind !== 'meeting') {
        return { text: 'No meeting to ' + arg + '.' }
      }
      if (arg === 'join') {
        return { text: await join($, v) }
      }
      await dismiss($, v.id)
      return { text: 'Dismissed.' }
    }
    if (arg !== '') {
      return { text: 'Usage: /tardy [join | dismiss | refresh | hide | show]' }
    }

    return { text: error ?? agenda(meetings, now) }
  })

  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    const v = await read($, shown)
    if (e.props.hasSurvey || v === null || v.kind === 'none') {
      return next(e)
    }

    const { Box, Button, Text } = $.ui.resolve(e)
    if (v.kind === 'notice') {
      return <Text dimColor>{`tardy: ${v.text}`}</Text>
    }

    const urgent = v.phase === 'late' || v.phase === 'alarm' || v.phase === 'countdown'
    const actionable = urgent || v.phase === 'alert'
    const quiet = v.phase === 'later' || v.phase === 'now'
    const color = urgent ? 'red' : v.phase === 'alert' ? 'yellow' : undefined
    const mark = v.phase === 'late' ? '⚠ ' : '● '

    return (
      <Box flexDirection="row" columnGap={1}>
        <Text>
          <Text color={urgent ? 'red' : v.dot}>{mark}</Text>
          <Text color={color} bold={v.phase === 'late' || v.phase === 'alarm'} inverse={v.flash} dimColor={quiet} wrap="truncate-end">
            {v.text}
          </Text>
          {v.more > 0 && quiet ? <Text dimColor>{` +${v.more} more today`}</Text> : null}
        </Text>
        {actionable && v.link ? (
          <Button key="join" label={`Join ${v.link.platform}`} hotkey="j" variant="primary" onPress={() => join($, v)} />
        ) : null}
        {actionable ? <Button key="dismiss" label="Dismiss" hotkey="d" dimColor role="dismiss" onPress={() => dismiss($, v.id)} /> : null}
      </Box>
    )
  })
}

// Finds the helper. Run from a Tardy checkout (the plugin is its claude-code/ folder), the
// checkout's own build wins, and is built on first use; otherwise the installed Tardy.app's.
async function locate($: EngineInterface): Promise<string | null> {
  const repo = `${$.plugin.root}/..`
  try {
    const checkout = await $.process.run(['/bin/test', '-d', `${repo}/Sources/TardyEvents`])
    if (checkout.exitCode === 0) {
      const bin = await $.process.run(['swift', 'build', '-c', 'release', '--product', 'tardy-events', '--show-bin-path'], {
        cwd: repo,
        timeoutMs: 60_000,
      })
      const path = `${bin.stdout.trim()}/tardy-events`
      if (bin.exitCode === 0 && (await $.process.run(['/bin/test', '-x', path])).exitCode === 0) {
        return path
      }
      if (bin.exitCode === 0 && !buildTried) {
        buildTried = true
        building = true
        error = 'building the calendar helper from this checkout (first run only)…'
        $.clock.after(0, () => {
          void build($, repo)
        })
        return null
      }
    }
  } catch {
    // No swift toolchain: fall back to the app's helper.
  }

  const app = await $.process.run(FIND_APP_HELPER)
  return app.exitCode === 0 ? app.stdout : null
}

async function build($: EngineInterface, repo: string) {
  try {
    const r = await $.process.run(['swift', 'build', '-c', 'release', '--product', 'tardy-events'], {
      cwd: repo,
      timeoutMs: 600_000,
    })
    error = r.exitCode === 0 ? null : `swift build failed: ${r.stderr.trim().split('\n').slice(-1)[0] ?? r.exitCode}`
  } catch (err) {
    error = `swift build failed: ${String(err)}`
  }
  building = false
  if (error === null) {
    await refresh($)
  }
  await tick($)
}

// Runs the helper; on failure keeps the last good list and shows why.
async function refresh($: EngineInterface) {
  if (building) return
  fetchedAt = await $.clock.now()
  try {
    helper ??= await locate($)
    if (helper === null) {
      error ??= INSTALL
      return
    }
    const r = await $.process.run([helper], { timeoutMs: 20_000 })
    if (r.exitCode !== 0) {
      error = r.stderr.trim() || `tardy-events exited ${r.exitCode}`
      return
    }
    meetings = parse(r.stdout)
    error = null
  } catch (err) {
    helper = null
    error = `calendar helper failed: ${String(err)}`
  }
}

// Recomputes the band, writes it only when it changed, and schedules the next tick.
async function tick($: EngineInterface) {
  timer?.cancel()
  const now = await $.clock.now()
  if (now - fetchedAt >= REFRESH_MS) {
    await refresh($)
  }

  const dismissed = await dismissedSet($)
  let next: View
  if ((await $.store.get(HIDDEN_KEY)) === true) {
    next = { kind: 'none' }
  } else if (error !== null && meetings.length === 0) {
    next = { kind: 'notice', text: error }
  } else {
    next = view(meetings, now, dismissed)
  }

  const current = await read($, shown)
  if (JSON.stringify(current) !== JSON.stringify(next)) {
    await update($, shown, () => next)
  }

  timer = $.clock.after(nextTick(meetings, now, dismissed), () => {
    void tick($)
  })
}

async function dismissedSet($: EngineInterface): Promise<Set<string>> {
  const ids = await $.store.get(DISMISSED_KEY)
  return new Set(Array.isArray(ids) ? ids.filter((x): x is string => typeof x === 'string') : [])
}

// Shared across sessions through $.store; ids of meetings no longer listed are dropped.
async function dismiss($: EngineInterface, id: string) {
  const live = new Set(meetings.map(m => m.id))
  const ids = [...(await dismissedSet($))].filter(x => live.has(x))
  await $.store.set(DISMISSED_KEY, [...ids, id])
  await tick($)
}

async function join($: EngineInterface, v: Extract<View, { kind: 'meeting' }>): Promise<string> {
  if (!v.link || !isSafeLink(v.link.url)) {
    return 'This meeting has no meeting link.'
  }
  await $.process.run(['open', v.link.url])
  await dismiss($, v.id)
  return `Opened ${v.link.platform}.`
}
