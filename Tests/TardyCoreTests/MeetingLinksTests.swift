import Foundation
import Testing
@testable import TardyCore

@Suite struct MeetingLinksTests {
    @Test(arguments: [
        ("https://acme.zoom.us/j/123456789?pwd=abc", "Zoom"),
        ("https://zoomgov.com/j/1234", "Zoom"),
        ("https://teams.microsoft.com/l/meetup-join/19%3ameeting_abc%40thread.v2/0", "Microsoft Teams"),
        ("https://teams.live.com/meet/9876543210", "Microsoft Teams"),
        ("https://meet.google.com/abc-defg-hij", "Google Meet"),
        ("https://acme.webex.com/meet/someone", "Webex"),
        ("https://meet.goto.com/123456789", "GoTo Meeting"),
        ("https://global.gotomeeting.com/join/123456789", "GoTo Meeting"),
        ("https://chime.aws/1234567890", "Amazon Chime"),
        ("https://app.slack.com/huddle/T123/C456", "Slack Huddle"),
        ("https://whereby.com/team-standup", "Whereby"),
        ("https://meet.jit.si/SomeRoom", "Jitsi Meet"),
        ("https://discord.gg/abc123", "Discord"),
        ("https://v.ringcentral.com/join/123456", "RingCentral Video"),
        ("https://meeting.zoho.com/meeting/join?key=1", "Zoho Meeting"),
    ])
    func recognizesProvider(url: String, platform: String) {
        let link = MeetingLinks.extract(location: nil, url: nil, notes: "Join: \(url) thanks")
        #expect(link?.platform == platform)
        #expect(link?.url.absoluteString == url)
    }

    @Test(arguments: [
        "https://attacker-zoom.us/j/123",
        "https://myzoom.us/j/123",
        "https://evilzoomgov.com/j/123",
        "https://evilwebex.com/meet/someone",
        "https://zoom.us.evil.com/j/123",
        "https://zoom.us@evil.com/j/123",
        "https://acme.zoom.us:8443/j/123",
    ])
    func rejectsLookalikeHosts(url: String) {
        #expect(MeetingLinks.extract(location: url, url: nil, notes: nil) == nil)
    }

    @Test(arguments: [
        "https://zoom.us/j/1",
        "https://us02web.zoom.us/j/1",
        "https://a.b-c.zoom.us/j/1",
        "https://webex.com/meet/x",
        "https://acme.my.webex.com/meet/x",
    ])
    func acceptsRealSubdomains(url: String) {
        #expect(MeetingLinks.extract(location: url, url: nil, notes: nil)?.url.absoluteString == url)
    }

    @Test func htmlNotesDoNotSwallowMarkup() {
        let notes = #"<a href="https://acme.zoom.us/j/42">Join</a>"#
        #expect(MeetingLinks.extract(location: nil, url: nil, notes: notes)?.url.absoluteString
                == "https://acme.zoom.us/j/42")
    }

    @Test func locationBeatsNotes() {
        let link = MeetingLinks.extract(location: "https://meet.google.com/abc-defg-hij",
                                        url: nil, notes: "https://acme.zoom.us/j/1")
        #expect(link?.platform == "Google Meet")
    }

    @Test func ignoresPlainText() {
        #expect(MeetingLinks.extract(location: "Room 101", url: nil, notes: "no links here") == nil)
    }

    @Test func onlyHttpsIsSafe() {
        #expect(MeetingLinks.isSafeToOpen(URL(string: "https://zoom.us/j/1")!))
        #expect(!MeetingLinks.isSafeToOpen(URL(string: "http://zoom.us/j/1")!))
        #expect(!MeetingLinks.isSafeToOpen(URL(string: "file:///etc/passwd")!))
    }
}
