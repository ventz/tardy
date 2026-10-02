import Foundation
import Testing
@testable import TardyCore

@Suite struct AlertSoundsTests {
    @Test func defaultsAreTenFiveTwoCountingUp() {
        let sounds = AlertSounds()
        #expect(sounds.alerts.map(\.minutes) == [10, 5, 2])
        #expect(sounds.alerts.indices.map(sounds.beeps(at:)) == [1, 2, 3])
    }

    @Test func customCountsApplyOnlyWhenNotProgressive() {
        var sounds = AlertSounds(progressive: false, alerts: [.init(minutes: 3, beeps: 5), .init(minutes: 20, beeps: 2)])
        #expect(sounds.alerts.map(\.minutes) == [20, 3])
        #expect([0, 1].map(sounds.beeps(at:)) == [2, 5])
        sounds.progressive = true
        #expect([0, 1].map(sounds.beeps(at:)) == [1, 2])
    }

    @Test func normalizesClampsDedupesAndCaps() {
        let sounds = AlertSounds(progressive: false, alerts: [
            .init(minutes: 0, beeps: 0), .init(minutes: 999, beeps: 99), .init(minutes: 5, beeps: 1),
            .init(minutes: 5, beeps: 3), .init(minutes: 4, beeps: 1), .init(minutes: 3, beeps: 1),
            .init(minutes: 2, beeps: 1),
        ])
        #expect(sounds.alerts == [.init(minutes: 60, beeps: 5), .init(minutes: 5, beeps: 1), .init(minutes: 4, beeps: 1),
                                  .init(minutes: 3, beeps: 1), .init(minutes: 2, beeps: 1)])
        #expect(AlertSounds(progressive: true, alerts: []).alerts == AlertSounds().alerts)
    }

    @Test func playsEachAlertOnceAsTheMeetingApproaches() {
        let sounds = AlertSounds()
        var handled = Set<Int>()
        #expect(sounds.due(secondsUntil: 700, handled: &handled) == nil)
        #expect(sounds.due(secondsUntil: 600, handled: &handled)?.index == 0)
        #expect(sounds.due(secondsUntil: 590, handled: &handled) == nil)
        #expect(sounds.due(secondsUntil: 299, handled: &handled)?.index == 1)
        #expect(sounds.due(secondsUntil: 120, handled: &handled)?.index == 2)
        #expect(sounds.due(secondsUntil: 60, handled: &handled) == nil)
        #expect(handled == [10, 5, 2])
    }

    @Test func startingLatePlaysOnlyTheMostRecentAlert() {
        var handled = Set<Int>()
        #expect(AlertSounds().due(secondsUntil: 180, handled: &handled)?.alert.minutes == 5)
        #expect(handled == [10, 5])
        var started = Set<Int>()
        #expect(AlertSounds().due(secondsUntil: 0, handled: &started) == nil)
    }

    @Test func proposesAFreeMinuteUntilFull() {
        var sounds = AlertSounds()
        #expect(sounds.proposedAlert() == .init(minutes: 1, beeps: 4))
        sounds.setAlerts(sounds.alerts + [sounds.proposedAlert()!])
        #expect(sounds.proposedAlert()?.minutes == 60)
        sounds.setAlerts(sounds.alerts + [sounds.proposedAlert()!])
        #expect(sounds.proposedAlert() == nil)
    }

    @Test func toleratesMissingAndHostileValues() throws {
        let decoded = try JSONDecoder().decode(AlertSounds.self, from: Data(#"{"alerts": [{"minutes": -4, "beeps": 1000}]}"#.utf8))
        #expect(decoded.progressive)
        #expect(decoded.alerts == [.init(minutes: 1, beeps: 5)])
    }

    @Test func skipsSoundsOnlyForMeetingsWithoutALinkWhenAsked() throws {
        let link = try #require(MeetingLinks.extract(location: "https://zoom.us/j/123456789", url: nil, notes: nil))
        func meeting(_ link: MeetingLink?) -> Meeting {
            Meeting(id: "m", title: "t", start: .distantFuture, end: .distantFuture, calendarID: "c", link: link)
        }
        var sounds = AlertSounds()
        #expect(!sounds.skipWithoutLink)
        #expect(sounds.playsSounds(for: meeting(nil)))
        sounds.skipWithoutLink = true
        #expect(!sounds.playsSounds(for: meeting(nil)))
        #expect(sounds.playsSounds(for: meeting(link)))
    }

    @Test func skipWithoutLinkRoundTripsAndDefaultsOffInOlderFiles() throws {
        let sounds = AlertSounds(progressive: true, alerts: [.init(minutes: 5, beeps: 1)], skipWithoutLink: true)
        let decoded = try JSONDecoder().decode(AlertSounds.self, from: JSONEncoder().encode(sounds))
        #expect(decoded == sounds)
        let older = try JSONDecoder().decode(AlertSounds.self, from: Data(#"{"progressive": false}"#.utf8))
        #expect(!older.skipWithoutLink)
    }

    @Test func schedulerWakesForAnAlertBeyondFifteenMinutes() {
        let now = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let meeting = Meeting(id: "m", title: "Standup", start: now.addingTimeInterval(45 * 60),
                              end: now.addingTimeInterval(50 * 60), calendarID: "c", link: nil)
        let delay = TickScheduler.nextDelay(now: now, meetings: [meeting], dismissed: [], menuOpen: false,
                                            clock: ClockOptions(), alertMinutes: [40])
        #expect(abs(delay - 300.05) < 0.01)
    }
}
