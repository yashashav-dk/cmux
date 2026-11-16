public import Foundation

public struct CachedSnapshot: Sendable, Equatable, Codable {
    public var snapshot: UsageSnapshot
    public var storedAt: Date

    public init(snapshot: UsageSnapshot, storedAt: Date) {
        self.snapshot = snapshot
        self.storedAt = storedAt
    }
}

public extension UsageWindow {
    /// A window whose reset time has passed renders as 0% and inactive. `resetsAt` is kept
    /// so the formatter can print "reset".
    func normalized(now: Date) -> UsageWindow {
        guard let resetsAt, resetsAt < now else { return self }
        var copy = self
        copy.percent = 0
        copy.isActive = false
        return copy
    }
}
