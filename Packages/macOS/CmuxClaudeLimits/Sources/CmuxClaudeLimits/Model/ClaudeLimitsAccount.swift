public struct ClaudeLimitsAccount: Sendable, Equatable, Codable, Identifiable {
    public var label: String
    public var configDir: String?
    public var style: AccountLabelStyle
    public var color: String?

    public init(
        label: String,
        configDir: String? = nil,
        style: AccountLabelStyle = .badge,
        color: String? = nil
    ) {
        self.label = label
        self.configDir = configDir
        self.style = style
        self.color = color
    }

    public var id: String { configDir ?? "default" }
}
