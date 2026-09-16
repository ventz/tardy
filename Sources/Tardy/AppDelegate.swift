import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: AppController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let controller = AppController()
        self.controller = controller
        controller.start()
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
    /// Since macOS 14 activation is cooperative: `NSApp.activate()` is only a request,
    /// and one made by a background menu bar app -- especially while its menu is still
    /// closing -- is often ignored, leaving the window behind the frontmost app.
    /// `orderFrontRegardless` puts it on top even while Tardy isn't active; activating
    /// afterwards gives it keyboard focus when macOS allows.
    func bringToFront() {
        orderFrontRegardless()
        NSApp.activate()
        makeKeyAndOrderFront(nil)
    }
}
