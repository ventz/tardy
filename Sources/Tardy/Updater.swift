import AppKit
import Sparkle

/// Sparkle in-app updates. Off unless Info.plist carries SUFeedURL, and always
/// off for `.debug` bundles, so development builds never check.
@MainActor
final class Updater: NSObject, SPUUpdaterDelegate, SPUStandardUserDriverDelegate {
    private var controller: SPUStandardUpdaterController?
    /// Set when Sparkle has downloaded an update to install on quit; Tardy runs as a
    /// service and rarely quits, so `installIfIdle` installs it at a quiet moment instead.
    private var pendingInstall: (() -> Void)?

    var isEnabled: Bool { controller != nil }

    override init() {
        super.init()
        let hasFeed = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil
        let isDebug = Bundle.main.bundleIdentifier?.hasSuffix(".debug") ?? true
        guard hasFeed, !isDebug else { return }
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self, userDriverDelegate: self)
    }

    var automaticallyChecks: Bool {
        get { controller?.updater.automaticallyChecksForUpdates ?? false }
        set { controller?.updater.automaticallyChecksForUpdates = newValue }
    }

    var lastCheck: Date? { controller?.updater.lastUpdateCheckDate }

    func checkForUpdates() {
        // A menu bar app is never frontmost; bring the update window forward
        NSApp.activate()
        controller?.checkForUpdates(nil)
        bringUpdateWindowsForward()
    }

    /// Runs a background check once the check interval has passed by the wall clock.
    /// Sparkle schedules its own check with an NSTimer, which doesn't count system sleep,
    /// so in a process that runs for days (Run as a service) it can fall days behind.
    /// Called from Tardy's refresh, which runs at least every 10 minutes and on wake.
    func checkIfDue(now: Date = Date()) {
        guard let updater = controller?.updater, updater.automaticallyChecksForUpdates,
              !updater.sessionInProgress, pendingInstall == nil else { return }
        if let last = updater.lastUpdateCheckDate, now.timeIntervalSince(last) < updater.updateCheckInterval { return }
        updater.checkForUpdatesInBackground()
    }

    /// Installs a downloaded update and relaunches, unless `isBusy` says now is a bad time.
    func installIfIdle(isBusy: Bool) {
        guard let install = pendingInstall, !isBusy else { return }
        pendingInstall = nil
        install()
    }

    // MARK: SPUUpdaterDelegate

    nonisolated func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem,
                             immediateInstallationBlock immediateInstallHandler: @escaping () -> Void) -> Bool {
        MainActor.assumeIsolated { pendingInstall = immediateInstallHandler }
        return true
    }

    // MARK: SPUStandardUserDriverDelegate

    /// Background (LSUIElement) apps should opt in so scheduled update prompts aren't missed.
    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    // Sparkle's windows open at the normal level, under the floating Settings window
    // (bringToFront) and under the app the user is in; each one is brought forward as it appears.
    nonisolated func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem,
                                                               state: SPUUserUpdateState) {
        MainActor.assumeIsolated { bringUpdateWindowsForward() }
    }

    nonisolated func standardUserDriverWillShowModalAlert() {
        MainActor.assumeIsolated { bringUpdateWindowsForward() }
    }

    /// The windows appear after these calls return, so look on the next passes too.
    private func bringUpdateWindowsForward() {
        for delay in [0.0, 0.2, 0.6] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                NSApp.windows
                    .filter { $0.isVisible && ($0.className.contains("SU") || $0.className.contains("SPU")) }
                    .forEach { $0.bringToFront() }
            }
        }
    }
}
