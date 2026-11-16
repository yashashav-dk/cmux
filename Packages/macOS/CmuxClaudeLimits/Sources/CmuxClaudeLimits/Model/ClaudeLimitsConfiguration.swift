public import Foundation

public struct ClaudeLimitsConfiguration: Sendable, Equatable, Codable {
    public var enabled: Bool
    public var refreshIntervalSeconds: Int
    public var claudeBinary: String
    public var mutedColor: String
    public var accounts: [ClaudeLimitsAccount]

    public init(
        enabled: Bool,
        refreshIntervalSeconds: Int,
        claudeBinary: String,
        mutedColor: String,
        accounts: [ClaudeLimitsAccount]
    ) {
        self.enabled = enabled
        self.refreshIntervalSeconds = refreshIntervalSeconds
        self.claudeBinary = claudeBinary
        self.mutedColor = mutedColor
        self.accounts = accounts
    }

    public static let `default` = ClaudeLimitsConfiguration(
        enabled: false,
        refreshIntervalSeconds: 300,
        claudeBinary: "~/.local/bin/claude",
        mutedColor: "#a89984",
        accounts: []
    )

    public var effectiveRefreshInterval: TimeInterval {
        max(60, Double(refreshIntervalSeconds))
    }
}
