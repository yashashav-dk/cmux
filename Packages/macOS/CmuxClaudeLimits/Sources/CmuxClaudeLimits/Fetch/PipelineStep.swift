public import Foundation

/// Result of one pipeline run: the card state and, after a failure, how long to wait
/// before the next attempt (`nil` means the regular refresh interval).
public struct PipelineStep: Sendable, Equatable {
    public var state: AccountCardState
    public var retryDelay: TimeInterval?

    public init(state: AccountCardState, retryDelay: TimeInterval? = nil) {
        self.state = state
        self.retryDelay = retryDelay
    }
}
