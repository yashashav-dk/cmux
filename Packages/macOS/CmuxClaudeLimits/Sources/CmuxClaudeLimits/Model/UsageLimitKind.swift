public enum UsageLimitKind: String, Sendable, Codable, Equatable {
    case session
    case weeklyAll = "weekly_all"
    case weeklyScoped = "weekly_scoped"
}
