import Foundation

/// Runs one `AccountPipeline` per configured account off the main actor and publishes
/// every account's card state. Accounts fetch concurrently: the first fetch fires
/// `initialDelay` after `start()`, then each account reschedules itself with jitter,
/// or with the pipeline's backoff delay after a failure.
public actor ClaudeLimitsService {
    /// Full card states keyed by `ClaudeLimitsAccount.id`, re-sent on every change.
    /// Single consumer. Card order is `accountIDs` (configuration order).
    public nonisolated let states: AsyncStream<[String: AccountCardState]>

    private static let maximumDelay: TimeInterval = 86_400

    private let continuation: AsyncStream<[String: AccountCardState]>.Continuation
    private let dependencies: ClaudeLimitsDependencies
    private let clock: any Clock<Duration>

    private var configuration: ClaudeLimitsConfiguration
    private var scheduler: RefreshScheduler
    /// One instance for the service's lifetime: its tripped-guard set, per-account
    /// rate limit and in-flight refresh must survive every reconfigure.
    private let refresher: TokenRefresher
    private var refresherBinary: String
    private var order: [String]
    private var slots: [String: AccountSlot]
    private var cardStates: [String: AccountCardState]
    private var running = false
    private var lastManual: Date?
    private var lastToken = 0

    // Observability for tests.
    private(set) var emissionCount = 0
    private(set) var droppedLateResults = 0
    private(set) var fetchesStarted = 0
    var inFlightCount: Int { slots.values.filter { $0.fetchToken != nil }.count }
    var tokenRefresher: TokenRefresher { refresher }

    public init(
        configuration: ClaudeLimitsConfiguration,
        dependencies: ClaudeLimitsDependencies,
        clock: any Clock<Duration>
    ) {
        (states, continuation) = AsyncStream.makeStream(of: [String: AccountCardState].self)
        self.dependencies = dependencies
        self.clock = clock
        self.configuration = configuration
        self.scheduler = RefreshScheduler(interval: configuration.effectiveRefreshInterval)
        let binary = ClaudeBinaryPath.expand(configuration.claudeBinary, home: dependencies.home)
        let refresher = TokenRefresher(
            runner: dependencies.runner,
            claudeBinary: binary,
            workingDirectory: dependencies.refreshWorkingDirectory,
            environment: dependencies.environment,
            now: dependencies.now
        )
        self.refresherBinary = binary
        self.refresher = refresher
        let built = AccountSlotSet(accounts: configuration.accounts, dependencies: dependencies, refresher: refresher)
        self.order = built.order
        self.slots = built.slots
        self.cardStates = built.initialStates
    }

    deinit {
        for slot in slots.values {
            slot.timer?.cancel()
            slot.fetch?.cancel()
        }
        continuation.finish()
    }

    /// Account ids in configuration order (duplicates removed).
    public var accountIDs: [String] { order }

    /// The most recently published card states.
    public var currentStates: [String: AccountCardState] { cardStates }

    public func start() {
        guard !running else { return }
        running = true
        publish()
        for id in order {
            schedule(id, after: scheduler.initialDelay)
        }
    }

    /// Cancels every timer and in-flight fetch; results that arrive later are dropped.
    public func stop() {
        guard running else { return }
        running = false
        var restored = false
        for id in order {
            if cancelTasks(of: id) { restored = true }
        }
        if restored { publish() }
    }

    /// Fetches every idle account now. Accounts with a fetch in flight are skipped;
    /// a manual trigger within the debounce window is ignored.
    public func refreshNow(_ trigger: RefreshTrigger) async {
        guard running else { return }
        if trigger == .manual {
            let now = dependencies.now()
            guard scheduler.manualAllowed(lastManual: lastManual, now: now) else { return }
            lastManual = now
        }
        for id in order {
            startFetch(id)
        }
    }

    /// Cancels and rebuilds every account's pipeline in the new configuration order.
    /// Removed accounts disappear from `states` for good; kept accounts keep their card.
    /// The token refresher is never replaced: a new `claudeBinary` only changes the
    /// executable for future launches, keeping its guard, rate limit and in-flight refresh.
    public func reconfigure(_ newConfiguration: ClaudeLimitsConfiguration) async {
        guard newConfiguration != configuration else { return }
        for id in order {
            _ = cancelTasks(of: id)
        }
        configuration = newConfiguration
        scheduler = RefreshScheduler(interval: newConfiguration.effectiveRefreshInterval)
        let built = AccountSlotSet(accounts: newConfiguration.accounts, dependencies: dependencies, refresher: refresher)
        var nextStates: [String: AccountCardState] = [:]
        for id in built.order {
            if built.slots[id]?.pipeline != nil, let kept = cardStates[id] {
                nextStates[id] = kept
            } else {
                nextStates[id] = built.initialStates[id]
            }
        }
        order = built.order
        slots = built.slots
        cardStates = nextStates
        publish()
        if running {
            for id in order {
                schedule(id, after: scheduler.initialDelay)
            }
        }
        // Last, so no state changes after this suspension point. `refresherBinary` is
        // updated first, so overlapping reconfigures send their paths in call order.
        let binary = ClaudeBinaryPath.expand(newConfiguration.claudeBinary, home: dependencies.home)
        if binary != refresherBinary {
            refresherBinary = binary
            await refresher.setClaudeBinary(binary)
        }
    }

    // MARK: - Scheduling

    private func schedule(_ id: String, after delay: TimeInterval) {
        guard running, var slot = slots[id], slot.pipeline != nil else { return }
        slot.timer?.cancel()
        let token = nextToken()
        let clock = self.clock
        let duration = Self.duration(seconds: delay)
        slot.timerToken = token
        slot.timer = Task { [weak self] in
            do {
                try await clock.sleep(for: duration)
            } catch {
                return
            }
            await self?.timerFired(id, token: token)
        }
        slots[id] = slot
    }

    private func timerFired(_ id: String, token: Int) {
        guard running, slots[id]?.timerToken == token else { return }
        startFetch(id)
    }

    private func startFetch(_ id: String) {
        guard running, var slot = slots[id], let pipeline = slot.pipeline, slot.fetchToken == nil else { return }
        slot.timer?.cancel()
        slot.timer = nil
        slot.timerToken = nil
        let token = nextToken()
        let previous = cardStates[id] ?? .loading
        slot.fetchToken = token
        slot.stateBeforeFetch = previous
        slot.fetch = Task { [weak self] in
            let step = await pipeline.runOnce(previous: previous) { [weak self] state in
                await self?.fetchProgressed(id, token: token, state: state)
            }
            await self?.fetchFinished(id, token: token, step: step)
        }
        slots[id] = slot
        fetchesStarted += 1
    }

    private func fetchProgressed(_ id: String, token: Int, state: AccountCardState) {
        guard slots[id]?.fetchToken == token else { return }
        cardStates[id] = state
        publish()
    }

    /// Publishes the result and schedules the next fetch, replacing any pending timer.
    private func fetchFinished(_ id: String, token: Int, step: PipelineStep) {
        guard var slot = slots[id], slot.fetchToken == token else {
            droppedLateResults += 1
            return
        }
        slot.fetch = nil
        slot.fetchToken = nil
        slot.stateBeforeFetch = nil
        slots[id] = slot
        cardStates[id] = step.state
        publish()
        schedule(id, after: step.retryDelay ?? scheduler.nextDelay(random: dependencies.random()))
    }

    /// Returns `true` when a cancelled fetch's pre-fetch state was restored.
    private func cancelTasks(of id: String) -> Bool {
        guard var slot = slots[id] else { return false }
        let restore = slot.cancelTasks()
        slots[id] = slot
        guard let restore, cardStates[id] != restore else { return false }
        cardStates[id] = restore
        return true
    }

    private func publish() {
        emissionCount += 1
        continuation.yield(cardStates)
    }

    private func nextToken() -> Int {
        lastToken += 1
        return lastToken
    }

    /// Clamped to `0...maximumDelay` so a huge `Retry-After` cannot overflow `Duration`.
    private static func duration(seconds: TimeInterval) -> Duration {
        let clamped = seconds.isNaN ? 0 : min(max(seconds, 0), maximumDelay)
        return .milliseconds(Int64((clamped * 1000).rounded()))
    }
}
