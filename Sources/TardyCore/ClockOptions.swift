import Foundation

public struct ClockOptions: Codable, Equatable, Sendable {
    public var enabled = false   // menu bar clock off by default; the dropdown always has one
    public var seconds = false   // menu bar seconds mean 1s wakeups
    public var ampm = true
    public var twentyFourHour = false
    public var weekday = true
    public var date = true

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case enabled, seconds, ampm, twentyFourHour, weekday, date
    }

    /// Missing keys take their defaults, so settings saved or exported by an older
    /// version still load after an option is added.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = ClockOptions()
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? d.enabled
        seconds = try c.decodeIfPresent(Bool.self, forKey: .seconds) ?? d.seconds
        ampm = try c.decodeIfPresent(Bool.self, forKey: .ampm) ?? d.ampm
        twentyFourHour = try c.decodeIfPresent(Bool.self, forKey: .twentyFourHour) ?? d.twentyFourHour
        weekday = try c.decodeIfPresent(Bool.self, forKey: .weekday) ?? d.weekday
        date = try c.decodeIfPresent(Bool.self, forKey: .date) ?? d.date
    }

    /// The dropdown header's fixed style: `Wed Sep 16  4:56:47 PM`.
    public static let menuHeader: ClockOptions = {
        var options = ClockOptions()
        options.enabled = true
        options.seconds = true
        return options
    }()
}
