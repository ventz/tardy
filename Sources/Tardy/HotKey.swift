import Carbon.HIToolbox
import TardyCore

/// One global hotkey via Carbon RegisterEventHotKey (no Accessibility permission).
///
/// While registered, macOS swallows the keystroke system-wide and delivers the
/// event only when the app's event loop is free -- never while a menu is
/// tracking. Suspend it while the menu is open (or while recording a new
/// shortcut) so the key reaches the app itself.
@MainActor
final class HotKey {
    private static var current: HotKey?
    private let action: () -> Void
    private(set) var shortcut: HotKeyShortcut?
    private var ref: EventHotKeyRef?
    private var suspended = false

    init(action: @escaping () -> Void) {
        self.action = action
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            MainActor.assumeIsolated { HotKey.current?.action() }
            return noErr
        }, 1, &spec, nil, nil)
        HotKey.current = self
    }

    /// Switches to `shortcut` (nil turns the hotkey off). If macOS refuses it --
    /// another app registered the same combination -- the previous one is restored
    /// and this returns false.
    @discardableResult
    func set(_ shortcut: HotKeyShortcut?) -> Bool {
        let previous = self.shortcut
        unregister()
        self.shortcut = shortcut
        guard shortcut != nil, !suspended else { return true }
        if register() { return true }
        self.shortcut = previous
        _ = register()
        return false
    }

    func suspend() {
        suspended = true
        unregister()
    }

    func resume() {
        suspended = false
        _ = register()
    }

    private func register() -> Bool {
        guard ref == nil, let shortcut else { return ref != nil }
        let id = EventHotKeyID(signature: OSType(0x7461_7264), id: 1) // 'tard'
        var newRef: EventHotKeyRef?
        guard RegisterEventHotKey(shortcut.keyCode, shortcut.carbonModifiers, id, GetApplicationEventTarget(), 0, &newRef) == noErr else {
            return false
        }
        ref = newRef
        return true
    }

    private func unregister() {
        guard let ref else { return }
        UnregisterEventHotKey(ref)
        self.ref = nil
    }
}
