public import Foundation

public struct UsageSnapshot: Sendable, Equatable, Codable {
    public var windows: [UsageWindow]
    public var fetchedAt: Date

    public init(windows: [UsageWindow], fetchedAt: Date) {
        self.windows = windows
        self.fetchedAt = fetchedAt
    }

    public var session: UsageWindow? { windows.first { $0.kind == .session } }
    public var weekly: UsageWindow? { windows.first { $0.kind == .weeklyAll } }
    public var scoped: [UsageWindow] { windows.filter { $0.kind == .weeklyScoped } }
}
