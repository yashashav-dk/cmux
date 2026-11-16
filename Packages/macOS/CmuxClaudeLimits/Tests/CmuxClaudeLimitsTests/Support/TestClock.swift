import Foundation

/// Virtual clock: sleepers resume only when `advance(by:)` passes their deadline,
/// and a cancelled sleeper throws immediately. `date` maps virtual time onto a
/// fixed wall-clock epoch for code that reads `Date`.
final class TestClock: Clock, @unchecked Sendable {
    struct Instant: InstantProtocol {
        var offset: Duration

        func advanced(by duration: Duration) -> Instant { Instant(offset: offset + duration) }
        func duration(to other: Instant) -> Duration { other.offset - offset }
        static func < (lhs: Instant, rhs: Instant) -> Bool { lhs.offset < rhs.offset }
    }

    private struct Sleeper {
        let id: Int
        let deadline: Instant
        let continuation: CheckedContinuation<Void, any Error>
    }

    private enum Admission {
        case wait
        case resume
        case cancel
    }

    let epoch: Date
    private let lock = NSLock()
    private var current = Instant(offset: .zero)
    private var sleepers: [Sleeper] = []
    private var nextID = 0

    init(epoch: Date = Date(timeIntervalSince1970: 1_800_000_000)) {
        self.epoch = epoch
    }

    var now: Instant { lock.withLock { current } }
    var minimumResolution: Duration { .zero }

    var date: Date {
        let components = now.offset.components
        let seconds = Double(components.seconds) + Double(components.attoseconds) / 1e18
        return epoch.addingTimeInterval(seconds)
    }

    var sleeperCount: Int { lock.withLock { sleepers.count } }

    /// Deadlines of the registered sleepers, as offsets from the clock's zero.
    var pendingDeadlines: [Duration] {
        lock.withLock { sleepers.map(\.deadline.offset).sorted() }
    }

    func sleep(until deadline: Instant, tolerance: Duration?) async throws {
        let id = lock.withLock { () -> Int in
            nextID += 1
            return nextID
        }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                let admission = lock.withLock { () -> Admission in
                    if Task.isCancelled { return .cancel }
                    if deadline <= current { return .resume }
                    sleepers.append(Sleeper(id: id, deadline: deadline, continuation: continuation))
                    return .wait
                }
                switch admission {
                case .wait: break
                case .resume: continuation.resume()
                case .cancel: continuation.resume(throwing: CancellationError())
                }
            }
        } onCancel: {
            let cancelled = self.lock.withLock { () -> CheckedContinuation<Void, any Error>? in
                guard let index = self.sleepers.firstIndex(where: { $0.id == id }) else { return nil }
                return self.sleepers.remove(at: index).continuation
            }
            cancelled?.resume(throwing: CancellationError())
        }
    }

    func advance(by duration: Duration) {
        let due = lock.withLock { () -> [Sleeper] in
            current = current.advanced(by: duration)
            let due = sleepers.filter { $0.deadline <= current }
            sleepers.removeAll { $0.deadline <= current }
            return due
        }
        due.forEach { $0.continuation.resume() }
    }
}
