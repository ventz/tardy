import type { Meeting, Phase, View } from '../types'

// Tardy's Timing, in milliseconds.
export const MIN = 60_000
export const ALARM = 1 * MIN
export const COUNTDOWN = 5 * MIN
export const ALERT = 15 * MIN
export const SHOW_TIME = 30 * MIN
export const LATE_AUTO_DISMISS = 5 * MIN

const RANK: Record<Phase, number> = { now: 0, later: 1, soon: 2, alert: 3, countdown: 4, alarm: 5, late: 6 }

export function phaseOf(m: Meeting, now: number): Phase {
  const until = m.start - now
  if (until <= 0) return now - m.start < LATE_AUTO_DISMISS ? 'late' : 'now'
  if (until <= ALARM) return 'alarm'
  if (until <= COUNTDOWN) return 'countdown'
  if (until <= ALERT) return 'alert'
  if (until <= SHOW_TIME) return 'soon'
  return 'later'
}

/** Highest phase wins; within a phase, the soonest start (Tardy's Primary.select). */
export function primary(meetings: readonly Meeting[], now: number, dismissed: ReadonlySet<string>): Meeting | undefined {
  let best: Meeting | undefined
  let bestRank = -1
  for (const m of meetings) {
    if (m.end <= now || dismissed.has(m.id)) continue
    const rank = RANK[phaseOf(m, now)]
    if (rank > bestRank || (rank === bestRank && best !== undefined && m.start < best.start)) {
      best = m
      bestRank = rank
    }
  }
  return best
}

/** `45m`, `1h 11m`, `2h` (Formatting.duration). */
export function duration(ms: number): string {
  const minutes = Math.max(1, Math.round(ms / MIN))
  const h = Math.floor(minutes / 60)
  const m = minutes % 60
  if (h === 0) return `${m}m`
  return m === 0 ? `${h}h` : `${h}h ${m}m`
}

/** Countdown `m:ss` (Formatting.minutesSeconds). */
export function minutesSeconds(ms: number): string {
  const total = Math.max(0, Math.floor(ms / 1000))
  return `${Math.floor(total / 60)}:${String(total % 60).padStart(2, '0')}`
}

export function view(meetings: readonly Meeting[], now: number, dismissed: ReadonlySet<string>): View {
  const m = primary(meetings, now, dismissed)
  if (m === undefined) return { kind: 'none' }

  const phase = phaseOf(m, now)
  const until = m.start - now
  let text: string
  switch (phase) {
    case 'late':
      text = `LATE ${minutesSeconds(now - m.start)} - ${m.title}`
      break
    case 'alarm':
    case 'countdown':
      text = `${minutesSeconds(until)} - ${m.title} (until ${m.until})`
      break
    case 'alert':
      text = `${duration(until)} - ${m.title}`
      break
    case 'soon':
      text = `${m.range} - ${m.title}`
      break
    case 'later':
      text = `Next: ${m.title} · ${m.range} (in ${duration(until)})`
      break
    case 'now':
      text = `Now: ${m.title} (until ${m.until})`
      break
  }

  const more = meetings.filter(o => o.id !== m.id && o.start > now && !dismissed.has(o.id)).length
  return {
    kind: 'meeting',
    id: m.id,
    phase,
    dot: m.kind === 'work' ? 'blue' : 'red',
    text,
    flash: phase === 'late' && Math.floor(now / 1000) % 2 === 0,
    ...(m.link ? { link: m.link } : {}),
    more,
  }
}

/** Milliseconds until the band could next change, so the timer runs fast only when it must. */
export function nextTick(meetings: readonly Meeting[], now: number, dismissed: ReadonlySet<string>): number {
  const m = primary(meetings, now, dismissed)
  if (m === undefined) return 30_000
  const phase = phaseOf(m, now)
  if (phase === 'late' || phase === 'alarm' || phase === 'countdown') return 1000
  // Wake at the next phase boundary of any meeting, at most every 15 s.
  let wait = 15_000
  for (const o of meetings) {
    for (const edge of [SHOW_TIME, ALERT, COUNTDOWN, 0]) {
      const at = o.start - edge - now
      if (at > 0 && at < wait) wait = at
    }
  }
  return Math.max(250, wait)
}

/** Only https links that the helper already matched to a known provider are opened. */
export function isSafeLink(url: string): boolean {
  return /^https:\/\/[^\s/@:]+(?::443)?\//i.test(url)
}

export function parse(stdout: string): Meeting[] {
  const rows: unknown = JSON.parse(stdout)
  if (!Array.isArray(rows)) throw new Error('expected a JSON array')
  return rows as Meeting[]
}

/** The /tardy listing: today's remaining meetings. */
export function agenda(meetings: readonly Meeting[], now: number): string {
  const left = meetings.filter(m => m.end > now)
  if (left.length === 0) return 'No more meetings today.'
  return left
    .map(m => {
      const tag = m.start <= now ? 'Now'.padEnd(7) : duration(m.start - now).padEnd(7)
      const link = m.link ? ` [${m.link.platform}]` : ''
      return `${tag} ${m.range.padEnd(16)} ${m.title}${link}`
    })
    .join('\n')
}
