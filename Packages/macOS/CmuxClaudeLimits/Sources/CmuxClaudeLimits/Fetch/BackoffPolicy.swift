public import Foundation

/// Exponential backoff for 429 / 5xx / network failures: `base * 2^(n-1)`, capped,
/// and a server-provided `Retry-After` wins when it is longer.
public struct BackoffPolicy: Sendable, Equatable {
    public var base: TimeInterval
    public var cap: TimeInterval

    public init(base: TimeInterval = 60, cap: TimeInterval = 1800) {
        self.base = base
        self.cap = cap
    }

    public func delay(consecutiveFailures: Int, retryAfter: TimeInterval?) -> TimeInterval {
        let exponent = min(max(consecutiveFailures, 1) - 1, 32)
        let exponential = min(cap, base * pow(2, Double(exponent)))
        guard let retryAfter, retryAfter > exponential else { return exponential }
        return retryAfter
    }
}
