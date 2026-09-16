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

public enum MeetingKind: String, Codable, Sendable {
    case personal
    case work
}
