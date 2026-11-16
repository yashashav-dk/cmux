import Testing
@testable import CmuxClaudeLimits

@Suite struct ClaudeKeychainServiceTests {
    @Test func defaultService() {
        #expect(ClaudeKeychainService.serviceName(configDir: nil) == "Claude Code-credentials")
    }

    @Test func hashedServices() {
        #expect(ClaudeKeychainService.serviceName(configDir: "/Users/test/.codex-accounts/claude/gmail") == "Claude Code-credentials-8dba8d44")
        #expect(ClaudeKeychainService.serviceName(configDir: "/tmp/claude-config") == "Claude Code-credentials-19aa18c8")
    }

    @Test func explicitHomeIsDifferentProfile() throws {
        let path = ClaudeConfigDirPath(home: "/Users/test")
        let normalized = try path.normalized("~/.claude")
        #expect(normalized == "/Users/test/.claude")
        let service = ClaudeKeychainService.serviceName(configDir: normalized)
        #expect(service == "Claude Code-credentials-462977e4")
        #expect(service != ClaudeKeychainService.defaultService)
    }

    @Test func normalization() throws {
        let path = ClaudeConfigDirPath(home: "/Users/test")
        #expect(try path.normalized("~/x/") == "/Users/test/x")
        #expect(try path.normalized(nil) == nil)
        #expect(try path.normalized("") == nil)
        #expect(throws: ClaudeConfigDirError.notAbsolute("relative")) {
            try path.normalized("relative")
        }
    }
}
