import Testing
@testable import TardyCore

@Suite struct HotKeyShortcutTests {
    @Test func defaultIsShiftCommandM() {
        #expect(HotKeyShortcut.default.display == "⇧⌘M")
        #expect(HotKeyShortcut.default.isValid)
    }

    @Test func displayUsesAppleModifierOrder() {
        let all = HotKeyShortcut.carbonCommand | HotKeyShortcut.carbonShift | HotKeyShortcut.carbonOption | HotKeyShortcut.carbonControl
        #expect(HotKeyShortcut(keyCode: 40, carbonModifiers: all, key: "K", keyEquivalent: "k").display == "⌃⌥⇧⌘K")
    }

    @Test func requiresCommandOptionOrControl() {
        #expect(!HotKeyShortcut(keyCode: 46, carbonModifiers: HotKeyShortcut.carbonShift, key: "M", keyEquivalent: "m").isValid)
        #expect(!HotKeyShortcut(keyCode: 46, carbonModifiers: 0, key: "M", keyEquivalent: "m").isValid)
        #expect(HotKeyShortcut(keyCode: 46, carbonModifiers: HotKeyShortcut.carbonControl, key: "M", keyEquivalent: "m").isValid)
    }

    @Test func cocoaAndCarbonModifiersRoundTrip() {
        let cocoa = HotKeyShortcut.cocoaCommand | HotKeyShortcut.cocoaOption
        let carbon = HotKeyShortcut.carbonModifiers(fromCocoa: cocoa | (1 << 16)) // caps lock ignored
        #expect(carbon == HotKeyShortcut.carbonCommand | HotKeyShortcut.carbonOption)
        #expect(HotKeyShortcut(keyCode: 1, carbonModifiers: carbon, key: "S", keyEquivalent: "s").cocoaModifiers == cocoa)
    }
}
