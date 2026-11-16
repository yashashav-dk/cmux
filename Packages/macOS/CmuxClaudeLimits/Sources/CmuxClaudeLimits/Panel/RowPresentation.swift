public struct RowPresentation: Sendable, Equatable, Identifiable {
    public var id: String
    /// "5h" | "wk" | scope label
    public var title: String
    /// Display percent, already clamped to 0...100 (non-finite becomes 0).
    public var percent: Double
    public var resetText: String
    public var tooltip: String
    public var tone: BarTone

    public init(
        id: String,
        title: String,
        percent: Double,
        resetText: String,
        tooltip: String,
        tone: BarTone
    ) {
        self.id = id
        self.title = title
        self.percent = percent
        self.resetText = resetText
        self.tooltip = tooltip
        self.tone = tone
    }
}
