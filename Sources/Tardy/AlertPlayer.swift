import AppKit
import TardyCore
import UserNotifications

@MainActor
final class AlertPlayer: NSObject, UNUserNotificationCenterDelegate {
    private static let sonar = "/System/Library/PrivateFrameworks/ToneLibrary.framework/Versions/A/Resources/Ringtones/Sonar.m4r"
    private var lastSound = Date.distantPast
    /// NSSound stops when released, so keep playing sounds alive.
    private var playing: [NSSound] = []
    var muted = false

    func requestNotificationPermission() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// Debounced so overlapping meetings don't stack sounds.
    private func shouldPlay() -> Bool {
        guard !muted, Date().timeIntervalSince(lastSound) >= Timing.soundDebounce else { return false }
        lastSound = Date()
        return true
    }

    private func play() {
        guard let sound = NSSound(contentsOfFile: Self.sonar, byReference: true) ?? NSSound(named: "Glass") else { return }
        playing.removeAll { !$0.isPlaying }
        playing.append(sound)
        sound.play()
    }

    func chime() {
        if shouldPlay() { play() }
    }

    func beeps(count: Int = 3, interval: TimeInterval = 0.4) {
        guard shouldPlay() else { return }
        for i in 0..<count {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * interval) { [weak self] in
                self?.play()
            }
        }
    }

    func notify(_ title: String, _ body: String) {
        guard !muted else { return }
        let content = UNMutableNotificationContent()
        content.title = String(title.prefix(100))
        content.body = String(body.prefix(200))
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list])
    }
}
