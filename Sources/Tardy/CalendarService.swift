import AppKit
import EventKit
import TardyCore

struct CalendarGroup: Equatable, Identifiable {
    struct Entry: Equatable, Identifiable {
        let id: String
        let title: String
    }
    let source: String
    let calendars: [Entry]

    var id: String { source }
}

@MainActor
final class CalendarService {
    let store = EKEventStore()
    private(set) var meetings: [Meeting] = []
    private(set) var lastFetch = Date.distantPast

    var hasAccess: Bool { EKEventStore.authorizationStatus(for: .event) == .fullAccess }

    func requestAccess() async -> Bool {
        if hasAccess { return true }
        return (try? await store.requestFullAccessToEvents()) ?? false
    }

    /// Forces the next tick to refetch.
    func invalidate() { lastFetch = .distantPast }

    /// Calendars grouped by account, mirroring Calendar.app's sidebar.
    func groups() -> [CalendarGroup] {
        var seen = Set<String>()
        return store.sources
            .filter { seen.insert($0.sourceIdentifier).inserted }
            .compactMap { source -> CalendarGroup? in
                let calendars = source.calendars(for: .event)
                    .map { CalendarGroup.Entry(id: $0.calendarIdentifier, title: $0.title) }
                    .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
                return calendars.isEmpty ? nil : CalendarGroup(source: source.title, calendars: calendars)
            }
            .sorted { $0.source.localizedCaseInsensitiveCompare($1.source) == .orderedAscending }
    }

    /// Today's timed events, from 10 minutes ago (so LATE meetings survive a refresh)
    /// to the end of the day.
    func refresh(disabled: Set<String>, now: Date = Date()) {
        lastFetch = now
        guard hasAccess else { meetings = []; return }
        let calendar = Calendar.current
        let start = now.addingTimeInterval(-10 * 60)
        let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!.addingTimeInterval(-1)
        let calendars = store.calendars(for: .event).filter { !disabled.contains($0.calendarIdentifier) }
        guard !calendars.isEmpty else { meetings = []; return }

        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: calendars)
        meetings = store.events(matching: predicate)
            .filter { !$0.isAllDay }
            .map { event in
                // eventIdentifier is shared by every occurrence of a recurring event
                let id = "\(event.eventIdentifier ?? UUID().uuidString)@\(event.startDate.timeIntervalSince1970)"
                return Meeting(
                    id: id,
                    title: event.title?.isEmpty == false ? event.title! : "(No title)",
                    start: event.startDate,
                    end: event.endDate,
                    calendarID: event.calendar.calendarIdentifier,
                    link: MeetingLinks.extract(location: event.location, url: event.url?.absoluteString, notes: event.notes)
                )
            }
            .sorted { $0.start < $1.start }
    }
}
