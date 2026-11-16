import Foundation
import Testing
@testable import CmuxClaudeLimits

private final class Clock: @unchecked Sendable {
    private let lock = NSLock()
    private var current = Date(timeIntervalSince1970: 1_000_000)
    var now: Date { lock.withLock { current } }
    func advance(_ seconds: TimeInterval) { lock.withLock { current = current.addingTimeInterval(seconds) } }
}

struct TokenRefresherTests {
    private static let clean = Data(#"{"is_error":false,"num_turns":0,"total_cost_usd":0}"#.utf8)

    private func make(_ runner: any ProcessRunning, clock: Clock = Clock()) -> TokenRefresher {
        TokenRefresher(
            runner: runner,
            claudeBinary: "/Users/test/.local/bin/claude",
            workingDirectory: "/cwd",
            environment: RefreshEnvironment(home: "/Users/test", user: "test", logname: "test", tmpdir: "/tmp", lang: nil),
            now: { clock.now }
        )
    }

    @Test func requestShapeAndRefreshed() async {
        let runner = FakeProcessRunner(outcome: ProcessOutcome(exitStatus: 0, stdout: Self.clean))
        let outcome = await make(runner).refresh(accountID: "a", configDir: "/cfg")
        #expect(outcome == .refreshed)
        let request = runner.requests.first
        #expect(runner.requests.count == 1)
        #expect(request?.executable == "/Users/test/.local/bin/claude")
        #expect(request?.arguments == ["-p", "/usage", "--output-format", "json"])
        #expect(request?.currentDirectory == "/cwd")
        #expect(request?.timeout == 60)
        #expect(request?.environment?["CLAUDE_CONFIG_DIR"] == "/cfg")
        #expect(request?.environment?["PATH"]?.hasPrefix("/Users/test/.local/bin:") == true)
    }

    @Test func secondCallWithinIntervalIsRateLimited() async {
        let clock = Clock()
        let runner = FakeProcessRunner(outcome: ProcessOutcome(exitStatus: 0, stdout: Self.clean))
        let refresher = make(runner, clock: clock)
        let first = clock.now
        _ = await refresher.refresh(accountID: "a", configDir: nil)
        clock.advance(100)
        let second = await refresher.refresh(accountID: "a", configDir: nil)
        #expect(second == .rateLimited(nextAllowedAt: first.addingTimeInterval(600)))
        #expect(runner.requests.count == 1)
    }

    @Test func unparseableIsLoginNeededAndRetriesLater() async {
        let clock = Clock()
        let runner = FakeProcessRunner(outcome: ProcessOutcome(exitStatus: 127, stdout: Data("node: command not found".utf8)))
        let refresher = make(runner, clock: clock)
        #expect(await refresher.refresh(accountID: "a", configDir: nil) == .loginNeeded("unparseable refresh output"))
        clock.advance(601)
        #expect(await refresher.refresh(accountID: "a", configDir: nil) == .loginNeeded("unparseable refresh output"))
        #expect(runner.requests.count == 2)
    }

    @Test func trippedDisablesForever() async {
        let clock = Clock()
        let tripped = Data(#"{"is_error":false,"num_turns":2,"total_cost_usd":0}"#.utf8)
        let runner = FakeProcessRunner(outcome: ProcessOutcome(exitStatus: 0, stdout: tripped))
        let refresher = make(runner, clock: clock)
        #expect(await refresher.refresh(accountID: "a", configDir: nil) == .guardTripped("num_turns=2"))
        clock.advance(100_000)
        #expect(await refresher.refresh(accountID: "a", configDir: nil) == .disabled)
        #expect(runner.requests.count == 1)
        // other accounts are unaffected by a trip on "a"
        #expect(await refresher.refresh(accountID: "b", configDir: nil) == .guardTripped("num_turns=2"))
    }

    @Test func timeoutIsLoginNeeded() async {
        let runner = FakeProcessRunner(outcome: ProcessOutcome(timedOut: true))
        #expect(await make(runner).refresh(accountID: "a", configDir: nil) == .loginNeeded("refresh timed out"))
    }

    @Test func concurrentCallsLaunchOneProcess() async {
        let runner = GatedProcessRunner(outcome: ProcessOutcome(exitStatus: 0, stdout: Self.clean))
        let refresher = make(runner)
        async let first = refresher.refresh(accountID: "a", configDir: nil)
        while runner.requests.isEmpty { await Task.yield() }
        async let second = refresher.refresh(accountID: "a", configDir: nil)
        while await refresher.joinedCallCount < 1 { await Task.yield() }
        runner.release()
        #expect(await first == .refreshed)
        #expect(await second == .refreshed)
        #expect(runner.requests.count == 1)
    }
}
