/** One meeting as tardy-events (Sources/TardyEvents) prints it. Times are epoch milliseconds. */
export type Meeting = {
  id: string
  title: string
  start: number
  end: number
  /** Preformatted by the helper in the host's time zone: `2:30-3:00pm`. */
  range: string
  /** The end time alone: `3:00pm`. */
  until: string
  kind: 'work' | 'personal'
  link?: { url: string; platform: string }
}

/** Tardy's escalation, lowest to highest. */
export type Phase = 'later' | 'soon' | 'alert' | 'countdown' | 'alarm' | 'late' | 'now'

/** What the band draws; recomputed each tick and written only when it changes. */
export type View =
  | { kind: 'none' }
  /** Setup state or a helper failure, drawn dim. */
  | { kind: 'notice'; text: string }
  | {
      kind: 'meeting'
      id: string
      phase: Phase
      /** Dot color: Tardy's red for personal, blue for work. */
      dot: 'red' | 'blue'
      text: string
      /** Alternates each second while LATE, for the flash. */
      flash: boolean
      link?: { url: string; platform: string }
      /** Meetings left today after this one. */
      more: number
    }

declare module 'claude-code' {
  interface PluginState {
    tardy: { view: View | null }
  }
}
