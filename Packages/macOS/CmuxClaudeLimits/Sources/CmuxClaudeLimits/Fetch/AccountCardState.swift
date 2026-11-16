public import Foundation

/// What one account's card shows. Never carries credentials.
public enum AccountCardState: Sendable, Equatable {
    case loading
    case ok(UsageSnapshot)
    /// Last good snapshot kept after a failed fetch; `since` is when it went stale.
    case stale(UsageSnapshot, error: String, since: Date)
    case refreshingLogin
    /// `detail` names the profile's config dir (`~/.claude` for the default profile).
    case loginNeeded(detail: String)
    case unavailable(reason: String)
}
