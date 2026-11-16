import Foundation
import Testing
@testable import CmuxClaudeLimits

@MainActor
struct ClaudeLimitsPanelModelTests {
    let tz = TimeZone(identifier: "America/Los_Angeles")!

    private func iso(_ s: String) -> Date {
        let f = ISO8601DateFormatter()
        return f.date(from: s)!
    }

    private var fixedNow: Date { iso("2026-11-14T20:00:00Z") }

    private func makeDefaults() -> UserDefaults {
        let name = "claude-limits-panel-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func configuration(
        enabled: Bool = true,
        accounts: [ClaudeLimitsAccount]? = nil
    ) -> ClaudeLimitsConfiguration {
        ClaudeLimitsConfiguration(
            enabled: enabled,
            refreshIntervalSeconds: 300,
            claudeBinary: "~/.local/bin/claude",
            mutedColor: "#a89984",
            accounts: accounts ?? [
                ClaudeLimitsAccount(label: "personal-a", configDir: nil, style: .solo),
                ClaudeLimitsAccount(label: "personal-b", configDir: "/Users/test/.accounts/b", style: .solo),
                ClaudeLimitsAccount(label: "org", configDir: "/Users/test/.accounts/org", style: .badge, color: "#89b482"),
            ]
        )
    }

    private func makeModel(
        _ configuration: ClaudeLimitsConfiguration? = nil,
        defaults: UserDefaults? = nil
    ) -> ClaudeLimitsPanelModel {
        let fixed = fixedNow
        return ClaudeLimitsPanelModel(
            configuration: configuration ?? self.configuration(),
            defaults: defaults ?? makeDefaults(),
            timeZone: tz,
            now: { fixed }
        )
    }

    private func teamActive(scopedPercent: Double = 0) throws -> UsageSnapshot {
        var snapshot = try UsagePayloadDecoder().decode(
            Data(UsageFixtures.teamActive.utf8),
            fetchedAt: fixedNow
        )
        if scopedPercent > 0, let index = snapshot.windows.firstIndex(where: { $0.kind == .weeklyScoped }) {
            snapshot.windows[index].percent = scopedPercent
        }
        return snapshot
    }

    private let orgID = "/Users/test/.accounts/org"

    @Test func activeSnapshotHidesIdleScopedRow() throws {
        let model = makeModel()
        model.apply(states: [orgID: .ok(try teamActive())])
        let card = model.cards[2]
        #expect(card.rows.map(\.title) == ["5h", "wk"])
        #expect(card.rows[0].percent == 1)
        #expect(card.rows[0].resetText == "in 2h10m")
        #expect(card.statusText == nil)
    }

    @Test func scopedRowShownWhenPercentPositive() throws {
        let model = makeModel()
        model.apply(states: [orgID: .ok(try teamActive(scopedPercent: 3))])
        let rows = model.cards[2].rows
        #expect(rows.count == 3)
        #expect(rows[2].title == "Fable")
    }

    @Test func staleStateCarriesErrorAndAge() throws {
        let model = makeModel()
        let since = fixedNow.addingTimeInterval(-300)
        model.apply(states: [orgID: .stale(try teamActive(), error: "HTTP 429", since: since)])
        let card = model.cards[2]
        #expect(card.statusText == "stale")
        #expect(card.statusTooltip?.contains("HTTP 429") == true)
        #expect(card.statusTooltip?.contains("5m") == true)
        #expect(card.rows.count == 2)
    }

    @Test func loginNeededTooltipHasConfigDir() {
        let model = makeModel()
        let path = "/Users/test/.codex-accounts/claude/org"
        model.apply(states: [orgID: .loginNeeded(detail: path)])
        let card = model.cards[2]
        #expect(card.statusText == "login needed")
        #expect(card.statusTooltip?.contains(path) == true)
        #expect(card.rows.isEmpty)
    }

    @Test func otherStatusTexts() {
        let model = makeModel()
        model.apply(states: [
            orgID: .refreshingLogin,
            "default": .unavailable(reason: "schema changed"),
        ])
        #expect(model.cards[2].statusText == "refreshing login")
        #expect(model.cards[0].statusText == "unavailable")
        #expect(model.cards[0].statusTooltip?.contains("schema changed") == true)
        #expect(model.cards[1].statusText == "loading")
    }

    @Test func collapsePersistsAndShrinksHeight() throws {
        let defaults = makeDefaults()
        let model = makeModel(defaults: defaults)
        model.isCollapsed = true
        #expect(defaults.bool(forKey: "claudeLimits.panelCollapsed") == true)
        #expect(model.reservedHeight == 34)
        let reloaded = makeModel(defaults: defaults)
        #expect(reloaded.isCollapsed)
    }

    @Test func expandedHeightMatchesMetrics() throws {
        let accounts = (0..<4).map {
            ClaudeLimitsAccount(label: "a\($0)", configDir: "/Users/test/.accounts/\($0)", style: .solo)
        }
        let model = makeModel(configuration(accounts: accounts))
        let snapshot = try teamActive()
        model.apply(states: Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, AccountCardState.ok(snapshot)) }))
        #expect(model.reservedHeight == 242)
    }

    @Test func disabledConfigurationHidesPanel() {
        let model = makeModel()
        #expect(model.isVisible)
        model.apply(configuration: configuration(enabled: false))
        #expect(!model.isVisible)
        #expect(model.reservedHeight == 0)
    }

    @Test func reorderedAccountsFollowNewOrder() {
        let model = makeModel()
        let original = configuration()
        #expect(model.cards.map(\.id) == original.accounts.map(\.id))
        model.apply(configuration: configuration(accounts: original.accounts.reversed()))
        #expect(model.cards.map(\.id) == original.accounts.reversed().map(\.id))
    }

    @Test func duplicateAccountIDsKeepFirst() {
        let model = makeModel()
        let dup = [
            ClaudeLimitsAccount(label: "first", configDir: "/Users/test/.accounts/x", style: .solo),
            ClaudeLimitsAccount(label: "second", configDir: "/Users/test/.accounts/x", style: .badge),
            ClaudeLimitsAccount(label: "third", configDir: nil, style: .solo),
        ]
        model.apply(configuration: configuration(accounts: dup))
        #expect(model.cards.map(\.label) == ["first", "third"])
        let initial = makeModel(configuration(accounts: dup))
        #expect(initial.cards.map(\.label) == ["first", "third"])
    }

    @Test func seedRendersStaleUntilFirstState() throws {
        let model = makeModel()
        let snapshot = try teamActive()
        model.seed(cache: [orgID: CachedSnapshot(snapshot: snapshot, storedAt: fixedNow.addingTimeInterval(-600))])
        #expect(model.cards[2].statusText == "stale")
        #expect(model.cards[2].rows.count == 2)
        // A bare .loading must not wipe the seeded values.
        model.apply(states: [orgID: .loading])
        #expect(model.cards[2].statusText == "stale")
        model.apply(states: [orgID: .ok(snapshot)])
        #expect(model.cards[2].statusText == nil)
    }

    @Test func refreshAgeText() {
        let model = makeModel()
        #expect(model.refreshAgeText == nil)
        model.lastSuccessfulRefresh = fixedNow.addingTimeInterval(-120)
        #expect(model.refreshAgeText == "2m")
    }

    @Test func pastResetRendersResetAndZero() {
        let model = makeModel()
        let snapshot = UsageSnapshot(windows: [
            UsageWindow(kind: .session, percent: 80, resetsAt: fixedNow.addingTimeInterval(-60), isActive: true),
            UsageWindow(kind: .weeklyAll, percent: 5, resetsAt: fixedNow.addingTimeInterval(3 * 86_400)),
        ], fetchedAt: fixedNow.addingTimeInterval(-3600))
        model.apply(states: [orgID: .ok(snapshot)])
        let row = model.cards[2].rows[0]
        #expect(row.percent == 0)
        #expect(row.resetText == "reset")
        #expect(row.tone == .normal)
        #expect(!row.tooltip.contains("Resets reset"))
    }

    @Test func percentClampedForDisplay() {
        let model = makeModel()
        let snapshot = UsageSnapshot(windows: [
            UsageWindow(kind: .session, percent: 250, resetsAt: fixedNow.addingTimeInterval(600)),
            UsageWindow(kind: .weeklyAll, percent: .nan),
        ], fetchedAt: fixedNow)
        model.apply(states: [orgID: .ok(snapshot)])
        #expect(model.cards[2].rows[0].percent == 100)
        #expect(model.cards[2].rows[1].percent == 0)
    }
}

