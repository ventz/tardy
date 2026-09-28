import Foundation

/// One sound alert before a meeting: a notification plus `beeps` sounds.
public struct SoundAlert: Codable, Equatable, Hashable, Sendable {
    public var minutes: Int
    public var beeps: Int

    public init(minutes: Int, beeps: Int) {
        self.minutes = minutes
        self.beeps = beeps
    }
}

/// The user's sound alert schedule (Settings > Alerts).
///
/// Independent of `AlertState`, which only drives the menu bar. Alerts are kept
/// sorted earliest first (most minutes before), so with `progressive` on the
/// first alert beeps once, the second twice, and so on.
public struct AlertSounds: Codable, Equatable, Sendable {
    public static let minuteRange = 1...60
    public static let beepRange = 1...5
    public static let maxAlerts = 5

    public var progressive = true
    public private(set) var alerts: [SoundAlert] = [
        SoundAlert(minutes: 10, beeps: 1),
        SoundAlert(minutes: 5, beeps: 2),
        SoundAlert(minutes: 2, beeps: 3),
    ]

    public init() {}

    public init(progressive: Bool, alerts: [SoundAlert]) {
        self.progressive = progressive
        self.alerts = Self.normalized(alerts)
    }

    /// Sounds for the alert at `index` (in `alerts` order).
    public func beeps(at index: Int) -> Int {
        progressive ? min(index + 1, Self.beepRange.upperBound) : alerts[index].beeps
    }

    public mutating func setAlerts(_ new: [SoundAlert]) {
        alerts = Self.normalized(new)
    }

    /// A new alert halfway between the last one and the meeting, or before the first
    /// when the last is already at 1 minute; nil at the limit or with no free minute.
    public func proposedAlert() -> SoundAlert? {
        guard alerts.count < Self.maxAlerts else { return nil }
        let taken = Set(alerts.map(\.minutes))
        let last = alerts.last?.minutes ?? 10
        let candidates = [last / 2, last - 1] + Array(Self.minuteRange).reversed()
        guard let minutes = candidates.first(where: { Self.minuteRange.contains($0) && !taken.contains($0) })
        else { return nil }
        return SoundAlert(minutes: minutes, beeps: min(alerts.count + 1, Self.beepRange.upperBound))
    }

    /// Clamped, one alert per minute, earliest first, at most `maxAlerts`, at least one.
    static func normalized(_ alerts: [SoundAlert]) -> [SoundAlert] {
        var seen = Set<Int>()
        let clean = alerts
            .map { SoundAlert(minutes: $0.minutes.clamped(to: minuteRange), beeps: $0.beeps.clamped(to: beepRange)) }
            .filter { seen.insert($0.minutes).inserted }
            .sorted { $0.minutes > $1.minutes }
        return clean.isEmpty ? AlertSounds().alerts : Array(clean.prefix(maxAlerts))
    }

    /// The alert to play now, given the seconds until the meeting and the alert
    /// minutes already handled for it.
    ///
    /// Only the most recently passed alert plays, so starting Tardy (or waking the
    /// Mac) at T-3 plays the 5-minute alert once instead of every earlier one.
    /// `handled` gains every passed alert either way. Nothing plays once the
    /// meeting has started.
    public func due(secondsUntil until: TimeInterval, handled: inout Set<Int>) -> (index: Int, alert: SoundAlert)? {
        guard until > 0 else { return nil }
        var latest: (Int, SoundAlert)?
        for (index, alert) in alerts.enumerated() where until <= TimeInterval(alert.minutes * 60) {
            if handled.insert(alert.minutes).inserted { latest = (index, alert) } else { latest = nil }
        }
        return latest
    }

    private enum CodingKeys: String, CodingKey { case progressive, alerts }

    /// Missing keys take their defaults; values from a file are clamped.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AlertSounds()
        progressive = try c.decodeIfPresent(Bool.self, forKey: .progressive) ?? d.progressive
        alerts = Self.normalized(try c.decodeIfPresent([SoundAlert].self, forKey: .alerts) ?? d.alerts)
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self { min(max(self, range.lowerBound), range.upperBound) }
}
