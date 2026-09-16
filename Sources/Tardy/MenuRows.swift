import AppKit
import TardyCore

/// Menu row builders. Settings live in the Settings window, not the menu.
@MainActor
enum MenuRows {
    static let personalColor = NSColor(srgbRed: 1.0, green: 0.23, blue: 0.19, alpha: 1)
    static let workColor = NSColor(srgbRed: 0.0, green: 0.53, blue: 1.0, alpha: 1)

    static func color(for kind: MeetingKind) -> NSColor {
        kind == .work ? workColor : personalColor
    }

    private static let inset: CGFloat = 14

    static func header(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    // MARK: Meetings (Granola-style two-line native rows)

    private static let paragraph: NSParagraphStyle = {
        let indent: CGFloat = 18
        let style = NSMutableParagraphStyle()
        style.tabStops = [NSTextTab(textAlignment: .left, location: indent)]
        style.headIndent = indent
        style.lineSpacing = 1
        return style
    }()

    /// Dot + title, then a gray detail line. U+2028 keeps one paragraph so the head
    /// indent lines the detail up under the title (`\n` would start a new paragraph).
    static func meeting(_ meeting: Meeting, kind: MeetingKind, target: AnyObject, action: Selector) -> NSMenuItem {
        var title = meeting.title
        if title.count > 60 { title = String(title.prefix(59)) + "…" }
        var details = Formatting.longRange(meeting.start, meeting.end)
        if let link = meeting.link { details += "  ·  \(link.platform)" }

        let text = NSMutableAttributedString()
        text.append(NSAttributedString(string: "●", attributes: [
            .paragraphStyle: paragraph,
            .font: NSFont.systemFont(ofSize: 9),
            .foregroundColor: color(for: kind),
            .baselineOffset: 1.5,
        ]))
        text.append(NSAttributedString(string: "\t" + title, attributes: [
            .paragraphStyle: paragraph,
            .font: NSFont.menuFont(ofSize: 14),
            .foregroundColor: NSColor.labelColor,
        ]))
        text.append(NSAttributedString(string: "\u{2028}" + details, attributes: [
            .paragraphStyle: paragraph,
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]))

        let item = NSMenuItem(title: meeting.title, action: action, keyEquivalent: "")
        item.attributedTitle = text
        item.target = target
        item.representedObject = meeting.id
        return item
    }

    // MARK: Clock header

    static func clockHeader() -> (NSMenuItem, NSTextField) {
        let width: CGFloat = 280, height: CGFloat = 30
        let view = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        view.autoresizingMask = [.width]
        let field = NSTextField(labelWithString: "")
        field.frame = NSRect(x: inset, y: 5, width: width - inset * 2, height: 21)
        // Monospaced digits so the seconds don't jitter the line
        field.font = .monospacedDigitSystemFont(ofSize: 16, weight: .medium)
        field.textColor = .labelColor
        view.addSubview(field)
        let item = NSMenuItem(title: "Clock Header", action: nil, keyEquivalent: "")
        item.view = view
        return (item, field)
    }

    static let joinAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.boldSystemFont(ofSize: 28),
        .foregroundColor: NSColor(srgbRed: 0.09, green: 0.64, blue: 0.29, alpha: 1), // #16A34A
    ]

    static let dismissAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.boldSystemFont(ofSize: 28),
        .foregroundColor: NSColor(srgbRed: 0.86, green: 0.15, blue: 0.15, alpha: 1), // #DC2626: systemRed was neon on the light menu
    ]

    /// LATE flashing alternates these every second.
    static let lateAttributes: [[NSAttributedString.Key: Any]] = [
        // #E879F9 fuchsia: pure #FF00FF magenta vibrated and was hard to read on the dark menu bar
        [.font: NSFont.boldSystemFont(ofSize: 14), .foregroundColor: NSColor(srgbRed: 0.91, green: 0.47, blue: 0.98, alpha: 1)],
        [.font: NSFont.boldSystemFont(ofSize: 14), .foregroundColor: NSColor(srgbRed: 1, green: 1, blue: 0, alpha: 1)],
    ]
}
