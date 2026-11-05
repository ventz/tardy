import Foundation

/// When sound alerts may play on one day of the week.
public struct DayHours: Codable, Equatable, Hashable, Sendable {
    public static let minutesPerDay = 24 * 60

    /// False: the whole day is quiet.
    public var alerts: Bool
    /// Minutes after midnight; alerts play for meetings starting at or after `start`
    /// and before `end` (24:00 is `minutesPerDay`).
    public private(set) var start: Int
    public private(set) var end: Int

    public init(alerts: Bool, start: Int, end: Int) {
        self.alerts = alerts
        self.start = start
        self.end = end
        normalize()
    }

    public static let workday = DayHours(alerts: true, start: 8 * 60, end: 18 * 60)
    public static let quiet = DayHours(alerts: false, start: 8 * 60, end: 18 * 60)

    /// Moving the start to or past the end pushes the end out rather than refusing.
    public mutating func setStart(_ minutes: Int) {
        start = minutes
        if end <= start { end = start + 30 }
        normalize()
    }

    /// An end at or before the start is ignored.
    public mutating func setEnd(_ minutes: Int) {
        guard minutes > start else { return }
        end = minutes
        normalize()
    }

    public func allows(minuteOfDay minute: Int) -> Bool {
        alerts && start <= minute && minute < end
    }

    private mutating func normalize() {
        start = start.clamped(to: 0...(Self.minutesPerDay - 1))
        end = end.clamped(to: (start + 1)...Self.minutesPerDay)
    }

    private enum CodingKeys: String, CodingKey { case alerts, start, end }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Self.workday
        self.init(alerts: try c.decodeIfPresent(Bool.self, forKey: .alerts) ?? d.alerts,
                  start: try c.decodeIfPresent(Int.self, forKey: .start) ?? d.start,
                  end: try c.decodeIfPresent(Int.self, forKey: .end) ?? d.end)
    }
}

/// Quiet hours (Settings > Alerts > Alert hours): meetings that start outside the
/// day's alert hours make no sound. Default: 8 AM to 6 PM on weekdays, none on weekends.
///
/// Judged by the meeting's start, not the clock, so the 7:50 alert for an 8:00
/// meeting still plays and a 6:30 PM meeting stays quiet at 6:20.
///
/// Each schedule keeps its own hours, so switching between them never overwrites
/// anything and the hours Settings shows are always the ones that apply.
public struct QuietHours: Codable, Equatable, Sendable {
    public enum Schedule: String, Codable, CaseIterable, Sendable {
        case everyDay, weekdaysWeekend, eachDay
    }

    /// Which stored hours a Settings row edits.
    public enum Slot: Hashable, Sendable {
        case everyDay, weekdays, weekend
        /// `Calendar` weekday, 1 = Sunday … 7 = Saturday.
        case day(Int)
    }

    /// A row in Settings.
    public struct Group: Equatable, Sendable {
        public let title: String
        public let slot: Slot
    }

    public static let weekdays = [2, 3, 4, 5, 6]
    public static let weekend = [7, 1]

    public var enabled = true
    /// Also hold back the notification, not just the sounds.
    public var includeNotifications = false
    public var schedule: Schedule = .weekdaysWeekend
    public private(set) var everyDay: DayHours = .workday
    public private(set) var weekdayHours: DayHours = .workday
    public private(set) var weekendHours: DayHours = .quiet
    /// Indexed by `Calendar` weekday - 1 (0 = Sunday).
    public private(set) var days: [DayHours] = [.quiet, .workday, .workday, .workday, .workday, .workday, .quiet]

    public init() {}

    public init(enabled: Bool, includeNotifications: Bool = false, schedule: Schedule) {
        self.enabled = enabled
        self.includeNotifications = includeNotifications
        self.schedule = schedule
    }

    /// The hours that apply on `weekday` under the current schedule.
    public func hours(weekday: Int) -> DayHours {
        let weekday = weekday.clamped(to: 1...7)
        switch schedule {
        case .everyDay: return everyDay
        case .weekdaysWeekend: return Self.weekend.contains(weekday) ? weekendHours : weekdayHours
        case .eachDay: return days[weekday - 1]
        }
    }

    /// The rows Settings shows for the current schedule, Monday first.
    public func groups(dayNames: [String] = Calendar.current.weekdaySymbols) -> [Group] {
        switch schedule {
        case .everyDay: [Group(title: "Every day", slot: .everyDay)]
        case .weekdaysWeekend: [Group(title: "Weekdays", slot: .weekdays), Group(title: "Weekends", slot: .weekend)]
        case .eachDay: (Self.weekdays + Self.weekend).map { Group(title: dayNames[$0 - 1], slot: .day($0)) }
        }
    }

    public func hours(for group: Group) -> DayHours {
        switch group.slot {
        case .everyDay: everyDay
        case .weekdays: weekdayHours
        case .weekend: weekendHours
        case .day(let weekday): days[weekday.clamped(to: 1...7) - 1]
        }
    }

    public mutating func set(_ hours: DayHours, for group: Group) {
        switch group.slot {
        case .everyDay: everyDay = hours
        case .weekdays: weekdayHours = hours
        case .weekend: weekendHours = hours
        case .day(let weekday): days[weekday.clamped(to: 1...7) - 1] = hours
        }
    }

    /// Whether a meeting starting at `date` is silenced.
    public func silences(_ date: Date, calendar: Calendar = .current) -> Bool {
        guard enabled else { return false }
        let parts = calendar.dateComponents([.weekday, .hour, .minute], from: date)
        guard let weekday = parts.weekday, let hour = parts.hour, let minute = parts.minute else { return false }
        return !hours(weekday: weekday).allows(minuteOfDay: hour * 60 + minute)
    }

    private enum CodingKeys: String, CodingKey {
        case enabled, includeNotifications, schedule, everyDay, weekdays, weekend, days
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(enabled, forKey: .enabled)
        try c.encode(includeNotifications, forKey: .includeNotifications)
        try c.encode(schedule, forKey: .schedule)
        try c.encode(everyDay, forKey: .everyDay)
        try c.encode(weekdayHours, forKey: .weekdays)
        try c.encode(weekendHours, forKey: .weekend)
        try c.encode(days, forKey: .days)
    }

    /// Missing or unreadable keys take their defaults; a `days` list that isn't seven long is ignored.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = QuietHours()
        enabled = (try? c.decodeIfPresent(Bool.self, forKey: .enabled)) ?? d.enabled
        includeNotifications = (try? c.decodeIfPresent(Bool.self, forKey: .includeNotifications)) ?? d.includeNotifications
        schedule = (try? c.decodeIfPresent(Schedule.self, forKey: .schedule)) ?? d.schedule
        everyDay = (try? c.decodeIfPresent(DayHours.self, forKey: .everyDay)) ?? d.everyDay
        weekdayHours = (try? c.decodeIfPresent(DayHours.self, forKey: .weekdays)) ?? d.weekdayHours
        weekendHours = (try? c.decodeIfPresent(DayHours.self, forKey: .weekend)) ?? d.weekendHours
        let days = (try? c.decodeIfPresent([DayHours].self, forKey: .days)) ?? d.days
        self.days = days.count == 7 ? days : d.days
    }
}
