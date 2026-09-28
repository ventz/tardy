import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: AppController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard Service.claimInstance() else {
            NSApp.terminate(nil)
            return
        }
        let controller = AppController()
        self.controller = controller
        controller.start()
        // A service handover (turning Run as a service on or off in Settings) restarts
        // Tardy; reopen the window the user was in
        if UserDefaults.standard.bool(forKey: Service.reopenSettingsKey) {
            UserDefaults.standard.removeObject(forKey: Service.reopenSettingsKey)
            controller.showSettings()
        }
    }

    /// Opening Tardy while the service copy runs only reopens that copy -- including
    /// Sparkle's relaunch after an update and a local install (`ditto` + `open`).
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        Service.restartIfUpdated()
        return true
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        Service.restartIfUpdated()
    }
}

func debugLog(_ message: @autoclosure () -> String) {
    if ProcessInfo.processInfo.environment["TARDY_DEBUG"] == "1" {
        FileHandle.standardError.write(Data((message() + "\n").utf8))
    }
}

extension NSWindow {
    /// Brings a window of this menu bar app in front of the app the user is in.
    ///
    /// Since macOS 14 activation is cooperative: a background menu bar app's activation
    /// request -- `activate()` and even `activate(ignoringOtherApps:)` -- is ignored, and
    /// `orderFrontRegardless` then leaves the window *under* the active app's front
    /// window (seen on macOS 27, 2026-09-28). So the window floats above other apps'
    /// windows until the user clicks into it (Tardy activates) or switches to another
    /// app, then returns to the normal level.
    func bringToFront() {
        FloatUntilSettled.add(self)
        orderFrontRegardless()
        makeKey()
        NSApp.activate()
    }
}

@MainActor
private enum FloatUntilSettled {
    private static let windows = NSHashTable<NSWindow>.weakObjects()
    private static var observers: [(NotificationCenter, NSObjectProtocol)] = []

    static func add(_ window: NSWindow) {
        window.level = .floating
        windows.add(window)
        guard observers.isEmpty else { return }
        let app = NotificationCenter.default
        let workspace = NSWorkspace.shared.notificationCenter
        observers = [
            (app, app.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { settle() }
            }),
            (workspace, workspace.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil,
                                              queue: .main) { note in
                let activated = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                MainActor.assumeIsolated {
                    if activated?.processIdentifier != ProcessInfo.processInfo.processIdentifier { settle() }
                }
            }),
        ]
    }

    private static func settle() {
        windows.allObjects.forEach { $0.level = .normal }
        windows.removeAllObjects()
        observers.forEach { $0.0.removeObserver($0.1) }
        observers = []
    }
}
