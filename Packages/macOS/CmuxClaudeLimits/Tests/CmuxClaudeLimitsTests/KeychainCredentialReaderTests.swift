import Foundation
import Testing
@testable import CmuxClaudeLimits

@Suite struct KeychainCredentialReaderTests {
    private func outcome(
        status: Int32? = 0,
        stdout: String = "",
        timedOut: Bool = false,
        launchError: String? = nil
    ) -> ProcessOutcome {
        ProcessOutcome(
            exitStatus: status,
            stdout: Data(stdout.utf8),
            stderr: Data(),
            timedOut: timedOut,
            launchError: launchError
        )
    }

    private let good = #"{"claudeAiOauth":{"accessToken":"sk-ant-oat01-abc","refreshToken":"sk-ant-ort01-def","expiresAt":1763164200000}}"#

    @Test func foundAndRequestShape() async {
        let runner = FakeProcessRunner(outcome: outcome(stdout: good + "\n"))
        let reader = KeychainCredentialReader(runner: runner)
        let result = await reader.read(service: "svc")
        #expect(runner.requests == [ProcessRequest(
            executable: "/usr/bin/security",
            arguments: ["find-generic-password", "-s", "svc", "-w"],
            environment: nil,
            currentDirectory: nil,
            timeout: 5
        )])
        guard case .found(let creds) = result else {
            Issue.record("expected found")
            return
        }
        #expect(creds.accessToken == "sk-ant-oat01-abc")
        #expect(creds.refreshToken == "sk-ant-ort01-def")
        #expect(creds.expiresAt == Date(timeIntervalSince1970: 1_763_164_200))
        #expect(!creds.debugDescription.contains("oat01"))
    }

    @Test func exit44IsMissing() async {
        let reader = KeychainCredentialReader(runner: FakeProcessRunner(outcome: outcome(status: 44)))
        #expect(await reader.read(service: "svc") == .missing)
    }

    @Test func missingOauthKeyIsMalformed() async {
        let reader = KeychainCredentialReader(runner: FakeProcessRunner(outcome: outcome(stdout: #"{"foo":1}"#)))
        #expect(await reader.read(service: "svc") == .malformed("claudeAiOauth missing"))
    }

    @Test func timeoutFails() async {
        let reader = KeychainCredentialReader(runner: FakeProcessRunner(outcome: outcome(status: nil, timedOut: true)))
        #expect(await reader.read(service: "svc") == .failed("timed out"))
    }

    @Test func launchErrorFails() async {
        let reader = KeychainCredentialReader(runner: FakeProcessRunner(outcome: outcome(status: nil, launchError: "nope")))
        guard case .failed = await reader.read(service: "svc") else {
            Issue.record("expected failed")
            return
        }
    }
}
