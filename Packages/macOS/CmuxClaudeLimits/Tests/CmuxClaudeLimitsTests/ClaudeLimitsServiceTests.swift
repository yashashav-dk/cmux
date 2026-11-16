import Foundation
import Testing
@testable import CmuxClaudeLimits

/// Four accounts: the default profile, an absolute dir, a `~` dir and a trailing-slash dir.
private struct Harness {
    static let home = "/Users/test"
    static let accounts = [
        ClaudeLimitsAccount(label: "One"),
        ClaudeLimitsAccount(label: "Two", configDir: "/Users/test/.claude-two"),
        ClaudeLimitsAccount(label: "Three", configDir: "~/.claude-three"),
        ClaudeLimitsAccount(label: "Four", configDir: "/Users/test/.claude-four/"),
    ]
    static let normalizedDirs: [String?] = [nil, "/Users/test/.claude-two", "/Users/test/.claude-three", "/Users/test/.claude-four"]
    static let ids = accounts.map(\.id)

    static func token(_ index: Int) -> String { "tok-\(index + 1)" }

    static let defaultBinary = "/Users/test/.local/bin/claude"
    static let nextBinary = "/opt/claude-next/claude"

    static func configuration(
        _ accounts: [ClaudeLimitsAccount] = accounts,
        refreshIntervalSeconds: Int = 300,
        claudeBinary: String = "~/.local/bin/claude"
    ) -> ClaudeLimitsConfiguration {
        ClaudeLimitsConfiguration(
            enabled: true,
            refreshIntervalSeconds: refreshIntervalSeconds,
            claudeBinary: claudeBinary,
            mutedColor: "#a89984",
            accounts: accounts
        )
    }

    let clock = TestClock()
    let runner: FakeProcessRunner
    /// Present when refreshes are gated: `claude` launches suspend until released.
    let gate: GatedProcessRunner?
    let transport: FakeUsageTransport
    let service: ClaudeLimitsService

    init(
        security: [Int: [ProcessOutcome]] = [:],
        replies: [String: [FakeUsageTransport.Reply]] = [:],
        extraProcessScript: [String: [ProcessOutcome]] = [:],
        gateRefreshes: Bool = false,
        configuration: ClaudeLimitsConfiguration = Harness.configuration()
    ) {
        let clock = self.clock
        var script = extraProcessScript
        for (index, dir) in Self.normalizedDirs.enumerated() {
            let fallback = CredentialFixtures.credentials(token: Self.token(index), expiresAt: clock.epoch.addingTimeInterval(86_400))
            script[FakeProcessRunner.securityKey(configDir: dir)] = security[index] ?? [fallback]
        }
        runner = FakeProcessRunner(script: script)
        gate = gateRefreshes ? GatedProcessRunner(wrapping: runner) { $0.executable != "/usr/bin/security" } : nil
        transport = FakeUsageTransport(script: replies, fallback: .http(200, body: UsageFixtures.teamActive))
        let dependencies = ClaudeLimitsDependencies(
            runner: gate ?? runner,
            transport: transport,
            home: Self.home,
            environment: RefreshEnvironment(home: Self.home, user: "test", logname: "test", tmpdir: "/tmp", lang: nil),
            refreshWorkingDirectory: "/cwd",
            now: { clock.date },
            random: { 0.5 }
        )
        service = ClaudeLimitsService(configuration: configuration, dependencies: dependencies, clock: clock)
    }

    /// Starts the service and fires the launch timers at +5 s.
    func startAndFireLaunchTimers(expectedTimers: Int = 4) async {
        await service.start()
        await waitUntil("launch timers registered") { clock.sleeperCount == expectedTimers }
        clock.advance(by: .seconds(5))
    }

    func states() async -> [String: AccountCardState] {
        await service.currentStates
    }

    func allOK(_ ids: [String]) async -> Bool {
        let states = await states()
        return ids.allSatisfy { id in
            if case .ok = states[id] { return true }
            return false
        }
    }

    /// Waits until every fetch has finished and its next timer is registered.
    func settle(timers: Int = 4) async {
        await waitUntil("fetches settled") {
            let inFlight = await service.inFlightCount
            return inFlight == 0 && clock.sleeperCount == timers
        }
    }
}

private func record(_ service: ClaudeLimitsService) -> (Recorder<[String: AccountCardState]>, Task<Void, Never>) {
    let recorder = Recorder<[String: AccountCardState]>()
    let stream = service.states
    let task = Task {
        for await states in stream { recorder.append(states) }
    }
    return (recorder, task)
}

@Suite struct ClaudeLimitsServiceTests {
    @Test func firstFetchFiresAtFiveSecondsForAllAccountsConcurrently() async {
        let h = Harness()
        h.transport.holdAll()
        await h.service.start()
        #expect(await h.states() == Dictionary(uniqueKeysWithValues: Harness.ids.map { ($0, AccountCardState.loading) }))
        await waitUntil("launch timers registered") { h.clock.sleeperCount == 4 }
        #expect(h.clock.pendingDeadlines == Array(repeating: .seconds(5), count: 4))

        h.clock.advance(by: .milliseconds(4_999))
        #expect(h.clock.sleeperCount == 4)
        #expect(h.transport.requests.isEmpty)

        h.clock.advance(by: .milliseconds(1))
        await waitUntil("four GETs in flight at once") { h.transport.pendingCount == 4 }
        #expect(Set(h.transport.tokens) == Set((0..<4).map(Harness.token)))
        h.transport.releaseAll()

        await waitUntil("all accounts ok") { await h.allOK(Harness.ids) }
        await h.settle()
        #expect(h.transport.requests.count == 4)
        #expect(h.clock.pendingDeadlines == Array(repeating: .seconds(305), count: 4))
    }

    @Test func missingLoginOnOneAccountDoesNotBlockOthers() async {
        let h = Harness(security: [1: [ProcessOutcome(exitStatus: 44)]])
        await h.startAndFireLaunchTimers()
        let others = [Harness.ids[0], Harness.ids[2], Harness.ids[3]]
        await waitUntil("other accounts ok") { await h.allOK(others) }
        await h.settle()
        #expect(await h.states()[Harness.ids[1]] == .loginNeeded(detail: "/Users/test/.claude-two"))
        #expect(Set(h.transport.tokens) == ["tok-1", "tok-3", "tok-4"])
    }

    @Test func reconfigureDropsRemovedAccountAndLateResults() async {
        let h = Harness()
        let (recorder, consumer) = record(h.service)
        defer { consumer.cancel() }
        h.transport.hold(token: "tok-2")
        await h.startAndFireLaunchTimers()
        let removed = Harness.ids[1]
        let kept = [Harness.ids[3], Harness.ids[0], Harness.ids[2]]
        await waitUntil("account two GET pending") { h.transport.pendingCount == 1 }
        await waitUntil("other accounts ok") { await h.allOK(kept) }

        let mark = await h.service.emissionCount
        let reordered = [Harness.accounts[3], Harness.accounts[0], Harness.accounts[2]]
        await h.service.reconfigure(Harness.configuration(reordered))
        #expect(await h.service.accountIDs == kept)
        #expect(Set(await h.states().keys) == Set(kept))
        #expect(await h.allOK(kept))

        h.transport.release(token: "tok-2")
        await waitUntil("late result dropped") { await h.service.droppedLateResults == 1 }
        #expect(await h.states()[removed] == nil)

        await waitUntil("rebuilt timers registered") { h.clock.sleeperCount == 3 }
        h.clock.advance(by: .seconds(5))
        await waitUntil("kept accounts fetched again") { h.transport.requests.count == 7 }
        await h.settle(timers: 3)
        #expect(Array(h.transport.tokens.suffix(3)).sorted() == ["tok-1", "tok-3", "tok-4"])

        let total = await h.service.emissionCount
        await waitUntil("stream caught up") { recorder.count == total }
        let afterReconfigure = Array(recorder.all.dropFirst(mark))
        #expect(!afterReconfigure.isEmpty)
        #expect(afterReconfigure.allSatisfy { $0[removed] == nil })
        #expect(afterReconfigure.allSatisfy { Set($0.keys) == Set(kept) })
    }

    @Test func wakeFetchesImmediatelyAndReplacesTimers() async {
        let h = Harness()
        await h.startAndFireLaunchTimers()
        await waitUntil("all accounts ok") { await h.allOK(Harness.ids) }
        await h.settle()
        h.clock.advance(by: .seconds(100))

        let started = await h.service.fetchesStarted
        await h.service.refreshNow(.wake)
        #expect(await h.service.fetchesStarted == started + 4)
        await waitUntil("wake GETs") { h.transport.requests.count == 8 }
        await h.settle()
        #expect(h.clock.pendingDeadlines == Array(repeating: .seconds(405), count: 4))
    }

    @Test func manualRefreshIsDebouncedFiveSeconds() async {
        let h = Harness()
        await h.startAndFireLaunchTimers()
        await h.settle()

        await h.service.refreshNow(.manual)
        await waitUntil("manual GETs") { h.transport.requests.count == 8 }
        await h.settle()

        h.clock.advance(by: .seconds(3))
        let started = await h.service.fetchesStarted
        await h.service.refreshNow(.manual)
        #expect(await h.service.fetchesStarted == started)

        h.clock.advance(by: .seconds(3))
        await h.service.refreshNow(.manual)
        #expect(await h.service.fetchesStarted == started + 4)
        await waitUntil("second manual GETs") { h.transport.requests.count == 12 }
    }

    @Test func refreshExpandsBinaryAndPublishesRefreshingLogin() async {
        let h = Harness(
            security: [0: [
                CredentialFixtures.credentials(token: "old", expiresAt: Date(timeIntervalSince1970: 1_800_086_400)),
                CredentialFixtures.credentials(token: "new", expiresAt: Date(timeIntervalSince1970: 1_800_086_400)),
            ]],
            replies: ["old": [.http(401, body: UsageFixtures.expiredToken)]],
            extraProcessScript: ["/Users/test/.local/bin/claude": [CredentialFixtures.clean]],
            configuration: Harness.configuration([Harness.accounts[0]])
        )
        let (recorder, consumer) = record(h.service)
        defer { consumer.cancel() }
        await h.startAndFireLaunchTimers(expectedTimers: 1)
        await waitUntil("account ok") { await h.allOK([Harness.ids[0]]) }
        await h.settle(timers: 1)

        let refreshes = h.runner.requests(forKey: "/Users/test/.local/bin/claude")
        #expect(refreshes.count == 1)
        #expect(refreshes.first?.environment?["CLAUDE_CONFIG_DIR"] == nil)
        #expect(refreshes.first?.currentDirectory == "/cwd")
        let total = await h.service.emissionCount
        await waitUntil("stream caught up") { recorder.count == total }
        #expect(recorder.all.contains { $0[Harness.ids[0]] == .refreshingLogin })
    }

    @Test func relativeConfigDirIsLoginNeededWithoutPipeline() async {
        let relative = ClaudeLimitsAccount(label: "Rel", configDir: "relative/dir")
        let h = Harness(configuration: Harness.configuration([Harness.accounts[0], relative]))
        await h.service.start()
        #expect(await h.states()[relative.id] == .loginNeeded(detail: "relative/dir"))
        #expect(await h.service.accountIDs == [Harness.ids[0], relative.id])
        await waitUntil("one launch timer") { h.clock.sleeperCount == 1 }
        h.clock.advance(by: .seconds(5))
        await waitUntil("valid account ok") { await h.allOK([Harness.ids[0]]) }
        await h.settle(timers: 1)
        #expect(h.runner.requests.count == 1)
        #expect(await h.states()[relative.id] == .loginNeeded(detail: "relative/dir"))
    }

    @Test func intervalBelowMinimumIsClampedAndReconfigureAppliesNewInterval() async {
        let h = Harness(configuration: Harness.configuration(refreshIntervalSeconds: 30))
        await h.startAndFireLaunchTimers()
        await waitUntil("all accounts ok") { await h.allOK(Harness.ids) }
        await h.settle()
        #expect(h.clock.pendingDeadlines == Array(repeating: .seconds(65), count: 4))

        await h.service.reconfigure(Harness.configuration(refreshIntervalSeconds: 600))
        await waitUntil("rebuilt launch timers") { h.clock.pendingDeadlines == Array(repeating: .seconds(10), count: 4) }
        h.clock.advance(by: .seconds(5))
        await waitUntil("refetched") { h.transport.requests.count == 8 }
        await h.settle()
        #expect(h.clock.pendingDeadlines == Array(repeating: .seconds(610), count: 4))
    }

    @Test func trippedGuardSurvivesBinaryChange() async {
        let h = Harness(
            replies: ["tok-1": [.http(401, body: UsageFixtures.expiredToken)]],
            extraProcessScript: [Harness.defaultBinary: [CredentialFixtures.tripped], Harness.nextBinary: [CredentialFixtures.clean]],
            configuration: Harness.configuration([Harness.accounts[0]])
        )
        let id = Harness.ids[0]
        await h.startAndFireLaunchTimers(expectedTimers: 1)
        await waitUntil("guard tripped") { await h.states()[id] == .loginNeeded(detail: "~/.claude") }
        await h.settle(timers: 1)
        #expect(h.runner.requests(forKey: Harness.defaultBinary).count == 1)

        await h.service.reconfigure(Harness.configuration([Harness.accounts[0]], claudeBinary: Harness.nextBinary))
        await waitUntil("rebuilt launch timer") { h.clock.pendingDeadlines == [.seconds(10)] }
        h.clock.advance(by: .seconds(5))
        await waitUntil("second GET") { h.transport.requests.count == 2 }
        await h.settle(timers: 1)
        #expect(await h.states()[id] == .loginNeeded(detail: "~/.claude"))
        #expect(h.runner.requests(forKey: Harness.defaultBinary).count == 1)
        #expect(h.runner.requests(forKey: Harness.nextBinary).isEmpty)
        #expect(h.transport.requests.count == 2)
    }

    @Test func refreshInFlightAcrossBinaryChangeLaunchesOneProcess() async {
        let expiry = Date(timeIntervalSince1970: 1_800_086_400)
        let h = Harness(
            security: [0: [
                CredentialFixtures.credentials(token: "old", expiresAt: expiry),
                CredentialFixtures.credentials(token: "old", expiresAt: expiry),
                CredentialFixtures.credentials(token: "fresh", expiresAt: expiry),
            ]],
            replies: ["old": [.http(401, body: UsageFixtures.expiredToken)]],
            extraProcessScript: [Harness.defaultBinary: [CredentialFixtures.clean], Harness.nextBinary: [CredentialFixtures.clean]],
            gateRefreshes: true,
            configuration: Harness.configuration([Harness.accounts[0]])
        )
        let id = Harness.ids[0]
        await h.startAndFireLaunchTimers(expectedTimers: 1)
        await waitUntil("refresh launched") { h.gate?.pendingCount == 1 }
        #expect(await h.states()[id] == .refreshingLogin)

        await h.service.reconfigure(Harness.configuration([Harness.accounts[0]], claudeBinary: Harness.nextBinary))
        #expect(await h.states()[id] == .loading)
        await waitUntil("rebuilt launch timer") { h.clock.pendingDeadlines == [.seconds(10)] }
        h.clock.advance(by: .seconds(5))
        await waitUntil("second caller joined the in-flight refresh") {
            await h.service.tokenRefresher.joinedCallCount == 1
        }
        h.gate?.release()

        await waitUntil("account ok") { await h.allOK([id]) }
        await h.settle(timers: 1)
        await waitUntil("cancelled fetch dropped") { await h.service.droppedLateResults == 1 }
        let launches = h.runner.requests.filter { $0.executable != "/usr/bin/security" }
        #expect(launches.map(\.executable) == [Harness.defaultBinary])
    }

    @Test func nextLaunchAfterBinaryChangeUsesNewPathAndKeepsRateLimit() async {
        let expiry = Date(timeIntervalSince1970: 1_800_086_400)
        let ok = FakeUsageTransport.Reply.http(200, body: UsageFixtures.teamActive)
        let expired = FakeUsageTransport.Reply.http(401, body: UsageFixtures.expiredToken)
        let h = Harness(
            security: [0: [
                CredentialFixtures.credentials(token: "old", expiresAt: expiry),
                CredentialFixtures.credentials(token: "fresh", expiresAt: expiry),
            ]],
            replies: ["old": [expired], "fresh": [ok, ok, expired]],
            extraProcessScript: [Harness.defaultBinary: [CredentialFixtures.clean], Harness.nextBinary: [CredentialFixtures.clean]],
            configuration: Harness.configuration([Harness.accounts[0]])
        )
        let id = Harness.ids[0]
        // t=5: 401, refresh with the original binary, retry ok.
        await h.startAndFireLaunchTimers(expectedTimers: 1)
        await waitUntil("first fetch ok") { await h.allOK([id]) }
        await h.settle(timers: 1)
        #expect(h.transport.requests.count == 2)

        // t=10: the rebuilt pipeline fetches without refreshing.
        await h.service.reconfigure(Harness.configuration([Harness.accounts[0]], claudeBinary: Harness.nextBinary))
        await waitUntil("rebuilt launch timer") { h.clock.pendingDeadlines == [.seconds(10)] }
        h.clock.advance(by: .seconds(5))
        await waitUntil("refetched") { h.transport.requests.count == 3 }
        await h.settle(timers: 1)

        // t=310: 401, but the 10-minute limit from the t=5 launch still holds.
        h.clock.advance(by: .seconds(300))
        await waitUntil("timer fetch") { h.transport.requests.count == 4 }
        await h.settle(timers: 1)
        #expect(await h.states()[id] == .loginNeeded(detail: "~/.claude"))
        #expect(h.runner.requests(forKey: Harness.nextBinary).isEmpty)
        #expect(h.clock.pendingDeadlines == [.seconds(605)])

        // t=605: refresh is allowed again and launches the new binary.
        h.clock.advance(by: .seconds(295))
        await waitUntil("refresh with new binary") { h.runner.requests(forKey: Harness.nextBinary).count == 1 }
        await h.settle(timers: 1)
        #expect(h.runner.requests(forKey: Harness.defaultBinary).count == 1)
    }

    @Test func stopCancelsTimersAndIgnoresTriggers() async {
        let h = Harness()
        await h.startAndFireLaunchTimers()
        await h.settle()
        await h.service.stop()
        await waitUntil("timers cancelled") { h.clock.sleeperCount == 0 }
        let started = await h.service.fetchesStarted
        await h.service.refreshNow(.wake)
        h.clock.advance(by: .seconds(3_600))
        #expect(await h.service.fetchesStarted == started)
        #expect(h.transport.requests.count == 4)
    }
}
