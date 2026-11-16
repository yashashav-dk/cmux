public import Foundation

/// Reads a profile's stored login through `/usr/bin/security`. Never uses the
/// Security framework directly, so no per-item Keychain prompt is triggered.
public struct KeychainCredentialReader: Sendable {
    private let runner: any ProcessRunning
    private let securityPath: String
    private let timeout: TimeInterval

    public init(
        runner: any ProcessRunning,
        securityPath: String = "/usr/bin/security",
        timeout: TimeInterval = 5
    ) {
        self.runner = runner
        self.securityPath = securityPath
        self.timeout = timeout
    }

    public func read(service: String) async -> CredentialReadResult {
        let outcome = await runner.run(ProcessRequest(
            executable: securityPath,
            arguments: ["find-generic-password", "-s", service, "-w"],
            environment: nil,
            currentDirectory: nil,
            timeout: timeout
        ))
        if outcome.timedOut { return .failed("timed out") }
        if let error = outcome.launchError {
            return .failed(SecretRedactor().redact(error))
        }
        guard let status = outcome.exitStatus else { return .failed("no exit status") }
        if status == 44 { return .missing }
        if status != 0 { return .failed("security exited with status \(status)") }
        return Self.parse(outcome.stdout)
    }

    private static func parse(_ data: Data) -> CredentialReadResult {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let root = object as? [String: Any]
        else { return .malformed("not a JSON object") }
        guard let oauth = root["claudeAiOauth"] as? [String: Any] else {
            return .malformed("claudeAiOauth missing")
        }
        guard let access = oauth["accessToken"] as? String, !access.isEmpty else {
            return .malformed("accessToken missing")
        }
        let refresh = oauth["refreshToken"] as? String
        var expires: Date?
        if let ms = (oauth["expiresAt"] as? NSNumber)?.doubleValue {
            expires = Date(timeIntervalSince1970: ms / 1000)
        }
        return .found(ClaudeCredentials(accessToken: access, refreshToken: refresh, expiresAt: expires))
    }
}
