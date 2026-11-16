public enum GuardVerdict: Sendable, Equatable {
    case clean
    case unparseable
    case tripped(String)
}
