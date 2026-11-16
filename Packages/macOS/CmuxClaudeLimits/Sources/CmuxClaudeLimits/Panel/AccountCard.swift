public struct AccountCard: Sendable, Equatable, Identifiable {
    public var id: String
    public var label: String
    public var style: AccountLabelStyle
    public var color: String?
    public var state: AccountCardState
    public var rows: [RowPresentation]
    /// "loading" | "stale" | "refreshing login" | "login needed" | "unavailable" | nil
    public var statusText: String?
    public var statusTooltip: String?

    public init(
        id: String,
        label: String,
        style: AccountLabelStyle,
        color: String?,
        state: AccountCardState,
        rows: [RowPresentation],
        statusText: String?,
        statusTooltip: String?
    ) {
        self.id = id
        self.label = label
        self.style = style
        self.color = color
        self.state = state
        self.rows = rows
        self.statusText = statusText
        self.statusTooltip = statusTooltip
    }

    /// Stale cards render their last good values dimmed.
    public var isDimmed: Bool {
        if case .stale = state { return true }
        return false
    }
}
