public struct BarToneResolver: Sendable {
    public init() {}

    /// Thresholds use the raw percent (not clamped): out-of-range values map naturally
    /// (>= 95 critical, < 80 normal including negatives).
    public func tone(for window: UsageWindow) -> BarTone {
        switch window.severity {
        case .normal:
            return .normal
        case .other(let raw):
            switch raw {
            case "warning", "elevated", "approaching_limit": return .warning
            case "critical", "exceeded", "rejected": return .critical
            default:
                if window.percent >= 95 { return .critical }
                if window.percent >= 80 { return .warning }
                return .normal
            }
        }
    }
}
