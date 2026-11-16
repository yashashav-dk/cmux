public import Foundation
import CMUXDebugLog

/// Refreshes an account's OAuth token by running Claude Code's own CLI
/// (`claude -p "/usage" --output-format json`), which costs zero turns.
public actor TokenRefresher {
    private let runner: any ProcessRunning
    private var claudeBinary: String
    private let workingDirectory: String
    private let environment: RefreshEnvironment
    private let now: @Sendable () -> Date
    private let minimumInterval: TimeInterval
    private let timeout: TimeInterval
    private let resultGuard = RefreshResultGuard()
    private let redactor = SecretRedactor()

    private var inFlight: [String: Task<RefreshOutcome, Never>] = [:]
    private var lastLaunch: [String: Date] = [:]
    private var disabledAccounts: Set<String> = []
    private(set) var joinedCallCount = 0

    public init(
        runner: any ProcessRunning,
        claudeBinary: String,
        workingDirectory: String,
        environment: RefreshEnvironment,
        now: @escaping @Sendable () -> Date = { Date() },
        minimumInterval: TimeInterval = 600,
        timeout: TimeInterval = 60
    ) {
        self.runner = runner
        self.claudeBinary = claudeBinary
        self.workingDirectory = workingDirectory
        self.environment = environment
        self.now = now
        self.minimumInterval = minimumInterval
        self.timeout = timeout
    }

    /// Changes the executable for future launches only. Disabled accounts, the
    /// per-account rate limit and any in-flight refresh are kept, so a config reload
    /// can never re-enable a tripped guard or start a second concurrent refresh.
    public func setClaudeBinary(_ path: String) {
        claudeBinary = path
    }

    public func refresh(accountID: String, configDir: String?) async -> RefreshOutcome {
        if disabledAccounts.contains(accountID) { return .disabled }
        if let task = inFlight[accountID] {
            joinedCallCount += 1
            return await task.value
        }
        let current = now()
        if let last = lastLaunch[accountID], current < last.addingTimeInterval(minimumInterval) {
            return .rateLimited(nextAllowedAt: last.addingTimeInterval(minimumInterval))
        }
        lastLaunch[accountID] = current
        let task = Task { await self.perform(accountID: accountID, configDir: configDir) }
        inFlight[accountID] = task
        let outcome = await task.value
        inFlight[accountID] = nil
        return outcome
    }

    private func perform(accountID: String, configDir: String?) async -> RefreshOutcome {
        let request = ProcessRequest(
            executable: claudeBinary,
            arguments: ["-p", "/usage", "--output-format", "json"],
            environment: environment.variables(configDir: configDir),
            currentDirectory: workingDirectory,
            timeout: timeout
        )
        let result = await runner.run(request)
        if result.timedOut {
            log("refresh timed out", accountID)
            return .loginNeeded("refresh timed out")
        }
        if let error = result.launchError {
            log("refresh launch failed: \(error)", accountID)
            return .loginNeeded("refresh launch failed")
        }
        switch resultGuard.evaluate(stdout: result.stdout) {
        case .clean:
            log("refresh ok", accountID)
            return .refreshed
        case .unparseable:
            log("refresh output unparseable", accountID)
            return .loginNeeded("unparseable refresh output")
        case .tripped(let reason):
            disabledAccounts.insert(accountID)
            log("refresh disabled, guard tripped: \(reason)", accountID)
            return .guardTripped(reason)
        }
    }

    private func log(_ message: String, _ accountID: String) {
        let line = redactor.redact("claudeLimits.refresh account=\(accountID) \(message)")
        logDebugEvent(line)
    }
}
