public enum UsageSeverity: Sendable, Equatable, Codable {
    case normal
    case other(String)

    public init(raw: String) {
        self = raw == "normal" ? .normal : .other(raw)
    }

    public var raw: String {
        switch self {
        case .normal: return "normal"
        case .other(let value): return value
        }
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(raw: try container.decode(String.self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(raw)
    }
}
