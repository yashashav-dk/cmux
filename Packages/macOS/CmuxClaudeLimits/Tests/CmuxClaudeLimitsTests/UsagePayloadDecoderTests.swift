import Foundation
import Testing
@testable import CmuxClaudeLimits

@Suite struct UsagePayloadDecoderTests {
    private let fetchedAt = Date(timeIntervalSince1970: 1_700_000_000)

    private func decode(_ json: String) throws -> UsageSnapshot {
        try UsagePayloadDecoder().decode(Data(json.utf8), fetchedAt: fetchedAt)
    }

    private func date(_ iso: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: iso)
    }

    @Test func teamActive() throws {
        let s = try decode(UsageFixtures.teamActive)
        #expect(s.fetchedAt == fetchedAt)
        #expect(s.windows.count == 3)
        #expect(s.session?.percent == 1)
        #expect(s.session?.isActive == true)
        #expect(s.session?.resetsAt == date("2026-11-14T22:10:00.502237+00:00"))
        #expect(s.session?.resetsAt != nil)
        #expect(s.weekly?.percent == 0)
        #expect(s.weekly?.resetsAt == date("2026-11-21T08:00:00.502262+00:00"))
        #expect(s.scoped == [UsageWindow(
            kind: .weeklyScoped, percent: 0,
            resetsAt: date("2026-11-21T08:00:00.502483+00:00"),
            severity: .normal, isActive: false, scopeLabel: "Fable")])
        #expect(s.windows.allSatisfy { $0.severity == .normal })
    }

    @Test func idleNullFiveHour() throws {
        let s = try decode(UsageFixtures.idleNullFiveHour)
        #expect(s.session == nil)
        #expect(s.weekly != nil)
        #expect(s.weekly?.percent == 4)
    }

    @Test func idleZeroSession() throws {
        let s = try decode(UsageFixtures.idleZeroSession)
        #expect(s.session?.resetsAt == nil)
        #expect(s.session?.percent == 0)
    }

    @Test func legacyOnly() throws {
        let s = try decode(UsageFixtures.legacyOnly)
        #expect(s.windows.map(\.kind) == [.session, .weeklyAll])
        #expect(s.session?.percent == 37.5)
        #expect(s.weekly?.percent == 12)
        #expect(s.session?.resetsAt == date("2026-11-14T22:10:00.502237+00:00"))
    }

    @Test func noiseIsIgnoredAndSeverityPreserved() throws {
        let s = try decode(UsageFixtures.noise)
        #expect(s.weekly?.severity == .other("elevated"))
        #expect(s.session?.severity == .normal)
    }

    @Test func malformedRowDroppedNumericRowKept() throws {
        let s = try decode(UsageFixtures.noise)
        #expect(s.windows.count == 3)
        #expect(s.scoped.first?.percent == 12.5)
        #expect(s.scoped.first?.resetsAt == nil)
        #expect(s.scoped.first?.scopeLabel == "Fable")
    }

    @Test func emptyLimitsWithoutLegacyThrows() {
        #expect(throws: UsageDecodeError.noUsageFields) {
            try decode(UsageFixtures.emptyLimits)
        }
    }

    @Test func nonJSONThrows() {
        #expect(throws: UsageDecodeError.notJSON) {
            try UsagePayloadDecoder().decode(Data("nope".utf8), fetchedAt: fetchedAt)
        }
        #expect(throws: UsageDecodeError.notJSON) {
            try decode("[1,2]")
        }
    }

    @Test func plainIsoDateFallback() throws {
        let s = try decode(#"{"five_hour":{"utilization":2,"resets_at":"2026-11-14T22:10:00Z"}}"#)
        #expect(s.session?.resetsAt == ISO8601DateFormatter().date(from: "2026-11-14T22:10:00Z"))
    }

    @Test func configurationDefaults() {
        let c = ClaudeLimitsConfiguration.default
        #expect(c.enabled == false)
        #expect(c.refreshIntervalSeconds == 300)
        #expect(c.claudeBinary == "~/.local/bin/claude")
        #expect(c.mutedColor == "#a89984")
        #expect(c.accounts.isEmpty)
        var low = c
        low.refreshIntervalSeconds = 10
        #expect(low.effectiveRefreshInterval == 60)
        #expect(c.effectiveRefreshInterval == 300)
        #expect(ClaudeLimitsAccount(label: "a", configDir: nil, style: .solo, color: nil).id == "default")
    }
}
