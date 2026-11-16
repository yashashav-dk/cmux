import Foundation
@testable import CmuxClaudeLimits

final class FakeProcessRunner: ProcessRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [ProcessRequest] = []
    private let outcome: ProcessOutcome

    init(outcome: ProcessOutcome) {
        self.outcome = outcome
    }

    var requests: [ProcessRequest] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    func run(_ request: ProcessRequest) async -> ProcessOutcome {
        lock.withLock { recorded.append(request) }
        return outcome
    }
}
