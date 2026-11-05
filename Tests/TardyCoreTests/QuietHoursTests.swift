import Foundation
import Testing
@testable import TardyCore

@Suite struct QuietHoursTests {
    private static let calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/New_York")!
        return cal
    }()

    /// 2026-11-02 is a Monday.
    private func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        Self.calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    private func silenced(_ quiet: QuietHours, _ date: Date) -> Bool { quiet.silences(date, calendar: Self.calendar) }

    @Test func defaultsAllowEightToSixOnWeekdaysOnly() {
        let quiet = QuietHours()
        #expect(quiet.enabled && quiet.schedule == .weekdaysWeekend && !quiet.includeNotifications)
        #expect(silenced(quiet, at(2, 7, 59)))
        #expect(!silenced(quiet, at(2, 8)))
        #expect(!silenced(quiet, at(6, 17, 59)))   // Friday
        #expect(silenced(quiet, at(6, 18)))
        #expect(silenced(quiet, at(7, 12)))        // Saturday noon
        #expect(silenced(quiet, at(8, 12)))        // Sunday noon
        var off = quiet
        off.enabled = false
        #expect(!silenced(off, at(8, 23)))
    }

    @Test func editingTheWeekendRowSetsBothWeekendDays() {
        var quiet = QuietHours()
        let weekend = quiet.groups()[1]
        #expect(weekend.slot == .weekend)
        quiet.set(DayHours(alerts: true, start: 10 * 60, end: 14 * 60), for: weekend)
        #expect(!silenced(quiet, at(7, 10)) && !silenced(quiet, at(8, 13, 59)))
        #expect(silenced(quiet, at(8, 14)))
        #expect(!silenced(quiet, at(2, 9)))        // weekdays untouched
    }

    /// The bug the first UI had: picking Every day copied Monday onto the weekend.
    @Test func eachScheduleKeepsItsOwnHoursAcrossSwitches() {
        var quiet = QuietHours()
        quiet.schedule = .everyDay
        #expect(!silenced(quiet, at(7, 12)))       // every day 8–6, Saturday included
        quiet.schedule = .eachDay
        let groups = quiet.groups()
        #expect(groups.count == 7 && groups.first?.slot == .day(2) && groups.last?.slot == .day(1))
        #expect(silenced(quiet, at(7, 12)) && silenced(quiet, at(8, 12)))   // weekend still quiet
        quiet.set(.quiet, for: groups[2])                                    // Wednesday off
        #expect(silenced(quiet, at(4, 9)))
        quiet.schedule = .weekdaysWeekend
        #expect(!silenced(quiet, at(4, 9)) && silenced(quiet, at(7, 12)))
        quiet.schedule = .eachDay
        #expect(silenced(quiet, at(4, 9)))         // Wednesday's change survived
    }

    @Test func dayHoursKeepTheEndAfterTheStart() {
        var hours = DayHours.workday
        hours.setStart(18 * 60)
        #expect(hours.start == 18 * 60 && hours.end == 18 * 60 + 30)
        hours.setEnd(17 * 60)
        #expect(hours.end == 18 * 60 + 30)
        hours.setStart(24 * 60 + 99)
        #expect(hours.start == 24 * 60 - 1 && hours.end == 24 * 60)
        #expect(DayHours(alerts: true, start: -5, end: 99_999) == DayHours(alerts: true, start: 0, end: 24 * 60))
    }

    @Test func soundsAndNotificationsFollowTheMeetingStart() {
        func meeting(_ start: Date) -> Meeting {
            Meeting(id: "m", title: "t", start: start, end: start, calendarID: "c", link: nil)
        }
        var sounds = AlertSounds()
        let saturday = meeting(at(7, 10)), monday = meeting(at(2, 8))
        #expect(!sounds.playsSounds(for: saturday, calendar: Self.calendar))
        #expect(sounds.postsNotification(for: saturday, calendar: Self.calendar))
        #expect(sounds.playsSounds(for: monday, calendar: Self.calendar))
        sounds.quietHours.includeNotifications = true
        #expect(!sounds.postsNotification(for: saturday, calendar: Self.calendar))
        #expect(sounds.postsNotification(for: monday, calendar: Self.calendar))
    }

    @Test func roundTripsAndToleratesOlderAndHostileFiles() throws {
        var quiet = QuietHours()
        quiet.schedule = .eachDay
        quiet.set(.quiet, for: quiet.groups()[0])
        quiet.includeNotifications = true
        let sounds = AlertSounds(progressive: true, alerts: [.init(minutes: 5, beeps: 1)], quietHours: quiet)
        #expect(try JSONDecoder().decode(AlertSounds.self, from: JSONEncoder().encode(sounds)) == sounds)

        let older = try JSONDecoder().decode(AlertSounds.self, from: Data(#"{"progressive": false}"#.utf8))
        #expect(older.quietHours == QuietHours())
        let hostile = try JSONDecoder().decode(QuietHours.self, from: Data(
            #"{"schedule": "fortnightly", "days": [{"alerts": true, "start": -1, "end": 1}], "enabled": false}"#.utf8))
        #expect(!hostile.enabled && hostile.schedule == .weekdaysWeekend && hostile.days == QuietHours().days)
        let badDay = try JSONDecoder().decode(QuietHours.self, from: Data(#"{"weekend": "nope", "enabled": true}"#.utf8))
        #expect(badDay.weekendHours == .quiet)
    }
}
