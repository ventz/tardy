import Foundation

/// A timed (non all-day) calendar event for today.
public struct Meeting: Equatable, Sendable {
    public let id: String
    public let title: String
    public let start: Date
    public let end: Date
    public let calendarID: String
    public let link: MeetingLink?

    public init(id: String, title: String, start: Date, end: Date, calendarID: String, link: MeetingLink?) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.calendarID = calendarID
        self.link = link
    }
}

/// Which calendar events become meetings. Declined and canceled invites are left out
/// entirely: anyone can put an invite on the calendar, and one you've turned down
/// shouldn't alert you or offer a Join button.
public enum MeetingFilter {
    public static func includes(isAllDay: Bool, isCanceled: Bool, declinedByMe: Bool) -> Bool {
        !isAllDay && !isCanceled && !declinedByMe
    }
}

public enum MeetingKind: String, Codable, Sendable {
    case personal
    case work
}
