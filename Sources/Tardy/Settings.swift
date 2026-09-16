import Combine
import Foundation
import TardyCore

/// User preferences, persisted to UserDefaults (`defaults read net.vpetkov.tardy`).
/// Observable so the Settings window and the menu bar stay in sync.
@MainActor
final class SettingsStore: ObservableObject {
    private let defaults = UserDefaults.standard

    private enum Key {
        static let disabledCalendars = "disabledCalendarIDs"
        static let workCalendars = "workCalendarIDs"
        static let clock = "clock"
        static let mute = "muteSounds"
        static let didRegisterLoginItem = "didRegisterLoginItem"
        static let shortcut = "menuShortcut"
        static let shortcutEnabled = "menuShortcutEnabled"
    }

    /// Stored as *disabled*, so a calendar added to the Mac Calendar app later is watched automatically.
    @Published var disabledCalendarIDs: Set<String> {
        didSet { defaults.set(disabledCalendarIDs.sorted(), forKey: Key.disabledCalendars) }
    }

    /// Work calendars (blue); everything else is Personal (red).
    @Published var workCalendarIDs: Set<String> {
        didSet { defaults.set(workCalendarIDs.sorted(), forKey: Key.workCalendars) }
    }

    @Published var clock: ClockOptions {
        didSet { defaults.set(try? JSONEncoder().encode(clock), forKey: Key.clock) }
    }

    @Published var muteSounds: Bool {
        didSet { defaults.set(muteSounds, forKey: Key.mute) }
    }

    /// The global shortcut that opens and closes the menu.
    @Published var shortcut: HotKeyShortcut {
        didSet { defaults.set(try? JSONEncoder().encode(shortcut), forKey: Key.shortcut) }
    }

    @Published var shortcutEnabled: Bool {
        didSet { defaults.set(shortcutEnabled, forKey: Key.shortcutEnabled) }
    }

    /// State, not a setting: never exported, never reset.
    var didRegisterLoginItem: Bool {
        get { defaults.bool(forKey: Key.didRegisterLoginItem) }
        set { defaults.set(newValue, forKey: Key.didRegisterLoginItem) }
    }

    init() {
        disabledCalendarIDs = Set(defaults.stringArray(forKey: Key.disabledCalendars) ?? [])
        workCalendarIDs = Set(defaults.stringArray(forKey: Key.workCalendars) ?? [])
        clock = defaults.data(forKey: Key.clock).flatMap { try? JSONDecoder().decode(ClockOptions.self, from: $0) }
            ?? ClockOptions()
        muteSounds = defaults.bool(forKey: Key.mute)
        shortcut = defaults.data(forKey: Key.shortcut).flatMap { try? JSONDecoder().decode(HotKeyShortcut.self, from: $0) }
            ?? .default
        shortcutEnabled = defaults.object(forKey: Key.shortcutEnabled) as? Bool ?? true
    }

    func kind(ofCalendar id: String) -> MeetingKind {
        workCalendarIDs.contains(id) ? .work : .personal
    }

    func snapshot(calendars: [CalendarRef]) -> SettingsSnapshot {
        SettingsSnapshot(muteSounds: muteSounds, clock: clock, calendars: calendars,
                         disabled: disabledCalendarIDs, work: workCalendarIDs,
                         shortcut: .init(enabled: shortcutEnabled, shortcut: shortcut))
    }

    /// Replaces every setting with the file's; returns calendars that had no match here.
    func apply(_ snapshot: SettingsSnapshot, calendars: [CalendarRef]) -> [String] {
        let resolved = snapshot.resolve(against: calendars)
        muteSounds = snapshot.muteSounds
        clock = snapshot.clock
        disabledCalendarIDs = resolved.disabled
        workCalendarIDs = resolved.work
        if let imported = snapshot.shortcut, imported.shortcut.isValid {
            shortcut = imported.shortcut
            shortcutEnabled = imported.enabled
        }
        return resolved.unmatched
    }

    func resetToDefaults() {
        muteSounds = false
        clock = ClockOptions()
        disabledCalendarIDs = []
        workCalendarIDs = []
        shortcut = .default
        shortcutEnabled = true
    }
}

/// The calendars the Settings window lists, refreshed with each EventKit fetch.
@MainActor
final class CalendarDirectory: ObservableObject {
    @Published private(set) var groups: [CalendarGroup] = []
    @Published private(set) var hasAccess = false

    var refs: [CalendarRef] {
        groups.flatMap { group in group.calendars.map { CalendarRef(id: $0.id, source: group.source, title: $0.title) } }
    }

    func update(groups: [CalendarGroup], hasAccess: Bool) {
        if groups != self.groups { self.groups = groups }
        if hasAccess != self.hasAccess { self.hasAccess = hasAccess }
    }
}
