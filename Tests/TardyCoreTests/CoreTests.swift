import Foundation
import Testing
@testable import TardyCore

private let posix = Locale(identifier: "en_US_POSIX")

private func date(_ hour: Int, _ minute: Int, _ second: Int = 0) -> Date {
    var c = DateComponents()
    (c.year, c.month, c.day, c.hour, c.minute, c.second) = (2026, 9, 16, hour, minute, second)
    return Calendar.current.date(from: c)!
}

private func meeting(_ id: String, start: Date, minutes: Double = 30) -> Meeting {
    Meeting(id: id, title: id, start: start, end: start.addingTimeInterval(minutes * 60),
            calendarID: "cal", link: nil)
}

@Suite struct AlertStateTests {
    @Test func thresholds() {
        #expect(AlertState.forSecondsUntil(3600) == .idle)
        #expect(AlertState.forSecondsUntil(900) == .alert15)
        #expect(AlertState.forSecondsUntil(300) == .countdown)
        #expect(AlertState.forSecondsUntil(60) == .alarm)
        #expect(AlertState.forSecondsUntil(0) == .late)
        #expect(AlertState.forSecondsUntil(-120) == .late)
    }

    @Test func primaryPrefersHigherStateThenSoonest() {
        let now = date(10, 0)
        let a = meeting("a", start: date(10, 10)), b = meeting("b", start: date(10, 3)), c = meeting("c", start: date(10, 12))
        let states: [String: AlertState] = ["a": .alert15, "b": .countdown, "c": .alert15]
        #expect(Primary.select([a, b, c], states: states, now: now)?.id == "b")
        #expect(Primary.select([a, c], states: states, now: now)?.id == "a")
    }
}

@Suite struct FormattingTests {
    @Test func shortRangeDropsRepeatedPeriod() {
        #expect(Formatting.shortRange(date(14, 30), date(15, 0), locale: posix) == "2:30-3:00pm")
        #expect(Formatting.shortRange(date(11, 30), date(12, 30), locale: posix) == "11:30am-12:30pm")
    }

    @Test func longRange() {
        #expect(Formatting.longRange(date(17, 0), date(18, 0), locale: posix) == "5:00 PM - 6:00 PM")
    }

    @Test func duration() {
        #expect(Formatting.duration(45 * 60) == "45m")
        #expect(Formatting.duration(71 * 60) == "1h 11m")
        #expect(Formatting.duration(120 * 60) == "2h")
        #expect(Formatting.duration(5) == "1m")
    }

    @Test func clockMatchesMenuBarStyle() {
        #expect(Formatting.clock(date(16, 56, 47), .menuHeader, locale: posix) == "Wed Sep 16  4:56:47 PM")
        var options = ClockOptions()
        options.weekday = false
        options.date = false
        #expect(Formatting.clock(date(16, 56, 47), options, locale: posix) == "4:56 PM")
        options.twentyFourHour = true
        options.seconds = true
        #expect(Formatting.clock(date(16, 56, 47), options, locale: posix) == "16:56:47")
    }
}

@Suite struct TickSchedulerTests {
    private let clockOff = ClockOptions()

    @Test func idleSleepsUntilNextThreshold() {
        // Meeting at 11:00 -> next threshold is T-30 at 10:30
        let delay = TickScheduler.nextDelay(now: date(10, 25), meetings: [meeting("m", start: date(11, 0))],
                                            dismissed: [], menuOpen: false, clock: clockOff)
        #expect(abs(delay - 300.05) < 0.01)
    }

    @Test func idleIsCappedAtMaxTick() {
        let delay = TickScheduler.nextDelay(now: date(9, 0), meetings: [meeting("m", start: date(15, 0))],
                                            dismissed: [], menuOpen: false, clock: clockOff)
        #expect(delay == Timing.maxTick)
    }

    @Test func nearMeetingTicksEverySecond() {
        let delay = TickScheduler.nextDelay(now: date(10, 50), meetings: [meeting("m", start: date(11, 0))],
                                            dismissed: [], menuOpen: false, clock: clockOff)
        #expect(delay <= 1.02)
    }

    @Test func dismissedMeetingDoesNotForceFastTicks() {
        let delay = TickScheduler.nextDelay(now: date(10, 50), meetings: [meeting("m", start: date(11, 0))],
                                            dismissed: ["m"], menuOpen: false, clock: clockOff)
        #expect(delay > 1.02)
    }

    @Test func openMenuAndSecondsClockTickEverySecond() {
        #expect(TickScheduler.nextDelay(now: date(9, 0), meetings: [], dismissed: [], menuOpen: true, clock: clockOff) <= 1.02)
        var clock = ClockOptions()
        clock.enabled = true
        clock.seconds = true
        #expect(TickScheduler.nextDelay(now: date(9, 0), meetings: [], dismissed: [], menuOpen: false, clock: clock) <= 1.02)
    }

    @Test func minuteClockAlignsToTheMinute() {
        var clock = ClockOptions()
        clock.enabled = true
        let delay = TickScheduler.nextDelay(now: date(9, 0, 40), meetings: [], dismissed: [], menuOpen: false, clock: clock)
        #expect(abs(delay - 20.05) < 0.01)
    }

    @Test func wakesAtMidnight() {
        let delay = TickScheduler.nextDelay(now: date(23, 58), meetings: [], dismissed: [], menuOpen: false, clock: clockOff)
        #expect(abs(delay - 121) < 0.5)
    }
}
