import Foundation
import Testing
@testable import CmuxClaudeLimits

@Suite struct ResetTextFormatterTests {
    private let now = Date(timeIntervalSince1970: 1_794_686_400) // 2026-11-14T20:00:00Z
    private func iso(_ s: String) -> Date { ISO8601DateFormatter().date(from: s)! }
    private func fmt(_ tz: String) -> ResetTextFormatter {
        ResetTextFormatter(timeZone: TimeZone(identifier: tz)!)
    }
    private func window(_ date: Date?) -> UsageWindow {
        UsageWindow(kind: .session, percent: 10, resetsAt: date)
    }

    @Test func nowIsAsExpected() {
        #expect(now == iso("2026-11-14T20:00:00Z"))
    }

    @Test func idleCases() {
        let f = fmt("America/Los_Angeles")
        #expect(f.text(for: nil, now: now) == "idle")
        #expect(f.text(for: window(nil), now: now) == "idle")
    }

    @Test func relativeUnder24h() {
        let f = fmt("America/Los_Angeles")
        #expect(f.text(for: window(now + 47 * 60), now: now) == "in 47m")
        #expect(f.text(for: window(now + 130 * 60), now: now) == "in 2h10m")
        #expect(f.text(for: window(now + 120 * 60), now: now) == "in 2h")
        #expect(f.text(for: window(now + (23 * 60 + 59) * 60), now: now) == "in 23h59m")
    }

    @Test func absoluteFrom24h() {
        let f = fmt("America/Los_Angeles")
        #expect(f.text(for: window(now + 24 * 3600), now: now) == "Sun 12pm")
        #expect(f.text(for: window(iso("2026-11-21T14:00:00Z")), now: now) == "Sat 6am")
        #expect(f.text(for: window(iso("2026-11-20T00:30:00Z")), now: now) == "Thu 4:30pm")
        #expect(f.text(for: window(iso("2026-11-21T08:00:00Z")), now: now) == "Sat 12am")
    }

    @Test func otherTimeZone() {
        let f = fmt("Asia/Kolkata")
        #expect(f.text(for: window(iso("2026-11-21T14:00:00Z")), now: now) == "Sat 7:30pm")
        #expect(f.text(for: window(iso("2026-11-20T00:30:00Z")), now: now) == "Fri 6am")
    }

    @Test func pastIsReset() {
        #expect(fmt("America/Los_Angeles").text(for: window(now - 60), now: now) == "reset")
    }

    @Test func tooltip() {
        let f = fmt("America/Los_Angeles")
        let w = UsageWindow(kind: .session, percent: 42.4, resetsAt: now + 47 * 60)
        #expect(f.tooltip(for: w, lastFetched: iso("2026-11-14T19:58:00Z"), now: now)
            == "Resets in 47m · 42% used · fetched 2m ago")
    }
}
