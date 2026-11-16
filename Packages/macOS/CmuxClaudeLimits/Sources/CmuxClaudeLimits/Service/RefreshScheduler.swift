public import Foundation

/// Timing rules: first fetch shortly after launch, then the refresh interval with
/// symmetric jitter, and a debounce on the manual refresh button.
public struct RefreshScheduler: Sendable {
    public var interval: TimeInterval
    public var jitterFraction: Double
    public var initialDelay: TimeInterval
    public var manualDebounce: TimeInterval

    public init(
        interval: TimeInterval,
        jitterFraction: Double = 0.1,
        initialDelay: TimeInterval = 5,
        manualDebounce: TimeInterval = 5
    ) {
        self.interval = interval
        self.jitterFraction = jitterFraction
        self.initialDelay = initialDelay
        self.manualDebounce = manualDebounce
    }

    /// `interval * (1 + (random * 2 - 1) * jitter)` for `random` in `0...1`.
    public func nextDelay(random: Double) -> TimeInterval {
        let unit = min(max(random, 0), 1)
        return interval + interval * (unit * 2 - 1) * jitterFraction
    }

    public func manualAllowed(lastManual: Date?, now: Date) -> Bool {
        guard let lastManual else { return true }
        return now.timeIntervalSince(lastManual) >= manualDebounce
    }
}
