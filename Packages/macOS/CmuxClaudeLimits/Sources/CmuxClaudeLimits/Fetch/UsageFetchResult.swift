public import Foundation

/// Outcome of one usage GET. Carries no credentials.
public enum UsageFetchResult: Sendable, Equatable {
    case success(Data)
    case unauthorized
    case rateLimited(retryAfter: TimeInterval?)
    /// Any other non-2xx status (5xx in practice).
    case serverError(Int)
    case transport(String)
}
