public import Foundation

public struct UsageWindow: Sendable, Equatable, Codable {
    public var kind: UsageLimitKind
    public var percent: Double
    public var resetsAt: Date?
    public var severity: UsageSeverity
    public var isActive: Bool
    public var scopeLabel: String?

    public init(
        kind: UsageLimitKind,
        percent: Double,
        resetsAt: Date? = nil,
        severity: UsageSeverity = .normal,
        isActive: Bool = false,
        scopeLabel: String? = nil
    ) {
        self.kind = kind
        self.percent = percent
        self.resetsAt = resetsAt
        self.severity = severity
        self.isActive = isActive
        self.scopeLabel = scopeLabel
    }
}
