public import Foundation

/// Everything the service touches outside the process: subprocesses, HTTP, paths and time.
public struct ClaudeLimitsDependencies: Sendable {
    public var runner: any ProcessRunning
    public var transport: any UsageTransport
    public var home: String
    public var environment: RefreshEnvironment
    public var refreshWorkingDirectory: String
    public var now: @Sendable () -> Date
    public var random: @Sendable () -> Double

    public init(
        runner: any ProcessRunning,
        transport: any UsageTransport,
        home: String,
        environment: RefreshEnvironment,
        refreshWorkingDirectory: String,
        now: @escaping @Sendable () -> Date = { Date() },
        random: @escaping @Sendable () -> Double = { Double.random(in: 0...1) }
    ) {
        self.runner = runner
        self.transport = transport
        self.home = home
        self.environment = environment
        self.refreshWorkingDirectory = refreshWorkingDirectory
        self.now = now
        self.random = random
    }
}
