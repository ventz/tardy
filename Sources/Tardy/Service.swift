import AppKit
import ServiceManagement

/// "Run as a service": a launchd agent (Contents/Library/LaunchAgents, KeepAlive)
/// that starts Tardy at login and relaunches it whenever it quits, including an
/// accidental Quit. Off, "Launch at login" is a plain login item.
///
/// Only one Tardy runs at a time. With the service on, the copy launchd runs is the
/// one that stays: a copy started any other way (Finder, a Sparkle relaunch) hands
/// over to launchd and exits. Turning the service off stops launchd's copy
/// (unregistering boots the job out), so it first launches a successor that waits
/// for it to go.
@MainActor
enum Service {
    static let label = (Bundle.main.bundleIdentifier ?? "net.vpetkov.tardy") + ".agent"
    private static let successorKey = "TARDY_SUCCESSOR"
    static let reopenSettingsKey = "reopenSettingsAfterHandover"
    private static let agent = SMAppService.agent(plistName: label + ".plist")

    static var isEnabled: Bool { agent.status == .enabled }
    /// The user turned Tardy off in System Settings > General > Login Items.
    static var needsApproval: Bool { agent.status == .requiresApproval }

    static func openLoginItemsSettings() { SMAppService.openSystemSettingsLoginItems() }
    static var launchAtLogin: Bool { isEnabled || SMAppService.mainApp.status == .enabled }

    /// launchd names the job in the environment of the processes it starts.
    static var isManagedByLaunchd: Bool {
        ProcessInfo.processInfo.environment["XPC_SERVICE_NAME"] == label
    }

    /// The service includes launching at login, so the login item is dropped while it
    /// is on (both would start a copy at login) and restored when it is turned off.
    static func setEnabled(_ enable: Bool) throws {
        if enable {
            try agent.register()
            try? SMAppService.mainApp.unregister()
            handOverIfNeeded()
        } else if isManagedByLaunchd {
            try? SMAppService.mainApp.register()
            let config = NSWorkspace.OpenConfiguration()
            config.createsNewApplicationInstance = true
            config.activates = false
            config.environment = [successorKey: "1"]
            NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: config) { _, error in
                Task { @MainActor in
                    if let error { NSLog("Tardy: could not start a successor: \(error)") }
                    // Stops this process too
                    do { try agent.unregister() } catch { NSLog("Tardy: could not stop the service: \(error)") }
                }
            }
        } else {
            try? SMAppService.mainApp.register()
            try agent.unregister()
        }
    }

    static func setLaunchAtLogin(_ enable: Bool) throws {
        if enable { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
    }

    /// Called at launch before anything else. Returns false if this copy should exit.
    static func claimInstance() -> Bool {
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
            .filter { $0 != .current }
        if ProcessInfo.processInfo.environment[successorKey] == "1" {
            // Launched by a service copy that is turning the service off
            waitUntilGone(others, timeout: 10)
            return others.allSatisfy(\.isTerminated)
        }
        if handOverIfNeeded() { return false }
        guard !others.isEmpty else { return true }
        guard isManagedByLaunchd else { return false } // already running
        // launchd's copy wins; the other must be gone before the hotkey is registered
        others.forEach { $0.terminate() }
        waitUntilGone(others, timeout: 5)
        others.filter { !$0.isTerminated }.forEach { $0.forceTerminate() }
        return true
    }

    private static func waitUntilGone(_ apps: [NSRunningApplication], timeout: TimeInterval) {
        let deadline = Date().addingTimeInterval(timeout)
        while apps.contains(where: { !$0.isTerminated }) && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
    }

    /// With the service on, a copy launchd didn't start asks launchd to start its
    /// own and quits. Returns true when it did. `-k` restarts a copy that is already
    /// running: after a Sparkle update launchd may have relaunched the old version
    /// before the new one was in place, and Sparkle's relaunch must replace it.
    @discardableResult
    private static func handOverIfNeeded() -> Bool {
        guard isEnabled, !isManagedByLaunchd else { return false }
        let kickstart = Process()
        kickstart.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        kickstart.arguments = ["kickstart", "-k", "gui/\(getuid())/\(label)"]
        do {
            try kickstart.run()
            kickstart.waitUntilExit()
        } catch {
            NSLog("Tardy: could not start the service: \(error)")
            return false
        }
        guard kickstart.terminationStatus == 0 else {
            NSLog("Tardy: launchctl kickstart exited \(kickstart.terminationStatus)")
            return false
        }
        debugLog("[service] handed over to \(label)")
        NSApp.terminate(nil)
        return true
    }
}
