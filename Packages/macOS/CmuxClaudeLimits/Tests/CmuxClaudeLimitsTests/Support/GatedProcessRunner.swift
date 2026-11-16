import Foundation
@testable import CmuxClaudeLimits

/// Suspends gated runs until `release()` is called, so concurrency tests are deterministic.
final class GatedProcessRunner: ProcessRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [ProcessRequest] = []
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var released = false
    private let outcome: ProcessOutcome
    private let inner: (any ProcessRunning)?
    private let shouldGate: @Sendable (ProcessRequest) -> Bool

    /// Gates every run and answers each with `outcome`.
    init(outcome: ProcessOutcome) {
        self.outcome = outcome
        self.inner = nil
        self.shouldGate = { _ in true }
    }

    /// Gates only runs matching `gating`; every run is answered by `inner`.
    init(wrapping inner: any ProcessRunning, gating: @escaping @Sendable (ProcessRequest) -> Bool) {
        self.outcome = ProcessOutcome()
        self.inner = inner
        self.shouldGate = gating
    }

    var requests: [ProcessRequest] { lock.withLock { recorded } }
    var pendingCount: Int { lock.withLock { waiters.count } }

    func run(_ request: ProcessRequest) async -> ProcessOutcome {
        lock.withLock { recorded.append(request) }
        if shouldGate(request) {
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                let resume = lock.withLock { () -> Bool in
                    if released { return true }
                    waiters.append(cont)
                    return false
                }
                if resume { cont.resume() }
            }
        }
        if let inner { return await inner.run(request) }
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
