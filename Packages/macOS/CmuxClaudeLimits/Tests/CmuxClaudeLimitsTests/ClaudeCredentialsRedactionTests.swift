import Foundation
import Testing
@testable import CmuxClaudeLimits

@Suite struct ClaudeCredentialsRedactionTests {
    private let creds = ClaudeCredentials(
        accessToken: "sk-ant-oat01-abc",
        refreshToken: "sk-ant-ort01-def",
        expiresAt: Date(timeIntervalSince1970: 1_763_164_200)
    )

    private func expectNoLeak(_ text: String) {
        #expect(!text.contains("oat01"))
        #expect(!text.contains("ort01"))
        #expect(!text.contains("abc"))
        #expect(!text.contains("def"))
    }

    @Test func stringifications() {
        expectNoLeak(String(describing: creds))
        expectNoLeak("\(creds)")
        expectNoLeak(String(reflecting: creds))
        expectNoLeak(String(describing: CredentialReadResult.found(creds)))
        expectNoLeak("\(CredentialReadResult.found(creds))")
        expectNoLeak(String(reflecting: CredentialReadResult.found(creds)))
    }

    @Test func dumpDoesNotLeak() {
        var out = ""
        dump(creds, to: &out)
        expectNoLeak(out)
        var out2 = ""
        dump(CredentialReadResult.found(creds), to: &out2)
        expectNoLeak(out2)
    }
}
