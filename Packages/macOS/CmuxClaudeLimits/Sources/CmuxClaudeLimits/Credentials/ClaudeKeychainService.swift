import CryptoKit
import Foundation

public struct ClaudeKeychainService: Sendable {
    public static let defaultService = "Claude Code-credentials"

    /// `nil` config dir is the default profile (variable unset). Any explicit path,
    /// including the home default, maps to a hashed service.
    public static func serviceName(configDir: String?) -> String {
        guard let configDir else { return defaultService }
        let digest = SHA256.hash(data: Data(configDir.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return "\(defaultService)-\(hex.prefix(8))"
    }
}
