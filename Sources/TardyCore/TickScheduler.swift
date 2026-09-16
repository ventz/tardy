import Foundation

public enum TickScheduler {
    /// Seconds until the display next needs to change.
    ///
    /// 1s (aligned to the second) while a meeting is within 15 min or LATE, the menu is
    /// open, or the menu bar clock shows seconds. Otherwise sleep until the next
    /// threshold -- T-30 time shown, T-15, a start, midnight, the next clock minute --
    /// capped at `Timing.maxTick`. Calendar edits, wake and timezone changes arrive as
    /// notifications and tick immediately.
    public static func nextDelay(
        now: Date,
        meetings: [Meeting],
        dismissed: Set<String>,
        menuOpen: Bool,
        clock: ClockOptions,
        calendar: Calendar = .current
    ) -> TimeInterval {
        let t = now.timeIntervalSinceReferenceDate
        let nextSecond = 1.0 - t.truncatingRemainder(dividingBy: 1.0) + 0.02
        if menuOpen || (clock.enabled && clock.seconds) { return nextSecond }

        var delay = Timing.maxTick
        if clock.enabled {
            delay = min(delay, 60.0 - t.truncatingRemainder(dividingBy: 60.0) + 0.05)
        }
        for meeting in meetings where !dismissed.contains(meeting.id) {
            let until = meeting.start.timeIntervalSince(now)
            if until > -Timing.lateAutoDismiss && until <= Timing.alert { return nextSecond }
            for offset in [Timing.showTime, Timing.alert, 0] {
                let wait = until - offset
                if wait > 0 { delay = min(delay, wait + 0.05) }
            }
        }
        if let midnight = calendar.nextDate(after: now, matching: DateComponents(hour: 0, minute: 0, second: 1),
                                            matchingPolicy: .nextTime) {
            delay = min(delay, midnight.timeIntervalSince(now))
        }
        return max(1.0, delay)
    }
}
