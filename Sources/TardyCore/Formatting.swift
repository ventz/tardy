import Foundation

public enum Formatting {
    /// An event title made safe to show: control, format (bidi overrides, zero-width),
    /// line and paragraph separator characters become spaces, then runs of whitespace
    /// collapse. Invite titles are untrusted, and those characters could reorder the
    /// row's detail line or fake a second line. U+200D stays so emoji sequences survive.
    public static func displaySafe(_ text: String) -> String {
        var scalars = String.UnicodeScalarView()
        var lastWasSpace = true
        for scalar in text.unicodeScalars {
            let blanked: Bool
            switch scalar.properties.generalCategory {
            case .control, .lineSeparator, .paragraphSeparator: blanked = true
            case .format: blanked = scalar != "\u{200D}"
            default: blanked = scalar.properties.isWhitespace
            }
            if blanked {
                if !lastWasSpace { scalars.append(" ") }
                lastWasSpace = true
            } else {
                scalars.append(scalar)
                lastWasSpace = false
            }
        }
        var result = String(scalars)
        if result.hasSuffix(" ") { result.removeLast() }
        return result
    }

    private static func formatter(_ format: String, _ locale: Locale) -> DateFormatter {
        let f = DateFormatter()
        f.locale = locale
        f.dateFormat = format
        return f
    }

    /// Menu bar range, omitting a repeated am/pm: `2:30-3:00pm`.
    public static func shortRange(_ start: Date, _ end: Date, locale: Locale = .current) -> String {
        let period = formatter("a", locale)
        let startPeriod = period.string(from: start), endPeriod = period.string(from: end)
        let endText = formatter("h:mma", locale).string(from: end).lowercased()
        let startText = startPeriod == endPeriod
            ? formatter("h:mm", locale).string(from: start)
            : formatter("h:mma", locale).string(from: start).lowercased()
        return "\(startText)-\(endText)"
    }

    /// Menu list range: `5:00 PM - 6:00 PM`.
    public static func longRange(_ start: Date, _ end: Date, locale: Locale = .current) -> String {
        let f = formatter("h:mm a", locale)
        return "\(f.string(from: start)) - \(f.string(from: end))"
    }

    public static func endTime(_ end: Date, locale: Locale = .current) -> String {
        formatter("h:mma", locale).string(from: end).lowercased()
    }

    /// `45m`, `1h 11m`, `2h`.
    public static func duration(_ seconds: TimeInterval) -> String {
        let minutes = max(1, Int((seconds / 60).rounded()))
        let (h, m) = minutes.quotientAndRemainder(dividingBy: 60)
        if h == 0 { return "\(m)m" }
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }

    /// `Wed Sep 16  4:56:47 PM`, per options.
    public static func clock(_ date: Date, _ options: ClockOptions, locale: Locale = .current) -> String {
        var time: String
        if options.twentyFourHour {
            time = formatter(options.seconds ? "HH:mm:ss" : "HH:mm", locale).string(from: date)
        } else {
            time = formatter(options.seconds ? "h:mm:ss" : "h:mm", locale).string(from: date)
            if options.ampm { time += " " + formatter("a", locale).string(from: date) }
        }
        var day: [String] = []
        if options.weekday { day.append(formatter("EEE", locale).string(from: date)) }
        if options.date { day.append(formatter("MMM d", locale).string(from: date)) }
        return day.isEmpty ? time : day.joined(separator: " ") + "  " + time
    }

    /// Countdown `m:ss`.
    public static func minutesSeconds(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        return "\(total / 60):" + String(format: "%02d", total % 60)
    }
}
