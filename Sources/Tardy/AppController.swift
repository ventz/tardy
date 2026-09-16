import AppKit
import Combine
import EventKit
import ServiceManagement
import TardyCore

/// Owns the status item, the per-meeting alert state machine, the tick timer and
/// the menu.
@MainActor
final class AppController: NSObject, NSMenuDelegate {
    private let settings = SettingsStore()
    private let directory = CalendarDirectory()
    private let calendars = CalendarService()
    private let alerts = AlertPlayer()
    private let updater = Updater()
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private lazy var settingsWindow = SettingsWindowController(
        settings: settings, directory: directory, updater: updater,
        shortcuts: ShortcutActions(tryShortcut: { [unowned self] in tryShortcut($0) },
                                   setRecording: { [unowned self] in setShortcutRecording($0) })
    )
    private var settingsObserver: AnyCancellable?
    private var watchedCalendars: Set<String> = []
    private let closeItem = NSMenuItem(title: "Close Menu", action: #selector(closeMenu), keyEquivalent: "m")

    // Alert state
    private var states: [String: AlertState] = [:]
    private var entered: [String: Set<AlertState>] = [:]
    private var dismissed: Set<String> = []
    private var primary: Meeting?
    private var clock = ClockOptions()

    // Status item rendering
    private var statusText = ""          // meeting part of the title, without the clock
    private var renderedTitle: String?   // nil forces the next render
    private var showingLate = false
    private var iconKey: String?

    // Tick + menu tracking
    private var timer: Timer?
    private var menuOpen = false
    private var menuClosedAt = Date.distantPast
    private var hotKey: HotKey?

    // Menu items
    private var clockField: NSTextField!
    private let joinItem = NSMenuItem(title: "Join", action: #selector(joinPrimary), keyEquivalent: "")
    private let joinSeparator = NSMenuItem.separator()
    private let meetingsEnd = NSMenuItem(title: "Meetings End", action: nil, keyEquivalent: "")
    private var meetingItems: [NSMenuItem] = []
    private let dismissItem = NSMenuItem(title: "Dismiss", action: #selector(dismissPrimary), keyEquivalent: "")
    private let muteItem = NSMenuItem(title: "Mute Sounds", action: #selector(toggleMute), keyEquivalent: "")

    // MARK: Startup

    func start() {
        clock = settings.clock
        alerts.muted = settings.muteSounds
        watchedCalendars = settings.disabledCalendarIDs
        // objectWillChange fires before the new value lands; apply on the next pass
        settingsObserver = settings.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.applySettings() }
        buildMenu()
        statusItem.menu = menu
        statusItem.button?.imagePosition = .imageLeft
        render(text: "", icon: true)

        alerts.requestNotificationPermission()
        registerLoginItemOnFirstLaunch()
        hotKey = HotKey { [weak self] in self?.toggleMenu() }
        applyShortcut()
        observeChanges()

        Task { @MainActor in
            if await calendars.requestAccess() == false { showAccessAlert() }
            directory.update(groups: calendars.groups(), hasAccess: calendars.hasAccess)
            refreshSoon()
        }
        scheduleTick(0.1)
    }

    /// A menu bar alert app is only useful if it's running, so the first launch of an
    /// installed build turns on Launch at Login once; the settings checkbox turns it off.
    private func registerLoginItemOnFirstLaunch() {
        guard updater.isEnabled, !settings.didRegisterLoginItem else { return }
        settings.didRegisterLoginItem = true
        do {
            try SMAppService.mainApp.register()
        } catch {
            NSLog("Tardy: could not enable launch at login: \(error)")
        }
    }

    /// Event-driven refresh instead of polling: calendar edits, wake, timezone and day changes.
    private func observeChanges() {
        let center = NotificationCenter.default
        let refresh: @Sendable (Notification) -> Void = { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshSoon() }
        }
        center.addObserver(forName: .EKEventStoreChanged, object: calendars.store, queue: .main, using: refresh)
        center.addObserver(forName: .NSSystemTimeZoneDidChange, object: nil, queue: .main) { [weak self] _ in
            NSTimeZone.resetSystemTimeZone()
            MainActor.assumeIsolated { self?.refreshSoon() }
        }
        center.addObserver(forName: .NSCalendarDayChanged, object: nil, queue: .main, using: refresh)
        // NSTimers don't count system sleep, so wake must tick explicitly
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil,
                                                          queue: .main, using: refresh)
    }

    private func showAccessAlert() {
        let alert = NSAlert()
        alert.messageText = "Tardy needs access to your calendars"
        alert.informativeText = "Tardy reads the calendars from the Mac Calendar app. Allow access in System Settings > Privacy & Security > Calendars."
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Later")
        alert.window.bringToFront()
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!)
        }
    }

    // MARK: Tick

    private func scheduleTick(_ delay: TimeInterval) {
        timer?.invalidate()
        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.tickFired() }
        }
        // Tolerance lets macOS coalesce wakeups; tight only for the 1s countdown
        timer.tolerance = delay <= 1 ? 0.1 : min(delay * 0.1, 30)
        // Common modes so the countdown and menu clock keep running while the menu is open
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tickFired() {
        tick()
        let delay = TickScheduler.nextDelay(now: Date(), meetings: calendars.meetings, dismissed: dismissed,
                                            menuOpen: menuOpen, clock: clock)
        debugLog("[tick] next in \(String(format: "%.1f", delay))s")
        scheduleTick(delay)
    }

    private func refreshSoon() {
        calendars.invalidate()
        scheduleTick(0.5) // short delay coalesces notification bursts
    }

    private func tick() {
        let now = Date()
        if menuOpen { updateClockHeader() }

        if now.timeIntervalSince(calendars.lastFetch) >= Timing.safetyRefresh {
            calendars.refresh(disabled: settings.disabledCalendarIDs, now: now)
            rebuildMeetings()
            directory.update(groups: calendars.groups(), hasAccess: calendars.hasAccess)
            dismissed.formIntersection(calendars.meetings.map(\.id))
        }

        var active = calendars.meetings.filter {
            !dismissed.contains($0.id) && $0.start.timeIntervalSince(now) > -Timing.lateAutoDismiss
        }
        guard !active.isEmpty else {
            if primary != nil { resetAlerts() }
            render(text: "", icon: true)
            return
        }

        for meeting in active {
            let until = meeting.start.timeIntervalSince(now)
            let state = AlertState.forSecondsUntil(until)
            states[meeting.id] = state
            if state == .late && until <= -Timing.lateAutoDismiss {
                dismiss(meeting.id)
                continue
            }
            if state != .idle && entered[meeting.id, default: []].insert(state).inserted {
                onEnter(state, meeting)
            }
        }

        active.removeAll { dismissed.contains($0.id) }
        guard let newPrimary = Primary.select(active, states: states, now: now) else {
            resetAlerts()
            render(text: "", icon: true)
            return
        }
        if newPrimary.id != primary?.id {
            clearLate()
            hideDismiss()
            primary = newPrimary
            if (states[newPrimary.id] ?? .idle) != .idle { showDismiss() }
        } else {
            primary = newPrimary
        }
        updateDisplay(states[newPrimary.id] ?? .idle, newPrimary, newPrimary.start.timeIntervalSince(now))

        let current = Set(active.map(\.id))
        states = states.filter { current.contains($0.key) }
        entered = entered.filter { current.contains($0.key) }
    }

    private func resetAlerts() {
        primary = nil
        clearLate()
        hideDismiss()
        states.removeAll()
        entered.removeAll()
    }

    private func onEnter(_ state: AlertState, _ meeting: Meeting) {
        switch state {
        case .alert15:
            alerts.chime()
            alerts.notify("Meeting in 15 minutes", meeting.title)
        case .countdown:
            alerts.chime()
            alerts.notify("Meeting in 5 minutes", meeting.title)
        case .alarm:
            alerts.beeps()
        case .late, .idle:
            break
        }
        if state != .idle { showDismiss() }
    }

    // MARK: Status item

    private func updateDisplay(_ state: AlertState, _ meeting: Meeting, _ until: TimeInterval) {
        if state != .late { clearLate() }
        let title = String(meeting.title.prefix(20))
        switch state {
        case .idle:
            // Far away: icon + dot only; show the time once it's within 30 min
            render(text: until > Timing.showTime ? "" : " " + Formatting.shortRange(meeting.start, meeting.end), icon: true)
        case .alert15:
            render(text: " \(Int(until / 60))m - \(title)", icon: true)
        case .countdown:
            render(text: "🔴 \(Formatting.minutesSeconds(until)) - \(title) (until \(Formatting.endTime(meeting.end)))", icon: false)
        case .alarm:
            render(text: "🔴 \(Formatting.minutesSeconds(until)) - \(title)", icon: false)
        case .late:
            showingLate = true
            syncIcon(show: false)
            let late = -until
            statusItem.button?.attributedTitle = NSAttributedString(
                string: "⚠ LATE \(Formatting.minutesSeconds(late))",
                attributes: MenuRows.lateAttributes[Int(late) % 2]
            )
            renderedTitle = nil
        }
    }

    /// Icon states show the date icon, dot and optional clock; red/LATE states stay uncluttered.
    private func render(text: String, icon: Bool) {
        syncIcon(show: icon)
        statusText = text
        var full = text
        if icon && clock.enabled {
            full = " " + Formatting.clock(Date(), clock) + (text.isEmpty ? "" : "  ·" + text)
        }
        guard !showingLate, full != renderedTitle else { return }
        statusItem.button?.title = full
        renderedTitle = full
    }

    private func clearLate() {
        guard showingLate else { return }
        showingLate = false
        renderedTitle = nil
        statusItem.button?.title = ""
    }

    /// Redraws the icon only when day, dot, visibility or menu bar appearance changes.
    private func syncIcon(show: Bool) {
        guard let button = statusItem.button else { return }
        let now = Date()
        let dotKind = show ? nextMeetingKind(now: now) : nil
        let dark = button.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let day = Calendar.current.ordinality(of: .day, in: .era, for: now) ?? 0
        let key = "\(day)|\(show)|\(dotKind?.rawValue ?? "-")|\(dark)"
        guard key != iconKey else { return }
        iconKey = key
        button.image = show ? StatusImage.make(date: now, dot: dotKind.map(MenuRows.color(for:)), dark: dark) : nil
    }

    /// The dot marks the next meeting that hasn't started; an in-progress one gets none.
    private func nextMeetingKind(now: Date) -> MeetingKind? {
        calendars.meetings
            .first { $0.start > now && !dismissed.contains($0.id) }
            .map { settings.kind(ofCalendar: $0.calendarID) }
    }

    // MARK: Menu

    private func buildMenu() {
        menu.autoenablesItems = false
        menu.delegate = self

        let (clockItem, field) = MenuRows.clockHeader()
        clockField = field
        menu.addItem(clockItem)
        menu.addItem(.separator())

        joinItem.target = self
        menu.addItem(joinItem)
        menu.addItem(joinSeparator)
        meetingsEnd.isHidden = true
        menu.addItem(meetingsEnd)

        dismissItem.target = self
        dismissItem.attributedTitle = NSAttributedString(string: "Dismiss", attributes: MenuRows.dismissAttributes)
        menu.addItem(dismissItem)
        [joinItem, joinSeparator, dismissItem].forEach { $0.isHidden = true }

        menu.addItem(.separator())
        muteItem.target = self
        muteItem.state = alerts.muted ? .on : .off
        menu.addItem(muteItem)
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Tardy", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        // Hidden Cmd+Shift+M item closes the open menu: the global hotkey is suspended
        // while the menu tracks (see menuWillOpen), so the key reaches the menu itself
        closeItem.target = self
        closeItem.isHidden = true
        closeItem.allowsKeyEquivalentWhenHidden = true
        menu.addItem(closeItem)

        rebuildMeetings()
    }

    private func rebuildMeetings() {
        meetingItems.forEach(menu.removeItem)
        meetingItems.removeAll()
        let insertAt = { [menu, meetingsEnd] (item: NSMenuItem) in
            menu.insertItem(item, at: menu.index(of: meetingsEnd))
        }
        func add(_ item: NSMenuItem) {
            insertAt(item)
            meetingItems.append(item)
        }

        guard calendars.hasAccess else {
            let item = NSMenuItem(title: "Allow Calendar Access…", action: #selector(openCalendarPrivacy), keyEquivalent: "")
            item.target = self
            add(item)
            return
        }

        let now = Date()
        let visible = calendars.meetings.filter { $0.end > now && !dismissed.contains($0.id) }
        guard !visible.isEmpty else {
            add(MenuRows.header("No more meetings today"))
            return
        }

        var sections: [(String, [Meeting])] = []
        let inProgress = visible.filter { $0.start <= now }
        let upcoming = visible.filter { $0.start > now }
        if !inProgress.isEmpty { sections.append(("Now", inProgress)) }
        if let first = upcoming.first {
            // Meetings sharing the next start time go under the same header
            let next = upcoming.filter { $0.start == first.start }
            sections.append(("Starts in \(Formatting.duration(first.start.timeIntervalSince(now)))", next))
            let later = Array(upcoming.dropFirst(next.count))
            if !later.isEmpty { sections.append(("Later today", later)) }
        }
        for (index, (label, meetings)) in sections.enumerated() {
            if index > 0 { add(.separator()) }
            add(MenuRows.header(label))
            for meeting in meetings {
                add(MenuRows.meeting(meeting, kind: settings.kind(ofCalendar: meeting.calendarID),
                                     target: self, action: #selector(openMeeting(_:))))
            }
        }
    }

    private func updateClockHeader() {
        clockField.stringValue = Formatting.clock(Date(), .menuHeader)
    }

    private func showDismiss() {
        dismissItem.isHidden = false
        guard let link = primary?.link else {
            joinItem.isHidden = true
            joinSeparator.isHidden = true
            return
        }
        joinItem.attributedTitle = NSAttributedString(string: "Join via \(link.platform)", attributes: MenuRows.joinAttributes)
        joinItem.isHidden = false
        joinSeparator.isHidden = false
    }

    private func hideDismiss() {
        [joinItem, joinSeparator, dismissItem].forEach { $0.isHidden = true }
    }

    private func dismiss(_ id: String) {
        dismissed.insert(id)
        states[id] = nil
        entered[id] = nil
        if primary?.id == id {
            primary = nil
            clearLate()
            hideDismiss()
        }
    }

    // MARK: NSMenuDelegate

    func menuWillOpen(_ menu: NSMenu) {
        guard menu === self.menu else { return }
        menuOpen = true
        // Registered hotkeys are swallowed until the menu closes; suspend so the
        // hidden Close Menu item receives Cmd+Shift+M
        hotKey?.suspend()
        rebuildMeetings() // keeps "Starts in …" current
        muteItem.state = alerts.muted ? .on : .off
        updateClockHeader()
        scheduleTick(1.0 - Date().timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1) + 0.02)
    }

    func menuDidClose(_ menu: NSMenu) {
        guard menu === self.menu else { return }
        menuOpen = false
        menuClosedAt = Date()
        hotKey?.resume()
    }

    // MARK: Actions

    private func toggleMenu() {
        // The closing keypress can arrive just after menuDidClose; don't reopen
        guard Date().timeIntervalSince(menuClosedAt) >= 0.5 else { return }
        if menuOpen {
            menu.cancelTracking()
        } else {
            // performClick blocks while the menu is open; run it after the hotkey
            // handler returns so the closing press isn't queued behind it
            perform(#selector(openMenu), with: nil, afterDelay: 0)
        }
    }

    @objc private func openMenu() {
        statusItem.button?.performClick(nil)
    }

    @objc private func closeMenu() {}

    @objc private func openMeeting(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let meeting = calendars.meetings.first(where: { $0.id == id }) else { return }
        if let link = meeting.link {
            join(meeting, link)
        } else if let calendarApp = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") {
            NSWorkspace.shared.openApplication(at: calendarApp, configuration: .init())
        }
    }

    @objc private func joinPrimary() {
        guard let primary, let link = primary.link else { return }
        join(primary, link)
    }

    /// Opens the link and dismisses the meeting so the LATE flashing stops.
    private func join(_ meeting: Meeting, _ link: MeetingLink) {
        guard MeetingLinks.isSafeToOpen(link.url) else { return }
        NSWorkspace.shared.open(link.url)
        dismiss(meeting.id)
        scheduleTick(0.05)
    }

    @objc private func dismissPrimary() {
        guard let primary else { return }
        dismiss(primary.id)
        scheduleTick(0.05)
    }

    @objc private func toggleMute() {
        settings.muteSounds.toggle()
    }

    /// Registers the configured shortcut and mirrors it on the hidden Close Menu item.
    /// A shortcut macOS refuses (another app owns it) falls back to none, logged.
    private func applyShortcut() {
        let wanted = settings.shortcutEnabled ? settings.shortcut : nil
        if hotKey?.shortcut != wanted, hotKey?.set(wanted) == false {
            NSLog("Tardy: \(wanted?.display ?? "") is already used by another app")
        }
        let active = hotKey?.shortcut
        closeItem.keyEquivalent = active?.keyEquivalent ?? ""
        closeItem.keyEquivalentModifierMask = NSEvent.ModifierFlags(rawValue: active?.cocoaModifiers ?? 0)
    }

    /// For the Settings recorder: try a shortcut and report whether macOS accepted it.
    func tryShortcut(_ shortcut: HotKeyShortcut) -> Bool {
        guard hotKey?.set(shortcut) == true else { return false }
        settings.shortcut = shortcut
        settings.shortcutEnabled = true
        return true
    }

    func setShortcutRecording(_ recording: Bool) {
        // A registered hotkey is swallowed system-wide, so the recorder couldn't see it
        if recording { hotKey?.suspend() } else { hotKey?.resume() }
    }

    @objc private func openSettings() {
        // Wait for the menu to finish closing: an activation request made during
        // menu tracking is the one macOS most often ignores
        DispatchQueue.main.async { [weak self] in self?.settingsWindow.show() }
    }

    /// Settings changed (menu, Settings window, import or reset): bring everything in line.
    private func applySettings() {
        alerts.muted = settings.muteSounds
        muteItem.state = alerts.muted ? .on : .off
        clock = settings.clock
        if settings.disabledCalendarIDs != watchedCalendars {
            watchedCalendars = settings.disabledCalendarIDs
            calendars.invalidate()
        }
        applyShortcut()
        iconKey = nil       // dot color may have changed
        renderedTitle = nil // clock format may have changed
        rebuildMeetings()
        scheduleTick(0.05)
    }

    @objc private func openCalendarPrivacy() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!)
    }
}
