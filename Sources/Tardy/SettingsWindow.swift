import AppKit
import ServiceManagement
import SwiftUI
import TardyCore
import UniformTypeIdentifiers

/// The Settings window (menu > Settings…, ⌘,), plus the AppKit panels and alerts
/// its Data pane needs.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let settings: SettingsStore
    private let directory: CalendarDirectory
    private let updater: Updater
    private let shortcuts: ShortcutActions
    private var window: NSWindow?

    init(settings: SettingsStore, directory: CalendarDirectory, updater: Updater, shortcuts: ShortcutActions) {
        self.settings = settings
        self.directory = directory
        self.updater = updater
        self.shortcuts = shortcuts
    }

    func show() {
        if window == nil {
            let view = SettingsView(settings: settings, directory: directory, updater: updater, shortcuts: shortcuts,
                                    actions: SettingsActions(export: { [weak self] in self?.exportSettings() },
                                                             importFile: { [weak self] in self?.importSettings() },
                                                             reset: { [weak self] in self?.resetSettings() }))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 520),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                                  backing: .buffered, defer: false)
            window.title = "Tardy Settings"
            // NavigationSplitView only lines its sidebar and detail title up with the
            // title bar when the window has a unified toolbar (what SwiftUI's own
            // Window scene provides); without one the detail header sits offset
            window.toolbar = NSToolbar(identifier: "TardySettings")
            window.toolbarStyle = .unified
            window.contentViewController = NSHostingController(rootView: view)
            window.setContentSize(NSSize(width: 760, height: 520))
            window.contentMinSize = NSSize(width: 680, height: 440)
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            window.setFrameAutosaveName("TardySettings")
            self.window = window
        }
        window?.bringToFront()
    }

    // MARK: Data pane

    private func exportSettings() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "Tardy Settings.json"
        panel.canCreateDirectories = true
        guard let window, panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try settings.snapshot(calendars: directory.refs).encoded().write(to: url, options: .atomic)
        } catch {
            showError("Couldn't Export Settings", error, in: window)
        }
    }

    private func importSettings() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard let window, panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let snapshot = try SettingsSnapshot.decode(Data(contentsOf: url))
            let confirm = NSAlert()
            confirm.messageText = "Replace your Tardy settings?"
            // Name the shortcut: an imported one is registered system-wide
            var shortcutNote = ""
            if let imported = snapshot.shortcut, imported.shortcut.isValid {
                shortcutNote = imported.enabled
                    ? " The menu shortcut becomes \(imported.shortcut.display)."
                    : " The menu shortcut will be turned off."
            }
            confirm.informativeText = "Mute, clock and all \(snapshot.calendars.count) calendar settings will be replaced with the ones in “\(url.lastPathComponent)”." + shortcutNote
            confirm.addButton(withTitle: "Import")
            confirm.addButton(withTitle: "Cancel")
            confirm.beginSheetModal(for: window) { [weak self] response in
                MainActor.assumeIsolated {
                    guard response == .alertFirstButtonReturn, let self else { return }
                    let unmatched = self.settings.apply(snapshot, calendars: self.directory.refs)
                    if !unmatched.isEmpty { self.showUnmatched(unmatched, in: window) }
                }
            }
        } catch {
            showError("Couldn't Import Settings", error, in: window)
        }
    }

    private func resetSettings() {
        guard let window else { return }
        let confirm = NSAlert()
        confirm.messageText = "Reset all settings?"
        confirm.informativeText = "Every calendar is watched and Personal again, the menu bar clock is turned off and sounds are unmuted."
        confirm.alertStyle = .warning
        confirm.addButton(withTitle: "Reset")
        confirm.addButton(withTitle: "Cancel")
        confirm.buttons.first?.hasDestructiveAction = true
        confirm.beginSheetModal(for: window) { [weak self] response in
            MainActor.assumeIsolated {
                if response == .alertFirstButtonReturn { self?.settings.resetToDefaults() }
            }
        }
    }

    private func showUnmatched(_ unmatched: [String], in window: NSWindow) {
        let alert = NSAlert()
        alert.messageText = "Some calendars weren't found"
        alert.informativeText = "These calendars from the file aren't in the Mac Calendar app on this Mac, so their settings were skipped:\n\n"
            + unmatched.joined(separator: "\n")
        alert.beginSheetModal(for: window)
    }

    private func showError(_ title: String, _ error: Error, in window: NSWindow) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.beginSheetModal(for: window)
    }
}

struct ShortcutActions {
    /// Registers the shortcut; false if macOS refuses it (another app owns it).
    let tryShortcut: (HotKeyShortcut) -> Bool
    /// Suspends the live hotkey while recording, so pressing it reaches the recorder.
    let setRecording: (Bool) -> Void
}

struct SettingsActions {
    let export: () -> Void
    let importFile: () -> Void
    let reset: () -> Void
}

// MARK: - Views

private enum SettingsPane: String, CaseIterable, Identifiable {
    case general, calendars, clock, shortcuts, updates, data

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .calendars: "Calendars"
        case .clock: "Clock"
        case .shortcuts: "Shortcuts"
        case .updates: "Updates"
        case .data: "Import & Export"
        }
    }

    var systemImage: String {
        switch self {
        case .general: "gearshape"
        case .calendars: "calendar"
        case .clock: "clock"
        case .shortcuts: "command"
        case .updates: "arrow.triangle.2.circlepath"
        case .data: "square.and.arrow.up.on.square"
        }
    }
}

struct SettingsView: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var directory: CalendarDirectory
    let updater: Updater
    let shortcuts: ShortcutActions
    let actions: SettingsActions

    @State private var pane: SettingsPane? = .general

    var body: some View {
        NavigationSplitView {
            List(SettingsPane.allCases, selection: $pane) { pane in
                Label(pane.title, systemImage: pane.systemImage).tag(pane)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 190)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            switch pane ?? .general {
            case .general: GeneralPane(settings: settings)
            case .calendars: CalendarsPane(settings: settings, directory: directory)
            case .clock: ClockPane(settings: settings)
            case .shortcuts: ShortcutsPane(settings: settings, actions: shortcuts)
            case .updates: UpdatesPane(updater: updater)
            case .data: DataPane(actions: actions)
            }
        }
        .frame(minWidth: 680, minHeight: 440)
    }
}

private struct GeneralPane: View {
    @ObservedObject var settings: SettingsStore
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    // The build number (CFBundleVersion) only orders releases for Sparkle; users see the version
    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    var body: some View {
        Form {
            Section {
                Toggle("Mute sounds and notifications", isOn: $settings.muteSounds)
            } header: {
                Text("Alerts")
            } footer: {
                Text("The menu bar still counts down and flashes LATE while muted.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Launch at login", isOn: Binding(
                    get: { launchAtLogin },
                    set: { enable in
                        do {
                            if enable { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                            loginError = nil
                        } catch {
                            loginError = error.localizedDescription
                        }
                        launchAtLogin = SMAppService.mainApp.status == .enabled
                    }
                ))
                if let loginError {
                    Text(loginError).foregroundStyle(.red).font(.callout)
                }
            } header: {
                Text("Startup")
            }

            Section("About") {
                LabeledContent("Version", value: version)
                LabeledContent("Website") {
                    Link("tardy.vpetkov.net", destination: URL(string: "https://tardy.vpetkov.net")!)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("General")
        .onAppear { launchAtLogin = SMAppService.mainApp.status == .enabled }
    }
}

private struct CalendarsPane: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var directory: CalendarDirectory

    var body: some View {
        Group {
            if !directory.hasAccess {
                ContentUnavailableView {
                    Label("No Calendar Access", systemImage: "calendar.badge.exclamationmark")
                } description: {
                    Text("Tardy reads the calendars in the Mac Calendar app. Allow access in System Settings.")
                } actions: {
                    Button("Open Privacy Settings") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!)
                    }
                }
            } else if directory.groups.isEmpty {
                ContentUnavailableView("No Calendars", systemImage: "calendar",
                                       description: Text("Add accounts in Calendar > Settings > Accounts."))
            } else {
                Form {
                    Section {
                        Text("Tardy watches the calendars in the Mac Calendar app. Mark each one Personal (red dot) or Work (blue dot); calendars added to Calendar later are watched automatically.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(directory.groups) { group in
                        Section(group.source) {
                            ForEach(group.calendars) { calendar in
                                CalendarRow(calendar: calendar, settings: settings)
                            }
                        }
                    }
                }
                .formStyle(.grouped)
            }
        }
        .navigationTitle("Calendars")
    }
}

private struct CalendarRow: View {
    let calendar: CalendarGroup.Entry
    @ObservedObject var settings: SettingsStore

    private var watched: Binding<Bool> {
        Binding(
            get: { !settings.disabledCalendarIDs.contains(calendar.id) },
            set: { watch in
                if watch { settings.disabledCalendarIDs.remove(calendar.id) } else { settings.disabledCalendarIDs.insert(calendar.id) }
            }
        )
    }

    private var kind: Binding<MeetingKind> {
        Binding(
            get: { settings.kind(ofCalendar: calendar.id) },
            set: { kind in
                if kind == .work { settings.workCalendarIDs.insert(calendar.id) } else { settings.workCalendarIDs.remove(calendar.id) }
            }
        )
    }

    var body: some View {
        HStack(spacing: 10) {
            Toggle(isOn: watched) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color(nsColor: MenuRows.color(for: kind.wrappedValue)))
                        .frame(width: 8, height: 8)
                        .opacity(watched.wrappedValue ? 1 : 0.3)
                    Text(calendar.title)
                        .foregroundStyle(watched.wrappedValue ? .primary : .secondary)
                }
            }
            .toggleStyle(.checkbox)
            Spacer()
            Picker("Kind", selection: kind) {
                Text("Personal").tag(MeetingKind.personal)
                Text("Work").tag(MeetingKind.work)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 160)
            .disabled(!watched.wrappedValue)
        }
    }
}

private struct ClockPane: View {
    @ObservedObject var settings: SettingsStore

    var body: some View {
        Form {
            Section {
                Toggle("Show a clock in the menu bar", isOn: $settings.clock.enabled)
            } footer: {
                Text("The menu always shows a live clock with seconds, whatever you choose here.")
                    .foregroundStyle(.secondary)
            }

            Section("Format") {
                Toggle("Show seconds", isOn: $settings.clock.seconds)
                Toggle("Show AM/PM", isOn: $settings.clock.ampm)
                    .disabled(settings.clock.twentyFourHour)
                Toggle("Use 24-hour time", isOn: $settings.clock.twentyFourHour)
                Toggle("Show the day of the week", isOn: $settings.clock.weekday)
                Toggle("Show the date", isOn: $settings.clock.date)
            }
            .disabled(!settings.clock.enabled)

            Section {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    LabeledContent("Preview") {
                        Text(Formatting.clock(context.date, settings.clock))
                            .monospacedDigit()
                            .foregroundStyle(settings.clock.enabled ? .primary : .secondary)
                    }
                }
            } footer: {
                if settings.clock.enabled && settings.clock.seconds {
                    Text("Seconds in the menu bar wake your Mac every second. Without them it updates once a minute.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Clock")
    }
}

private struct ShortcutsPane: View {
    @ObservedObject var settings: SettingsStore
    let actions: ShortcutActions
    @State private var error: String?

    var body: some View {
        Form {
            Section {
                Toggle("Open and close the menu from anywhere", isOn: $settings.shortcutEnabled)
                LabeledContent("Shortcut") {
                    HStack(spacing: 8) {
                        ShortcutRecorder(shortcut: settings.shortcut, actions: actions, error: $error)
                        Button("Reset") {
                            error = nil
                            if !actions.tryShortcut(.default) {
                                error = "\(HotKeyShortcut.default.display) is already used by another app."
                            }
                        }
                        .disabled(settings.shortcut == .default)
                    }
                }
                .disabled(!settings.shortcutEnabled)
                if let error {
                    Text(error).foregroundStyle(.red).font(.callout)
                }
            } header: {
                Text("Global")
            } footer: {
                Text("Click the shortcut, then press a new combination with ⌘, ⌥ or ⌃. Press Esc to cancel. Shortcuts reserved by macOS itself, such as ⌘Space, can't be detected and will win.")
                    .foregroundStyle(.secondary)
            }

            Section("In the Tardy menu") {
                LabeledContent("Settings", value: "⌘,")
                LabeledContent("Quit Tardy", value: "⌘Q")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Shortcuts")
    }
}

/// Click to record: the next key press with ⌘, ⌥ or ⌃ becomes the shortcut.
private struct ShortcutRecorder: View {
    let shortcut: HotKeyShortcut
    let actions: ShortcutActions
    @Binding var error: String?
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        Button(action: toggle) {
            Text(recording ? "Press a shortcut…" : shortcut.display)
                .font(recording ? .body : .body.monospaced())
                .frame(minWidth: 130)
        }
        .buttonStyle(.bordered)
        .tint(recording ? .accentColor : nil)
        .onDisappear(perform: stop)
    }

    private func toggle() {
        recording ? stop() : start()
    }

    private func start() {
        error = nil
        recording = true
        actions.setRecording(true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { // Esc
                stop()
                return nil
            }
            let flags = event.modifierFlags.intersection([.command, .option, .control, .shift]).rawValue
            let candidate = HotKeyShortcut(keyCode: UInt32(event.keyCode),
                                           carbonModifiers: HotKeyShortcut.carbonModifiers(fromCocoa: flags),
                                           key: Self.label(for: event),
                                           keyEquivalent: (event.charactersIgnoringModifiers ?? "").lowercased())
            guard candidate.isValid else {
                error = "Include ⌘, ⌥ or ⌃ in the shortcut."
                return nil
            }
            stop()
            if !actions.tryShortcut(candidate) {
                error = "\(candidate.display) is already used by another app."
            }
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if recording { actions.setRecording(false) }
        recording = false
    }

    private static let named: [UInt16: String] = [
        49: "Space", 36: "↩", 48: "⇥", 51: "⌫", 117: "⌦", 115: "↖", 119: "↘", 116: "⇞", 121: "⇟",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8",
        101: "F9", 109: "F10", 103: "F11", 111: "F12",
    ]

    private static func label(for event: NSEvent) -> String {
        if let name = named[event.keyCode] { return name }
        return (event.charactersIgnoringModifiers ?? "?").uppercased()
    }
}

private struct UpdatesPane: View {
    let updater: Updater
    @State private var automatic = false

    var body: some View {
        Form {
            if updater.isEnabled {
                Section {
                    Toggle("Automatically check for updates", isOn: Binding(
                        get: { automatic },
                        set: { updater.automaticallyChecks = $0; automatic = $0 }
                    ))
                    LabeledContent("Last checked") {
                        Text(updater.lastCheck.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "Never")
                    }
                    Button("Check for Updates Now") { updater.checkForUpdates() }
                } footer: {
                    Text("Updates are signed, notarized and verified before they install.")
                        .foregroundStyle(.secondary)
                }
            } else {
                Section {
                    Text("Updates are off in development builds.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Updates")
        .onAppear { automatic = updater.automaticallyChecks }
    }
}

private struct DataPane: View {
    let actions: SettingsActions

    var body: some View {
        Form {
            Section {
                LabeledContent("Export settings to a file") {
                    Button("Export…", action: actions.export)
                }
                LabeledContent("Import settings from a file") {
                    Button("Import…", action: actions.importFile)
                }
            } header: {
                Text("Import & Export")
            } footer: {
                Text("The file holds mute, clock, and each calendar's watched and Personal/Work settings. Calendars are matched by account and name on another Mac.")
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("Restore every setting to its default") {
                    Button("Reset…", role: .destructive, action: actions.reset)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Import & Export")
    }
}
