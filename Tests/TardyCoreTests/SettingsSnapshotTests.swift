import Foundation
import Testing
@testable import TardyCore

@Suite struct SettingsSnapshotTests {
    private let here = [
        CalendarRef(id: "A", source: "iCloud", title: "Home"),
        CalendarRef(id: "B", source: "iCloud", title: "Work"),
        CalendarRef(id: "C", source: "Exchange", title: "Calendar"),
    ]

    private func snapshot(_ calendars: [CalendarRef], disabled: Set<String> = [], work: Set<String> = []) -> SettingsSnapshot {
        var clock = ClockOptions()
        clock.enabled = true
        return SettingsSnapshot(muteSounds: true, clock: clock, calendars: calendars, disabled: disabled, work: work,
                                shortcut: .init(enabled: true, shortcut: .default),
                                exportedAt: Date(timeIntervalSince1970: 1_800_000_000))
    }

    @Test func roundTrips() throws {
        let original = snapshot(here, disabled: ["A"], work: ["B", "C"])
        #expect(try SettingsSnapshot.decode(original.encoded()) == original)
    }

    @Test func resolvesByIdentifier() {
        let resolved = snapshot(here, disabled: ["A"], work: ["B"]).resolve(against: here)
        #expect(resolved.disabled == ["A"])
        #expect(resolved.work == ["B"])
        #expect(resolved.matched == 3)
        #expect(resolved.unmatched.isEmpty)
    }

    @Test func fallsBackToAccountAndTitleOnAnotherMac() {
        let otherMac = [
            CalendarRef(id: "x1", source: "iCloud", title: "Work"),
            CalendarRef(id: "x2", source: "Exchange", title: "Calendar"),
        ]
        let resolved = snapshot(here, disabled: ["A"], work: ["B", "C"]).resolve(against: otherMac)
        #expect(resolved.work == ["x1", "x2"])
        #expect(resolved.disabled.isEmpty)
        #expect(resolved.unmatched == ["iCloud / Home"])
    }

    @Test func rejectsOtherFiles() {
        #expect(throws: SettingsImportError.notTardySettings) {
            try SettingsSnapshot.decode(Data(#"{"hello": "world"}"#.utf8))
        }
        #expect(throws: SettingsImportError.newerVersion(99)) {
            try SettingsSnapshot.decode(Data(#"{"format": "tardy-settings", "version": 99}"#.utf8))
        }
    }

    @Test func filesWithoutAShortcutStillImport() throws {
        let data = Data(#"{"format": "tardy-settings", "version": 1, "exportedAt": "2026-09-16T21:40:00Z", "muteSounds": false, "clock": {}, "calendars": []}"#.utf8)
        #expect(try SettingsSnapshot.decode(data).shortcut == nil)
    }

    @Test func clockToleratesMissingKeys() throws {
        let clock = try JSONDecoder().decode(ClockOptions.self, from: Data(#"{"enabled": true}"#.utf8))
        #expect(clock.enabled)
        #expect(clock.ampm)
        #expect(!clock.seconds)
    }
}
