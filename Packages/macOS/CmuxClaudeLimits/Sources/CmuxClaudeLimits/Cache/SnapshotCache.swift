public import Foundation

/// Last good snapshot per account. Holds percentages and timestamps only, never tokens.
public actor SnapshotCache {
    private let fileURL: URL
    private let fileManager: FileManager

    public init(fileURL: URL, fileManager: FileManager = .default) {
        self.fileURL = fileURL
        self.fileManager = fileManager
    }

    public func load() -> [String: CachedSnapshot] {
        guard let data = fileManager.contents(atPath: fileURL.path) else { return [:] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([String: CachedSnapshot].self, from: data)) ?? [:]
    }

    public func store(_ snapshot: UsageSnapshot, for accountID: String) {
        var all = load()
        all[accountID] = CachedSnapshot(snapshot: snapshot, storedAt: Date())
        write(all)
    }

    public func remove(accountID: String) {
        var all = load()
        guard all.removeValue(forKey: accountID) != nil else { return }
        write(all)
    }

    private func write(_ all: [String: CachedSnapshot]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(all) else { return }
        let directory = fileURL.deletingLastPathComponent()
        let temp = directory.appendingPathComponent(".\(fileURL.lastPathComponent).\(UUID().uuidString).tmp")
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            guard fileManager.createFile(
                atPath: temp.path,
                contents: data,
                attributes: [.posixPermissions: 0o600]
            ) else { return }
            if fileManager.fileExists(atPath: fileURL.path) {
                _ = try fileManager.replaceItemAt(fileURL, withItemAt: temp)
            } else {
                try fileManager.moveItem(at: temp, to: fileURL)
            }
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        } catch {
            try? fileManager.removeItem(at: temp)
        }
    }
}
