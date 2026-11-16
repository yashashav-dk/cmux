import Foundation
import Testing

/// Ordered record of calls across fakes, so tests can assert sequencing.
final class CallLog: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String] = []

    func append(_ entry: String) {
        lock.withLock { items.append(entry) }
    }

    var entries: [String] {
        lock.withLock { items }
    }
}

final class Recorder<Element: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [Element] = []

    func append(_ item: Element) {
        lock.withLock { items.append(item) }
    }

    var all: [Element] {
        lock.withLock { items }
    }

    var count: Int {
        lock.withLock { items.count }
    }
}

/// Yields until `condition` holds. The wall-clock bound only matters on failure;
/// nothing here sleeps.
@discardableResult
func waitUntil(
    _ description: String,
    timeout: Duration = .seconds(5),
    sourceLocation: SourceLocation = #_sourceLocation,
    _ condition: () async -> Bool
) async -> Bool {
    let wall = ContinuousClock()
    let deadline = wall.now.advanced(by: timeout)
    while wall.now < deadline {
        if await condition() { return true }
        await Task.yield()
    }
    if await condition() { return true }
    Issue.record(Comment(rawValue: "timed out waiting for \(description)"), sourceLocation: sourceLocation)
    return false
}
