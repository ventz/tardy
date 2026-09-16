import Foundation

/// Per-meeting escalation. Raw values order the priority used to pick the
/// meeting that drives the menu bar.
public enum AlertState: Int, Comparable, Sendable {
    case idle = 1
    case alert15      // T-15: sound, notification, Join/Dismiss
    case countdown    // T-5: sound, notification, live countdown
    case alarm        // T-1: three beeps
    case late         // T-0: flashing LATE counter

    public static func < (lhs: AlertState, rhs: AlertState) -> Bool { lhs.rawValue < rhs.rawValue }

    public static func forSecondsUntil(_ seconds: TimeInterval) -> AlertState {
        switch seconds {
        case ...0: return .late
        case ...Timing.alarm: return .alarm
        case ...Timing.countdown: return .countdown
        case ...Timing.alert: return .alert15
        default: return .idle
        }
    }

    public var hidesDateIcon: Bool { self == .countdown || self == .alarm || self == .late }
}

public enum Timing {
    public static let alarm: TimeInterval = 60
    public static let countdown: TimeInterval = 5 * 60
    public static let alert: TimeInterval = 15 * 60
    /// The menu bar shows the next meeting's time once it is this close.
    public static let showTime: TimeInterval = 30 * 60
    /// LATE auto-dismisses after this long.
    public static let lateAutoDismiss: TimeInterval = 5 * 60
    /// Idle wakeup ceiling; state changes themselves are scheduled exactly.
    public static let maxTick: TimeInterval = 10 * 60
    /// EventKit change notifications do the real work; this is a safety net.
    public static let safetyRefresh: TimeInterval = 10 * 60
    public static let soundDebounce: TimeInterval = 5
}

public enum Primary {
    /// Highest alert state wins; within a state, the soonest start.
    public static func select(_ meetings: [Meeting], states: [String: AlertState], now: Date) -> Meeting? {
        meetings.max { a, b in
            let sa = states[a.id] ?? .idle, sb = states[b.id] ?? .idle
            if sa != sb { return sa < sb }
            return a.start.timeIntervalSince(now) > b.start.timeIntervalSince(now)
        }
    }
}
