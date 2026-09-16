import Foundation

/// A calendar as the Mac Calendar app knows it.
public struct CalendarRef: Codable, Equatable, Hashable, Sendable {
    public let id: String
    public let source: String
    public let title: String

    public init(id: String, source: String, title: String) {
        self.id = id
        self.source = source
        self.title = title
    }
}

public enum SettingsImportError: LocalizedError, Equatable {
    case notTardySettings
    case newerVersion(Int)

    public var errorDescription: String? {
        switch self {
        case .notTardySettings:
            return "This file isn't a Tardy settings export."
        case .newerVersion(let version):
            return "This file was exported by a newer version of Tardy (format \(version)). Update Tardy to import it."
        }
    }
}

/// The exported settings file.
public struct SettingsSnapshot: Codable, Equatable, Sendable {
    public static let formatName = "tardy-settings"
    public static let currentVersion = 1

    public struct CalendarSetting: Codable, Equatable, Sendable {
        public let id: String
        public let source: String
        public let title: String
        public let watched: Bool
        public let kind: MeetingKind
    }

    public var format: String
    public var version: Int
    public var exportedAt: Date
    public var muteSounds: Bool
    public var clock: ClockOptions
    public var calendars: [CalendarSetting]
    /// Menu shortcut; absent in files from before shortcuts were configurable.
    public var shortcut: ShortcutSetting?

    public struct ShortcutSetting: Codable, Equatable, Sendable {
        public let enabled: Bool
        public let shortcut: HotKeyShortcut

        public init(enabled: Bool, shortcut: HotKeyShortcut) {
            self.enabled = enabled
            self.shortcut = shortcut
        }
    }

    public init(muteSounds: Bool, clock: ClockOptions, calendars: [CalendarRef],
                disabled: Set<String>, work: Set<String>, shortcut: ShortcutSetting? = nil,
                exportedAt: Date = Date()) {
        self.shortcut = shortcut
        format = Self.formatName
        version = Self.currentVersion
        self.exportedAt = exportedAt
        self.muteSounds = muteSounds
        self.clock = clock
        self.calendars = calendars.map {
            CalendarSetting(id: $0.id, source: $0.source, title: $0.title,
                            watched: !disabled.contains($0.id), kind: work.contains($0.id) ? .work : .personal)
        }
    }

    public struct Resolved: Equatable, Sendable {
        public let disabled: Set<String>
        public let work: Set<String>
        /// Exported calendars with no counterpart on this Mac ("Account / Title").
        public let unmatched: [String]
        public let matched: Int
    }

    /// Maps the exported calendars onto this Mac's.
    ///
    /// Calendar identifiers are per-device, so a calendar matches by identifier
    /// first, then by account and title. Calendars not in the file are watched and
    /// Personal, the same as a fresh install.
    public func resolve(against available: [CalendarRef]) -> Resolved {
        var disabled = Set<String>(), work = Set<String>(), unmatched: [String] = []
        var matched = 0
        var claimed = Set<String>()
        let byID = Dictionary(available.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        for setting in calendars {
            let target = byID[setting.id].flatMap { claimed.contains($0.id) ? nil : $0 }
                ?? available.first { !claimed.contains($0.id) && $0.source == setting.source && $0.title == setting.title }
            guard let target else {
                unmatched.append("\(setting.source) / \(setting.title)")
                continue
            }
            claimed.insert(target.id)
            matched += 1
            if !setting.watched { disabled.insert(target.id) }
            if setting.kind == .work { work.insert(target.id) }
        }
        return Resolved(disabled: disabled, work: work, unmatched: unmatched, matched: matched)
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    public static func decode(_ data: Data) throws -> SettingsSnapshot {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        struct Header: Decodable { let format: String?; let version: Int? }
        guard let header = try? decoder.decode(Header.self, from: data),
              header.format == formatName, let version = header.version else {
            throw SettingsImportError.notTardySettings
        }
        guard version <= currentVersion else { throw SettingsImportError.newerVersion(version) }
        return try decoder.decode(SettingsSnapshot.self, from: data)
    }
}
