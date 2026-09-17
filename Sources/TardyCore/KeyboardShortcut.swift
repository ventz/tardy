import Foundation

/// The global "open/close the menu" shortcut.
///
/// Stored in Carbon terms (virtual key code + Carbon modifier bits) because that is
/// what RegisterEventHotKey takes, plus what AppKit needs for the menu's matching
/// key equivalent and a label for display.
public struct HotKeyShortcut: Codable, Equatable, Sendable {
    public let keyCode: UInt32
    public let carbonModifiers: UInt32
    /// Display label for the key: "M", "Space", "F5", "←"
    public let key: String
    /// NSMenuItem key equivalent for the key (charactersIgnoringModifiers, lowercased)
    public let keyEquivalent: String

    public init(keyCode: UInt32, carbonModifiers: UInt32, key: String, keyEquivalent: String) {
        self.keyCode = keyCode
        self.carbonModifiers = carbonModifiers
        self.key = key
        self.keyEquivalent = keyEquivalent
    }

    // Carbon modifier bits (Events.h)
    public static let carbonCommand: UInt32 = 1 << 8
    public static let carbonShift: UInt32 = 1 << 9
    public static let carbonOption: UInt32 = 1 << 11
    public static let carbonControl: UInt32 = 1 << 12

    // NSEvent.ModifierFlags raw bits
    public static let cocoaShift: UInt = 1 << 17
    public static let cocoaControl: UInt = 1 << 18
    public static let cocoaOption: UInt = 1 << 19
    public static let cocoaCommand: UInt = 1 << 20

    /// ⇧⌘M
    public static let `default` = HotKeyShortcut(keyCode: 46, carbonModifiers: carbonCommand | carbonShift,
                                                 key: "M", keyEquivalent: "m")

    public static func carbonModifiers(fromCocoa flags: UInt) -> UInt32 {
        var carbon: UInt32 = 0
        if flags & cocoaCommand != 0 { carbon |= carbonCommand }
        if flags & cocoaShift != 0 { carbon |= carbonShift }
        if flags & cocoaOption != 0 { carbon |= carbonOption }
        if flags & cocoaControl != 0 { carbon |= carbonControl }
        return carbon
    }

    public var cocoaModifiers: UInt {
        var flags: UInt = 0
        if carbonModifiers & Self.carbonCommand != 0 { flags |= Self.cocoaCommand }
        if carbonModifiers & Self.carbonShift != 0 { flags |= Self.cocoaShift }
        if carbonModifiers & Self.carbonOption != 0 { flags |= Self.cocoaOption }
        if carbonModifiers & Self.carbonControl != 0 { flags |= Self.cocoaControl }
        return flags
    }

    /// A global shortcut needs ⌘, ⌥ or ⌃: Shift alone would steal ordinary typing.
    /// The label and key equivalent are bounded too, since an imported settings file
    /// is untrusted.
    public var isValid: Bool {
        carbonModifiers & (Self.carbonCommand | Self.carbonOption | Self.carbonControl) != 0
            && keyCode <= 0xFF
            && !key.isEmpty && key.count <= 12
            && keyEquivalent.count <= 1
    }

    /// Apple's order: ⌃⌥⇧⌘ then the key, e.g. "⇧⌘M".
    public var display: String {
        var text = ""
        if carbonModifiers & Self.carbonControl != 0 { text += "⌃" }
        if carbonModifiers & Self.carbonOption != 0 { text += "⌥" }
        if carbonModifiers & Self.carbonShift != 0 { text += "⇧" }
        if carbonModifiers & Self.carbonCommand != 0 { text += "⌘" }
        return text + key
    }
}
