public import Foundation

public struct ClaudeCredentials: Sendable, Equatable, CustomDebugStringConvertible {
    public var accessToken: String
    public var refreshToken: String?
    public var expiresAt: Date?

    public init(accessToken: String, refreshToken: String? = nil, expiresAt: Date? = nil) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
    }

    public var debugDescription: String { "ClaudeCredentials(<redacted>)" }
}
