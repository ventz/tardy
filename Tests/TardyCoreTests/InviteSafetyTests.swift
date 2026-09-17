import Foundation
import Testing
@testable import TardyCore

@Suite struct InviteSafetyTests {
    @Test(arguments: [
        ("Standup", "Standup"),
        ("  Team\tsync  ", "Team sync"),
        ("Pay\u{202E}fdp.exe", "Pay fdp.exe"),
        ("Real\u{2028}9:00 AM - 9:30 AM  ·  Zoom", "Real 9:00 AM - 9:30 AM · Zoom"),
        ("Line\nbreak\r\nhere", "Line break here"),
        ("Zero\u{200B}width", "Zero width"),
        ("Family 👨\u{200D}👩\u{200D}👧", "Family 👨\u{200D}👩\u{200D}👧"),
        ("\u{202E}\u{2029}", ""),
    ])
    func displaySafeTitles(input: String, expected: String) {
        #expect(Formatting.displaySafe(input) == expected)
    }

    @Test func declinedAndCanceledEventsAreHidden() {
        #expect(MeetingFilter.includes(isAllDay: false, isCanceled: false, declinedByMe: false))
        #expect(!MeetingFilter.includes(isAllDay: false, isCanceled: false, declinedByMe: true))
        #expect(!MeetingFilter.includes(isAllDay: false, isCanceled: true, declinedByMe: false))
        #expect(!MeetingFilter.includes(isAllDay: true, isCanceled: false, declinedByMe: false))
    }

    @Test func importedShortcutsAreBounded() {
        let command = HotKeyShortcut.carbonCommand
        #expect(!HotKeyShortcut(keyCode: 46, carbonModifiers: command, key: "", keyEquivalent: "m").isValid)
        #expect(!HotKeyShortcut(keyCode: 46, carbonModifiers: command, key: String(repeating: "M", count: 50), keyEquivalent: "m").isValid)
        #expect(!HotKeyShortcut(keyCode: 46, carbonModifiers: command, key: "M", keyEquivalent: "mm").isValid)
        #expect(!HotKeyShortcut(keyCode: 4096, carbonModifiers: command, key: "M", keyEquivalent: "m").isValid)
        #expect(HotKeyShortcut(keyCode: 49, carbonModifiers: command, key: "Space", keyEquivalent: " ").isValid)
    }
}
