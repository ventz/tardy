import AppKit
import Sparkle

/// Sparkle in-app updates. Off unless Info.plist carries SUFeedURL, and always
/// off for `.debug` bundles, so development builds never check.
@MainActor
final class Updater: NSObject, SPUStandardUserDriverDelegate {
    private var controller: SPUStandardUpdaterController?

    var isEnabled: Bool { controller != nil }

    override init() {
        super.init()
        let hasFeed = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil
        let isDebug = Bundle.main.bundleIdentifier?.hasSuffix(".debug") ?? true
        guard hasFeed, !isDebug else { return }
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: self)
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
        DispatchQueue.main.async {
            NSApp.windows.filter { $0.isVisible && $0.className.contains("SU") }.forEach { $0.bringToFront() }
        }
    }

    /// Background (LSUIElement) apps should opt in so scheduled update prompts aren't missed.
    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }
}
