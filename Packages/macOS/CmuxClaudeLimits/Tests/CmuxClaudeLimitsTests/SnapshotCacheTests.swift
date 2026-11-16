import Foundation
import Testing
@testable import CmuxClaudeLimits

@Suite struct SnapshotCacheTests {
    private func tempFile() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("cmux-limits-cache-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("nested/cache.json")
    }

    private let snapshot = UsageSnapshot(
        windows: [
            UsageWindow(kind: .session, percent: 12, resetsAt: Date(timeIntervalSince1970: 1_800_000_000)),
            UsageWindow(kind: .weeklyAll, percent: 3, resetsAt: nil, severity: .other("elevated"), isActive: true),
        ],
        fetchedAt: Date(timeIntervalSince1970: 1_799_999_000)
    )

    @Test func storeThenLoadRoundTrips() async {
        let url = tempFile()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent().deletingLastPathComponent()) }
        let cache = SnapshotCache(fileURL: url)
        await cache.store(snapshot, for: "a")
        let loaded = await SnapshotCache(fileURL: url).load()
        #expect(loaded["a"]?.snapshot == snapshot)
    }

    @Test func fileHasNoTokensAndIsOwnerOnly() async throws {
        let url = tempFile()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent().deletingLastPathComponent()) }
        let cache = SnapshotCache(fileURL: url)
        await cache.store(snapshot, for: "a")
        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(!text.contains("accessToken"))
        #expect(!text.contains("refreshToken"))
        let perms = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int
        #expect(perms == 0o600)
    }

    @Test func corruptFileLoadsEmpty() async throws {
        let url = tempFile()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent().deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{not json".utf8).write(to: url)
        let loaded = await SnapshotCache(fileURL: url).load()
        #expect(loaded.isEmpty)
    }

    @Test func missingFileLoadsEmpty() async {
        let loaded = await SnapshotCache(fileURL: tempFile()).load()
        #expect(loaded.isEmpty)
    }

    @Test func removeDropsOnlyThatAccount() async {
        let url = tempFile()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent().deletingLastPathComponent()) }
        let cache = SnapshotCache(fileURL: url)
        await cache.store(snapshot, for: "a")
        await cache.store(snapshot, for: "b")
        await cache.remove(accountID: "a")
        let loaded = await cache.load()
        #expect(Set(loaded.keys) == ["b"])
    }

    @Test func normalizedPastWindowResetsToZero() {
        let now = Date(timeIntervalSince1970: 1_000)
        let past = UsageWindow(kind: .session, percent: 80, resetsAt: now - 60, isActive: true)
        let n = past.normalized(now: now)
        #expect(n.percent == 0)
        #expect(n.isActive == false)
        #expect(n.resetsAt == past.resetsAt)
        let future = UsageWindow(kind: .session, percent: 80, resetsAt: now + 60, isActive: true)
        #expect(future.normalized(now: now) == future)
    }
}
