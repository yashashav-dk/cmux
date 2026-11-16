import Testing
@testable import CmuxClaudeLimits

struct RefreshEnvironmentTests {
    private func make(lang: String? = "en_US.UTF-8") -> RefreshEnvironment {
        RefreshEnvironment(home: "/Users/test", user: "test", logname: "test", tmpdir: "/tmp/x", lang: lang)
    }

    @Test func defaultProfileHasOnlyAllowlist() {
        let vars = make().variables(configDir: nil)
        #expect(Set(vars.keys) == ["HOME", "USER", "LOGNAME", "TMPDIR", "LANG", "PATH"])
        #expect(vars["PATH"] == "/Users/test/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin")
    }

    @Test func configDirAddsOnlyThatKey() {
        let dir = "/Users/test/.codex-accounts/claude/org"
        let vars = make().variables(configDir: dir)
        #expect(Set(vars.keys) == ["HOME", "USER", "LOGNAME", "TMPDIR", "LANG", "PATH", "CLAUDE_CONFIG_DIR"])
        #expect(vars["CLAUDE_CONFIG_DIR"] == dir)
    }

    @Test func nilLangOmitted() {
        #expect(make(lang: nil).variables(configDir: nil)["LANG"] == nil)
    }
}
