public enum CredentialReadResult: Sendable, Equatable {
    case found(ClaudeCredentials)
    case missing
    case malformed(String)
    case failed(String)
}
