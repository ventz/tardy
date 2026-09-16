import AppKit

/// Menu bar image: a calendar page (weekday over day number) plus an optional
/// meeting dot.
///
/// Replaces the 📅 emoji, whose glyph is hardcoded to "JUL 17". The dot is drawn
/// into the same image rather than the button title -- title glyphs and text
/// attachments overlapped the icon in the real status bar. That makes the image
/// non-template, so the ink follows the menu bar appearance explicitly.
enum StatusImage {
    static let pageSize = NSSize(width: 20, height: 18)
    private static let headerHeight: CGFloat = 6.5
    private static let radius: CGFloat = 3
    private static let dotDiameter: CGFloat = 7
    private static let dotLead: CGFloat = 5

    static func make(date: Date, dot: NSColor?, dark: Bool) -> NSImage {
        let width = pageSize.width + (dot == nil ? 0 : dotLead + dotDiameter)
        let ink: NSColor = dark ? .white : .black
        let weekday = weekdayFormatter.string(from: date).uppercased()
        let day = String(Calendar.current.component(.day, from: date))

        // Drawing handler re-renders at the screen's scale (sharp on Retina)
        return NSImage(size: NSSize(width: width, height: pageSize.height), flipped: false) { _ in
            drawPage(weekday: weekday, day: day, ink: ink)
            if let dot {
                dot.setFill()
                NSBezierPath(ovalIn: NSRect(x: pageSize.width + dotLead, y: (pageSize.height - dotDiameter) / 2,
                                            width: dotDiameter, height: dotDiameter)).fill()
            }
            return true
        }
    }

    private static let weekdayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE"
        return f
    }()

    /// Solid page in `ink` with the weekday, a header rule and the day cut out.
    private static func drawPage(weekday: String, day: String, ink: NSColor) {
        let w = pageSize.width, h = pageSize.height
        ink.setFill()
        NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: w, height: h), xRadius: radius, yRadius: radius).fill()

        guard let context = NSGraphicsContext.current else { return }
        context.saveGraphicsState()
        context.compositingOperation = .destinationOut
        NSRect(x: 0, y: h - headerHeight - 0.5, width: w, height: 1).fill()

        func cutCentered(_ text: String, font: NSFont, centerY: CGFloat) {
            let string = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: ink])
            let size = string.size()
            string.draw(at: NSPoint(x: (w - size.width) / 2, y: centerY - size.height / 2))
        }
        cutCentered(weekday, font: .systemFont(ofSize: 5.5, weight: .bold), centerY: h - headerHeight / 2)
        cutCentered(day, font: .monospacedDigitSystemFont(ofSize: 10, weight: .bold), centerY: (h - headerHeight) / 2 + 0.5)
        context.restoreGraphicsState()
    }
}
