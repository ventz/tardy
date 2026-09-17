import Foundation

public struct MeetingLink: Equatable, Sendable {
    public let url: URL
    public let platform: String
}

public enum MeetingLinks {
    /// URL bodies stop at whitespace, quotes, angle brackets and closing HTML/brace
    /// characters, so links inside HTML notes (`<a href="...">`) don't swallow markup.
    private static let body = #"[^\s<>"'\])}]+"#

    /// Every provider Tardy recognizes, in priority order: the first match wins.
    /// Hosts that allow subdomains use `(?:[\w-]+\.)*` so the provider name must start
    /// a DNS label: `acme.zoom.us` matches, a lookalike like `attacker-zoom.us` does not.
    /// Keep README.md's provider list in sync with this table.
    public static let providers: [(pattern: String, platform: String)] = [
        (#"https://(?:[\w-]+\.)*zoom(?:gov)?\.(?:us|com)/(?:j|w|s|my|wc|meeting/register)/"# + body, "Zoom"),
        (#"https://teams\.(?:microsoft|live)\.com/(?:l/meetup-join|meet)/"# + body, "Microsoft Teams"),
        (#"https://meet\.google\.com/[a-z]{3}-[a-z]{4}-[a-z]{3}"#, "Google Meet"),
        (#"https://(?:[\w-]+\.)*webex\.com/"# + body, "Webex"),
        (#"https://(?:global\.gotomeeting\.com/join|meet\.goto\.com)/"# + body, "GoTo Meeting"),
        (#"https://chime\.aws/"# + body, "Amazon Chime"),
        (#"https://app\.slack\.com/huddle/"# + body, "Slack Huddle"),
        (#"https://whereby\.com/"# + body, "Whereby"),
        (#"https://meet\.jit\.si/"# + body, "Jitsi Meet"),
        (#"https://(?:www\.)?discord\.(?:gg|com/channels)/"# + body, "Discord"),
        (#"https://(?:v\.ringcentral\.com|meetings\.ringcentral\.com)/"# + body, "RingCentral Video"),
        (#"https://meeting\.zoho\.(?:com|eu|in)/"# + body, "Zoho Meeting"),
    ]

    private static let patterns: [(NSRegularExpression, String)] = providers.map {
        (try! NSRegularExpression(pattern: $0.pattern, options: [.caseInsensitive]), $0.platform)
    }

    /// The first meeting link in location, then URL, then notes.
    public static func extract(location: String?, url: String?, notes: String?) -> MeetingLink? {
        for text in [location, url, notes].compactMap({ $0 }) where text.contains("://") {
            let range = NSRange(text.startIndex..., in: text)
            for (pattern, platform) in patterns {
                guard let match = pattern.firstMatch(in: text, range: range),
                      let matchRange = Range(match.range, in: text) else { continue }
                var raw = String(text[matchRange])
                while raw.hasSuffix(">") { raw.removeLast() }
                if let url = URL(string: raw) {
                    return MeetingLink(url: url, platform: platform)
                }
            }
        }
        return nil
    }

    /// A calendar invite is untrusted input, so a link is opened only if it is https,
    /// carries no credentials or custom port, and on its own is still exactly a link
    /// to a known provider. That re-check keeps the host rules in one place (the
    /// patterns above) and guards against a future pattern matching too much.
    public static func isSafeToOpen(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https",
              url.user == nil, url.password == nil,
              url.port == nil || url.port == 443 else { return false }
        let text = url.absoluteString
        return extract(location: text, url: nil, notes: nil)?.url.absoluteString == text
    }
}
