import Foundation
import Testing
@testable import CmuxClaudeLimits

@Suite struct AccountPipelineTests {
    private static let now = Date(timeIntervalSince1970: 1_800_000_000)
    private static let configDir = "/Users/test/.claude-work"
    private static let security = FakeProcessRunner.securityKey(configDir: configDir)
    private static let claude = "/Users/test/.local/bin/claude"
    private static let snapshot = try! UsagePayloadDecoder().decode(Data(UsageFixtures.teamActive.utf8), fetchedAt: now)

    private static func credentials(_ token: String, expiresIn: TimeInterval = 3600) -> ProcessOutcome {
        CredentialFixtures.credentials(token: token, expiresAt: now.addingTimeInterval(expiresIn))
    }

    private func make(
        _ runner: any ProcessRunning,
        _ transport: FakeUsageTransport,
        configDir: String? = AccountPipelineTests.configDir
    ) -> AccountPipeline {
        let now = Self.now
        let refresher = TokenRefresher(
            runner: runner,
            claudeBinary: Self.claude,
            workingDirectory: "/cwd",
            environment: RefreshEnvironment(home: "/Users/test", user: "test", logname: "test", tmpdir: "/tmp", lang: nil),
            now: { now }
        )
        return AccountPipeline(
            account: ClaudeLimitsAccount(label: "Work", configDir: configDir),
            configDir: configDir,
            credentials: KeychainCredentialReader(runner: runner),
            refresher: refresher,
            client: UsageClient(transport: transport),
            now: { now }
        )
    }

    @Test func okPublishesSnapshot() async {
        let runner = FakeProcessRunner(script: [Self.security: [Self.credentials("tok")]])
        let transport = FakeUsageTransport(script: ["tok": [.http(200, body: UsageFixtures.teamActive)]])
        let step = await make(runner, transport).runOnce(previous: .loading)
        #expect(step == PipelineStep(state: .ok(Self.snapshot), retryDelay: nil))
        #expect(transport.tokens == ["tok"])
        #expect(runner.requests(forKey: Self.claude).isEmpty)
    }

    @Test func unauthorizedRefreshesOnceThenRetriesWithNewToken() async {
        let log = CallLog()
        let runner = FakeProcessRunner(
            script: [Self.security: [Self.credentials("old"), Self.credentials("new")], Self.claude: [CredentialFixtures.clean]],
            log: log
        )
        let transport = FakeUsageTransport(
            script: ["old": [.http(401, body: UsageFixtures.expiredToken)], "new": [.http(200, body: UsageFixtures.teamActive)]],
            log: log
        )
        let progress = Recorder<AccountCardState>()
        let step = await make(runner, transport).runOnce(previous: .loading) { progress.append($0) }
        #expect(step == PipelineStep(state: .ok(Self.snapshot), retryDelay: nil))
        #expect(progress.all == [.refreshingLogin])
        #expect(log.entries == ["run \(Self.security)", "get old", "run \(Self.claude)", "run \(Self.security)", "get new"])
        #expect(runner.requests(forKey: Self.claude).first?.environment?["CLAUDE_CONFIG_DIR"] == Self.configDir)
    }

    @Test func secondUnauthorizedIsLoginNeededWithConfigDir() async {
        let runner = FakeProcessRunner(script: [
            Self.security: [Self.credentials("old"), Self.credentials("new")],
            Self.claude: [CredentialFixtures.clean],
        ])
        let transport = FakeUsageTransport(script: [
            "old": [.http(401, body: UsageFixtures.expiredToken)],
            "new": [.http(401, body: UsageFixtures.expiredToken)],
        ])
        let step = await make(runner, transport).runOnce(previous: .ok(Self.snapshot))
        #expect(step == PipelineStep(state: .loginNeeded(detail: Self.configDir), retryDelay: nil))
        #expect(transport.tokens == ["old", "new"])
        #expect(runner.requests(forKey: Self.claude).count == 1)
    }

    @Test func missingKeychainItemIsLoginNeededWithoutHTTP() async {
        let runner = FakeProcessRunner(script: [Self.security: [ProcessOutcome(exitStatus: 44)]])
        let transport = FakeUsageTransport(reply: .http(200, body: UsageFixtures.teamActive))
        let step = await make(runner, transport).runOnce(previous: .loading)
        #expect(step == PipelineStep(state: .loginNeeded(detail: Self.configDir), retryDelay: nil))
        #expect(transport.requests.isEmpty)
        #expect(runner.requests(forKey: Self.claude).isEmpty)
    }

    @Test func defaultProfileDetailIsHomeClaude() async {
        let runner = FakeProcessRunner(script: [FakeProcessRunner.securityKey(configDir: nil): [ProcessOutcome(exitStatus: 44)]])
        let transport = FakeUsageTransport(reply: .http(200, body: UsageFixtures.teamActive))
        let step = await make(runner, transport, configDir: nil).runOnce(previous: .loading)
        #expect(step.state == .loginNeeded(detail: "~/.claude"))
        #expect(transport.requests.isEmpty)
    }

    @Test func itemWithoutOAuthIsLoginNeeded() async {
        let apiKeyLogin = ProcessOutcome(exitStatus: 0, stdout: Data(#"{"primaryApiKey":"x"}"#.utf8))
        let runner = FakeProcessRunner(script: [Self.security: [apiKeyLogin]])
        let transport = FakeUsageTransport(reply: .http(200, body: UsageFixtures.teamActive))
        let step = await make(runner, transport).runOnce(previous: .loading)
        #expect(step.state == .loginNeeded(detail: Self.configDir))
        #expect(transport.requests.isEmpty)
    }

    @Test func expiringTokenRefreshesBeforeFirstGet() async {
        let log = CallLog()
        let runner = FakeProcessRunner(
            script: [
                Self.security: [Self.credentials("old", expiresIn: 30), Self.credentials("new")],
                Self.claude: [CredentialFixtures.clean],
            ],
            log: log
        )
        let transport = FakeUsageTransport(script: ["new": [.http(200, body: UsageFixtures.teamActive)]], log: log)
        let progress = Recorder<AccountCardState>()
        let step = await make(runner, transport).runOnce(previous: .loading) { progress.append($0) }
        #expect(step.state == .ok(Self.snapshot))
        #expect(progress.all == [.refreshingLogin])
        #expect(log.entries == ["run \(Self.security)", "run \(Self.claude)", "run \(Self.security)", "get new"])
    }

    @Test func tokenValidForTwoMinutesIsNotRefreshed() async {
        let log = CallLog()
        let runner = FakeProcessRunner(script: [Self.security: [Self.credentials("tok", expiresIn: 120)]], log: log)
        let transport = FakeUsageTransport(script: ["tok": [.http(200, body: UsageFixtures.teamActive)]], log: log)
        let progress = Recorder<AccountCardState>()
        let step = await make(runner, transport).runOnce(previous: .loading) { progress.append($0) }
        #expect(step.state == .ok(Self.snapshot))
        #expect(progress.all.isEmpty)
        #expect(log.entries == ["run \(Self.security)", "get tok"])
    }

    @Test func rateLimitKeepsSnapshotAsStaleAndHonorsRetryAfter() async {
        let runner = FakeProcessRunner(script: [Self.security: [Self.credentials("tok")]])
        let transport = FakeUsageTransport(script: ["tok": [.http(429, headers: ["Retry-After": "120"])]])
        let step = await make(runner, transport).runOnce(previous: .ok(Self.snapshot))
        #expect(step == PipelineStep(state: .stale(Self.snapshot, error: "HTTP 429", since: Self.now), retryDelay: 120))
    }

    @Test func consecutiveServerErrorsBackOff() async {
        let runner = FakeProcessRunner(script: [Self.security: [Self.credentials("tok")]])
        let transport = FakeUsageTransport(script: ["tok": [.http(503)]])
        let pipeline = make(runner, transport)
        let first = await pipeline.runOnce(previous: .loading)
        #expect(first == PipelineStep(state: .unavailable(reason: "HTTP 503"), retryDelay: 60))
        let second = await pipeline.runOnce(previous: first.state)
        #expect(second.retryDelay == 120)
    }

    @Test func staleKeepsOriginalSince() async {
        let runner = FakeProcessRunner(script: [Self.security: [Self.credentials("tok")]])
        let transport = FakeUsageTransport(script: ["tok": [.http(502)]])
        let since = Self.now.addingTimeInterval(-600)
        let step = await make(runner, transport).runOnce(previous: .stale(Self.snapshot, error: "HTTP 503", since: since))
        #expect(step.state == .stale(Self.snapshot, error: "HTTP 502", since: since))
    }

    @Test func successResetsBackoff() async {
        let runner = FakeProcessRunner(script: [Self.security: [Self.credentials("tok")]])
        let transport = FakeUsageTransport(script: ["tok": [
            .http(503), .http(503), .http(200, body: UsageFixtures.teamActive), .http(503),
        ]])
        let pipeline = make(runner, transport)
        var delays: [TimeInterval?] = []
        var previous = AccountCardState.loading
        for _ in 0..<4 {
            let step = await pipeline.runOnce(previous: previous)
            delays.append(step.retryDelay)
            previous = step.state
        }
        #expect(delays == [60, 120, nil, 60])
        #expect(previous == .stale(Self.snapshot, error: "HTTP 503", since: Self.now))
    }

    @Test func networkErrorIsStaleWithoutToken() async {
        let runner = FakeProcessRunner(script: [Self.security: [Self.credentials("sk-ant-oat01-secret")]])
        let transport = FakeUsageTransport(reply: .failure(.notConnectedToInternet))
        let step = await make(runner, transport).runOnce(previous: .ok(Self.snapshot))
        guard case .stale(let snapshot, let error, let since) = step.state else {
            Issue.record("expected stale, got \(step.state)")
            return
        }
        #expect(snapshot == Self.snapshot)
        #expect(since == Self.now)
        #expect(!error.contains("sk-ant"))
        #expect(step.retryDelay == 60)
    }

    @Test func payloadWithoutUsageFieldsIsUnavailable() async {
        let runner = FakeProcessRunner(script: [Self.security: [Self.credentials("tok")]])
        let transport = FakeUsageTransport(script: ["tok": [.http(200, body: UsageFixtures.emptyLimits)]])
        let step = await make(runner, transport).runOnce(previous: .ok(Self.snapshot))
        guard case .unavailable(let reason) = step.state else {
            Issue.record("expected unavailable, got \(step.state)")
            return
        }
        #expect(!reason.isEmpty)
        #expect(step.retryDelay == nil)
    }

    @Test func trippedGuardIsLoginNeeded() async {
        let runner = FakeProcessRunner(script: [
            Self.security: [Self.credentials("old")],
            Self.claude: [CredentialFixtures.tripped],
        ])
        let transport = FakeUsageTransport(script: ["old": [.http(401, body: UsageFixtures.expiredToken)]])
        let step = await make(runner, transport).runOnce(previous: .ok(Self.snapshot))
        #expect(step == PipelineStep(state: .loginNeeded(detail: Self.configDir), retryDelay: nil))
        #expect(transport.tokens == ["old"])
    }

    @Test func throttledRefreshRetriesWhenRefreshIsAllowedAgain() async {
        let runner = FakeProcessRunner(script: [
            Self.security: [Self.credentials("old")],
            Self.claude: [CredentialFixtures.clean],
        ])
        let transport = FakeUsageTransport(script: ["old": [.http(401, body: UsageFixtures.expiredToken)]])
        let pipeline = make(runner, transport)
        let first = await pipeline.runOnce(previous: .loading)
        #expect(first == PipelineStep(state: .loginNeeded(detail: Self.configDir), retryDelay: nil))
        let second = await pipeline.runOnce(previous: first.state)
        #expect(second == PipelineStep(state: .loginNeeded(detail: Self.configDir), retryDelay: 600))
        #expect(runner.requests(forKey: Self.claude).count == 1)
    }

    @Test func cancelledRunMakesNoRequest() async {
        let runner = GatedProcessRunner(outcome: Self.credentials("tok"))
        let transport = FakeUsageTransport(reply: .http(200, body: UsageFixtures.teamActive))
        let pipeline = make(runner, transport)
        let task = Task { await pipeline.runOnce(previous: .ok(Self.snapshot)) }
        await waitUntil("keychain read started") { !runner.requests.isEmpty }
        task.cancel()
        runner.release()
        #expect(await task.value == PipelineStep(state: .ok(Self.snapshot), retryDelay: nil))
        #expect(transport.requests.isEmpty)
    }
}
