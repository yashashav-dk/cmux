public import Foundation

public enum RefreshOutcome: Sendable, Equatable {
    case refreshed
    case rateLimited(nextAllowedAt: Date)
    case loginNeeded(String)
    case guardTripped(String)
    case disabled
}
