public enum ClaudeConfigDirError: Error, Equatable {
    case notAbsolute(String)
}

/// Normalizes a configured `CLAUDE_CONFIG_DIR` string: expands a leading `~`,
/// strips trailing slashes, requires an absolute path. Symlinks are not resolved.
public struct ClaudeConfigDirPath: Sendable {
    private let home: String

    public init(home: String) {
        self.home = home
    }

    public func normalized(_ raw: String?) throws -> String? {
        guard var path = raw, !path.isEmpty else { return nil }
        if path == "~" {
            path = home
        } else if path.hasPrefix("~/") {
            path = home + String(path.dropFirst(1))
        }
        while path.count > 1, path.hasSuffix("/") {
            path.removeLast()
        }
        guard path.hasPrefix("/") else {
            throw ClaudeConfigDirError.notAbsolute(raw ?? path)
        }
        return path
    }
}
