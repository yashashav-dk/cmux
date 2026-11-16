import CmuxSettings
import Foundation
import Testing
@testable import CmuxClaudeLimits

@Suite struct ClaudeLimitsSettingsKeyTests {
    static var sample: [String: Any] { [
        "enabled": true,
        "refreshIntervalSeconds": 300,
        "claudeBinary": "~/.local/bin/claude",
        "mutedColor": "#a89984",
        "accounts": [
            ["label": "personal-a", "configDir": NSNull(), "style": "solo"],
            ["label": "personal-b", "configDir": "~/.claude-alt/b", "style": "solo"],
            ["label": "team-a", "configDir": "~/.claude-alt/a", "style": "badge", "color": "#89b482"],
            ["label": "team-b", "configDir": "~/.claude-alt/c", "style": "badge", "color": "#7daea3"],
        ],
    ] }

    @Test func decodesFullConfiguration() throws {
        let config = try #require(ClaudeLimitsConfiguration.decodeFromJSON(Self.sample))
        #expect(config.enabled)
        #expect(config.accounts.count == 4)
        #expect(config.accounts[0].id == "default")
        #expect(config.accounts[0].configDir == nil)
        #expect(config.accounts[2].style == .badge)
        #expect(config.accounts[2].color == "#89b482")
    }

    @Test func clampsRefreshIntervalToSixtySeconds() throws {
        var object = Self.sample
        object["refreshIntervalSeconds"] = 30
        let config = try #require(ClaudeLimitsConfiguration.decodeFromJSON(object))
        #expect(config.refreshIntervalSeconds == 60)
    }

    @Test func missingFieldsFallBackToDefaults() throws {
        let config = try #require(ClaudeLimitsConfiguration.decodeFromJSON([String: Any]()))
        #expect(config == ClaudeLimitsConfiguration.default)
    }

    @Test func ignoresUnknownKeysAndDropsEmptyLabels() throws {
        let object: [String: Any] = [
            "enabled": true,
            "somethingNew": 1,
            "accounts": [
                ["label": "", "configDir": "~/.claude-alt/x"],
                ["label": "ok", "email": "ignored", "style": "pill"],
                "not-an-object",
            ],
        ]
        let config = try #require(ClaudeLimitsConfiguration.decodeFromJSON(object))
        #expect(config.accounts.map(\.label) == ["ok"])
        #expect(config.accounts[0].style == .solo)
    }

    @Test func roundTripsThroughJSON() throws {
        let config = try #require(ClaudeLimitsConfiguration.decodeFromJSON(Self.sample))
        let again = ClaudeLimitsConfiguration.decodeFromJSON(config.encodeForJSON())
        #expect(again == config)
    }

    @Test func nilAndNonObjectDecodeToNil() {
        #expect(ClaudeLimitsConfiguration.decodeFromJSON(nil) == nil)
        #expect(ClaudeLimitsConfiguration.decodeFromJSON("nope") == nil)
    }

    @Test func keyIsClaudeLimitsWithDefault() {
        let key = ClaudeLimitsSettingsKey.configuration
        #expect(key.id == "claudeLimits")
        #expect(key.defaultValue == ClaudeLimitsConfiguration.default)
    }
}
