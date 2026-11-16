import Foundation
@testable import CmuxClaudeLimits

/// Suspends every run until `release()` is called, so concurrency tests are deterministic.
final class GatedProcessRunner: ProcessRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [ProcessRequest] = []
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var released = false
    private let outcome: ProcessOutcome

    init(outcome: ProcessOutcome) { self.outcome = outcome }

    var requests: [ProcessRequest] { lock.withLock { recorded } }

    func run(_ request: ProcessRequest) async -> ProcessOutcome {
        lock.withLock { recorded.append(request) }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            let resume = lock.withLock { () -> Bool in
                if released { return true }
                waiters.append(cont)
                return false
            }
            if resume { cont.resume() }
        }
        return outcome
    }

    func release() {
        let pending = lock.withLock { () -> [CheckedContinuation<Void, Never>] in
            released = true
            defer { waiters = [] }
            return waiters
        }
        pending.forEach { $0.resume() }
    }
}
