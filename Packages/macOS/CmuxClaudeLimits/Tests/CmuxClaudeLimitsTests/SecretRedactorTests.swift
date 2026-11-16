import Testing
@testable import CmuxClaudeLimits

@Suite struct SecretRedactorTests {
    private let redactor = SecretRedactor()

    @Test func redactsBearer() {
        let out = redactor.redact("Authorization: Bearer sk-ant-oat01-abc")
        #expect(out.contains("<redacted>"))
        #expect(!out.contains("oat01"))
    }

    @Test func redactsJSONValues() {
        let out = redactor.redact("{\"accessToken\":\"x\"}")
        #expect(out.contains("<redacted>"))
        #expect(!out.contains("\"x\""))
    }

    @Test func redactsBareTokens() {
        let out = redactor.redact("token sk-ant-ort01-def_9 end")
        #expect(!out.contains("ort01"))
        #expect(out.hasSuffix("end"))
    }

    @Test func plainTextUnchanged() {
        #expect(redactor.redact("login needed for org") == "login needed for org")
    }
}
