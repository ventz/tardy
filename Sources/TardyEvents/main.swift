// tardy-events: today's remaining meetings as JSON, for the Claude Code mod in claude-code/.
// Uses TardyCore, so the filter, title cleanup and meeting-link rules are the app's own.
// Calendar choices (watched, Work or Personal) come from the release app's settings,
// `defaults read net.vpetkov.tardy`, even in a debug build.

import EventKit
import Foundation
import TardyCore

struct Link: Encodable { let url: String; let platform: String }

struct Row: Encodable {
    let id: String
    let title: String
    let start: Double
    let end: Double
    /// Preformatted here, in the host's time zone and locale: `2:30-3:00pm`, `3:00pm`.
    let range: String
    let until: String
    let kind: String
    let link: Link?
}

func fail(_ message: String, _ code: Int32) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(code)
}

let store = EKEventStore()
if EKEventStore.authorizationStatus(for: .event) != .fullAccess {
    let done = DispatchSemaphore(value: 0)
    var granted = false
    store.requestFullAccessToEvents { ok, _ in granted = ok; done.signal() }
    done.wait()
    if !granted {
        fail("no calendar access: allow it in System Settings > Privacy & Security > Calendars", 2)
    }
}

let tardy = UserDefaults(suiteName: "net.vpetkov.tardy")
let disabled = Set(tardy?.stringArray(forKey: "disabledCalendarIDs") ?? [])
let work = Set(tardy?.stringArray(forKey: "workCalendarIDs") ?? [])

let now = Date()
let calendar = Calendar.current
// From 10 minutes ago, so a LATE meeting survives a refresh, to the end of the day.
let from = now.addingTimeInterval(-10 * 60)
let to = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!.addingTimeInterval(-1)
let calendars = store.calendars(for: .event).filter { !disabled.contains($0.calendarIdentifier) }

var rows: [Row] = []
if !calendars.isEmpty {
    let predicate = store.predicateForEvents(withStart: from, end: to, calendars: calendars)
    rows = store.events(matching: predicate)
        .filter { event in
            MeetingFilter.includes(
                isAllDay: event.isAllDay,
                isCanceled: event.status == .canceled,
                declinedByMe: event.attendees?.first(where: \.isCurrentUser)?.participantStatus == .declined)
        }
        .sorted { $0.startDate < $1.startDate }
        .map { event in
            let title = Formatting.displaySafe(event.title ?? "")
            let link = MeetingLinks.extract(location: event.location, url: event.url?.absoluteString, notes: event.notes)
                .flatMap { MeetingLinks.isSafeToOpen($0.url) ? Link(url: $0.url.absoluteString, platform: $0.platform) : nil }
            return Row(
                id: "\(event.eventIdentifier ?? UUID().uuidString)@\(event.startDate.timeIntervalSince1970)",
                title: title.isEmpty ? "(No title)" : title,
                start: (event.startDate.timeIntervalSince1970 * 1000).rounded(),
                end: (event.endDate.timeIntervalSince1970 * 1000).rounded(),
                range: Formatting.shortRange(event.startDate, event.endDate),
                until: Formatting.endTime(event.endDate),
                kind: work.contains(event.calendar.calendarIdentifier) ? "work" : "personal",
                link: link)
        }
}

let data = try JSONEncoder().encode(rows)
FileHandle.standardOutput.write(data)
FileHandle.standardOutput.write(Data("\n".utf8))
