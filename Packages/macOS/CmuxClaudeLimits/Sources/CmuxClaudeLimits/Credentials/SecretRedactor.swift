import Foundation

public struct SecretRedactor: Sendable {
    private static let patterns: [(String, String)] = [
        (#"(?i)("(?:accessToken|refreshToken)"\s*:\s*)"[^"]*""#, "$1\"<redacted>\""),
        (#"(?i)Bearer\s+[A-Za-z0-9._~+/=-]+"#, "Bearer <redacted>"),
        (#"sk-ant-[A-Za-z0-9_-]+"#, "<redacted>"),
    ]

    public init() {}

    public func redact(_ text: String) -> String {
        var result = text
        for (pattern, template) in Self.patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: template)
        }
        return result
    }
}
