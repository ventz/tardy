import { describe, expect, mock, test } from 'claude-code/testing'

import type { CommandRunInput, On } from 'claude-code'

import type { Meeting } from '../types'
import { MIN, agenda, duration, isSafeLink, minutesSeconds, nextTick, phaseOf, primary, view } from './core'

const T0 = 1_791_219_600_000

function meeting(id: string, startOffset: number, extra: Partial<Meeting> = {}): Meeting {
  return {
    id,
    title: `Meeting ${id}`,
    start: T0 + startOffset,
    end: T0 + startOffset + 30 * MIN,
    range: '1:00-1:30pm',
    until: '1:30pm',
    kind: 'work',
    ...extra,
  }
}

const NONE = new Set<string>()

describe('phases follow Tardy timing', () => {
  const m = meeting('a', 0)
  const cases: [number, string][] = [
    [-45 * MIN, 'later'],
    [-30 * MIN, 'soon'],
    [-15 * MIN, 'alert'],
    [-5 * MIN, 'countdown'],
    [-1 * MIN, 'alarm'],
    [0, 'late'],
    [4 * MIN, 'late'],
    [5 * MIN, 'now'],
  ]
  for (const [offset, phase] of cases) {
    test(`${offset / MIN} min → ${phase}`, async () => {
      expect(phaseOf(m, T0 + offset)).toBe(phase)
    })
  }
})

describe('primary and view', () => {
  test('LATE beats an upcoming meeting; dismissing it shows the next', async () => {
    const list = [meeting('late', -2 * MIN), meeting('next', 10 * MIN)]
    expect(primary(list, T0, NONE)?.id).toBe('late')
    expect(primary(list, T0, new Set(['late']))?.id).toBe('next')
  })

  test('countdown text and end time', async () => {
    const v = view([meeting('a', 4 * MIN + 59_000)], T0, NONE)
    expect(v.kind === 'meeting' ? v.text : '').toBe('4:59 - Meeting a (until 1:30pm)')
  })

  test('LATE text flashes', async () => {
    const v1 = view([meeting('a', -83_000)], T0, NONE)
    const v2 = view([meeting('a', -84_000)], T0 + 1000, NONE)
    expect(v1.kind === 'meeting' ? v1.text : '').toBe('LATE 1:23 - Meeting a')
    expect(v1.kind === 'meeting' && v2.kind === 'meeting' && v1.flash !== v2.flash).toBe(true)
  })

  test('personal meetings get the red dot, ended ones vanish', async () => {
    const v = view([meeting('p', 20 * MIN, { kind: 'personal' })], T0, NONE)
    expect(v.kind === 'meeting' ? v.dot : '').toBe('red')
    expect(view([meeting('old', -40 * MIN)], T0, NONE).kind).toBe('none')
  })

  test('ticks fast only near a meeting', async () => {
    expect(nextTick([meeting('a', 3 * MIN)], T0, NONE)).toBe(1000)
    expect(nextTick([meeting('a', 15 * MIN + 2000)], T0, NONE)).toBe(2000)
    expect(nextTick([meeting('a', 3 * 60 * MIN)], T0, NONE)).toBe(15_000)
  })
})

describe('formatting and links', () => {
  test('duration and m:ss', async () => {
    expect(duration(45 * MIN)).toBe('45m')
    expect(duration(71 * MIN)).toBe('1h 11m')
    expect(duration(120 * MIN)).toBe('2h')
    expect(minutesSeconds(299_400)).toBe('4:59')
  })

  test('only plain https links open', async () => {
    expect(isSafeLink('https://acme.zoom.us/j/123')).toBe(true)
    expect(isSafeLink('http://acme.zoom.us/j/123')).toBe(false)
    expect(isSafeLink('https://user@acme.zoom.us/j/123')).toBe(false)
    expect(isSafeLink('https://acme.zoom.us:8443/j/123')).toBe(false)
    expect(isSafeLink('javascript:alert(1)')).toBe(false)
  })

  test('agenda lists what is left', async () => {
    const text = agenda([meeting('a', -60 * MIN), meeting('b', 30 * MIN, { link: { url: 'https://meet.google.com/abc-defg-hij', platform: 'Google Meet' } })], T0)
    expect(text).toBe('30m     1:00-1:30pm      Meeting b [Google Meet]')
  })
})

const RUN = (args: string): CommandRunInput => ({
  command: 'tardy',
  args,
  origin: { kind: 'composer' },
  presentation: { isFullscreen: false, columns: 100 },
})

const PROPS = {
  hasSurvey: false,
  isWorking: false,
  maxRows: 10,
  bodyColumns: 100,
  scroll: { offset: 0, bodyRows: 10 },
  view: {},
}

const APP_HELPER = '/Applications/Tardy.app/Contents/Helpers/tardy-events'
const BIN = '/repo/.build/release'

type Machine = { checkout: boolean; built: boolean; app: boolean; rows: Meeting[] }

// A fake host: which helpers exist, and what each command prints.
function host(on: On, m: Machine, ran: string[]) {
  const ok = (stdout = '', exitCode = 0) => ({
    value: { exitCode, stdout, stderr: exitCode === 0 ? '' : 'failed', isStdoutTruncated: false, isStderrTruncated: false },
  })
  on('process.run', (_$, e) => {
    const argv = e.argv
    ran.push(argv.join(' '))
    if (argv[0] === '/bin/test') {
      const path = argv[2] ?? ''
      if (path.endsWith('Sources/TardyEvents')) return ok('', m.checkout ? 0 : 1)
      return ok('', path === `${BIN}/tardy-events` && m.built ? 0 : 1)
    }
    if (argv[0] === '/bin/sh') return ok(m.app ? APP_HELPER : '', m.app ? 0 : 1)
    if (argv[0] === 'swift' && argv.includes('--show-bin-path')) return ok(`${BIN}\n`)
    if (argv[0] === 'swift') {
      m.built = true
      return ok()
    }
    return ok(JSON.stringify(m.rows))
  })
}

for (const surface of ['terminal', 'desktop'] as const) {
  test(`draws the next meeting from Tardy.app's helper on ${surface}`, async ($, on) => {
    mock.store(on)
    const clock = mock.clock(on, { now: T0 })
    // With the band empty the engine draws its own; stand in for it.
    on('ui.render', ($, e) => $.ui.resolve(e).Text({ children: 'engine' }))
    const ran: string[] = []
    host(on, { checkout: false, built: false, app: true, rows: [meeting('soon', 3 * MIN, { link: { url: 'https://acme.zoom.us/j/1', platform: 'Zoom' } })] }, ran)
    await $.command.run(RUN('refresh'))
    expect(ran.includes(APP_HELPER)).toBe(true)

    const ui = await $.ui.mount({ plugin: 'tardy', surface, component: 'AbovePrompt', props: PROPS })
    expect((await ui.find({ text: '3:00 - Meeting soon (until 1:30pm)' })) !== undefined).toBe(true)
    expect((await ui.find({ key: 'join' })) !== undefined).toBe(true)

    // The timer keeps the countdown live and turns it into LATE at the start.
    await clock.advance(3 * MIN + 7000)
    const late = await $.ui.mount({ plugin: 'tardy', surface, component: 'AbovePrompt', props: PROPS })
    expect((await late.find({ text: 'LATE 0:07 - Meeting soon' })) !== undefined).toBe(true)

    await $.command.run(RUN('dismiss'))
    const after = await $.ui.mount({ plugin: 'tardy', surface, component: 'AbovePrompt', props: PROPS })
    expect(await after.find({ key: 'join' })).toBe(undefined)
    expect((await after.find({ text: 'engine' })) !== undefined).toBe(true)
  })

  test(`builds the helper once in a checkout on ${surface}`, async ($, on) => {
    mock.store(on)
    const clock = mock.clock(on, { now: T0 })
    const ran: string[] = []
    host(on, { checkout: true, built: false, app: true, rows: [meeting('a', 20 * MIN)] }, ran)
    await $.command.run(RUN('refresh'))

    const building = await $.ui.mount({ plugin: 'tardy', surface, component: 'AbovePrompt', props: PROPS })
    expect((await building.find({ text: /building the calendar helper/ })) !== undefined).toBe(true)

    await clock.advance(1)
    expect(ran.filter(c => c === 'swift build -c release --product tardy-events').length).toBe(1)
    expect(ran.includes(`${BIN}/tardy-events`)).toBe(true)
    expect(ran.includes(APP_HELPER)).toBe(false)
    const done = await $.ui.mount({ plugin: 'tardy', surface, component: 'AbovePrompt', props: PROPS })
    expect((await done.find({ text: '1:00-1:30pm - Meeting a' })) !== undefined).toBe(true)
  })

  test(`asks for Tardy when no helper exists on ${surface}`, async ($, on) => {
    mock.store(on)
    mock.clock(on, { now: T0 })
    host(on, { checkout: false, built: false, app: false, rows: [] }, [])
    const { text } = await $.command.run(RUN('refresh'))
    expect(text).toBe('Install Tardy 1.0.5 or later, which ships the calendar helper: https://tardy.vpetkov.net')
  })

  test(`shows the helper's error on ${surface}`, async ($, on) => {
    mock.store(on)
    mock.clock(on, { now: T0 })
    on('process.run', (_$, e) =>
      e.argv[0] === '/bin/sh'
        ? { value: { exitCode: 0, stdout: APP_HELPER, stderr: '', isStdoutTruncated: false, isStderrTruncated: false } }
        : e.argv[0] === '/bin/test'
          ? { value: { exitCode: 1, stdout: '', stderr: '', isStdoutTruncated: false, isStderrTruncated: false } }
          : { value: { exitCode: 2, stdout: '', stderr: 'no calendar access', isStdoutTruncated: false, isStderrTruncated: false } },
    )
    const { text } = await $.command.run(RUN('refresh'))
    expect(text).toBe('no calendar access')
  })
}
