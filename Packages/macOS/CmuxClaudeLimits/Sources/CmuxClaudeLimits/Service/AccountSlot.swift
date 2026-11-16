import Foundation

/// Per-account bookkeeping owned by `ClaudeLimitsService`. Each timer and fetch gets a
/// fresh token; a callback whose token no longer matches is a late result and is dropped.
struct AccountSlot: Sendable {
    let account: ClaudeLimitsAccount
    /// `nil` when the configured dir is not usable; the card then stays `.loginNeeded`.
    let pipeline: AccountPipeline?
    var timer: Task<Void, Never>?
    var timerToken: Int?
    var fetch: Task<Void, Never>?
    var fetchToken: Int?
    /// Card state when the in-flight fetch began; restored if that fetch is cancelled,
    /// so a cancelled refresh never leaves the card stuck on `.refreshingLogin`.
    var stateBeforeFetch: AccountCardState?

    /// Cancels the timer and any in-flight fetch. Returns the state to restore, if any.
    mutating func cancelTasks() -> AccountCardState? {
        timer?.cancel()
        fetch?.cancel()
        let restore = fetchToken == nil ? nil : stateBeforeFetch
        timer = nil
        timerToken = nil
        fetch = nil
        fetchToken = nil
        stateBeforeFetch = nil
        return restore
    }
}

struct AccountSlotSet: Sendable {
    /// Account ids in configuration order, duplicates removed (first entry wins).
    var order: [String] = []
    var slots: [String: AccountSlot] = [:]
    var initialStates: [String: AccountCardState] = [:]

    /// Normalizes each config dir; an unusable one gets `.loginNeeded` and no pipeline.
    init(accounts: [ClaudeLimitsAccount], dependencies: ClaudeLimitsDependencies, refresher: TokenRefresher) {
        let paths = ClaudeConfigDirPath(home: dependencies.home)
        let credentials = KeychainCredentialReader(runner: dependencies.runner)
        let client = UsageClient(transport: dependencies.transport)
        for account in accounts where slots[account.id] == nil {
            order.append(account.id)
            let configDir: String?
            do {
                configDir = try paths.normalized(account.configDir)
            } catch {
                slots[account.id] = AccountSlot(account: account, pipeline: nil)
                initialStates[account.id] = .loginNeeded(detail: account.configDir ?? "")
                continue
            }
            let pipeline = AccountPipeline(
                account: account,
                configDir: configDir,
                credentials: credentials,
                refresher: refresher,
                client: client,
                now: dependencies.now
            )
            slots[account.id] = AccountSlot(account: account, pipeline: pipeline)
            initialStates[account.id] = .loading
        }
    }
}

enum ClaudeBinaryPath {
    /// Expands a leading `~` against `home`; anything else is returned unchanged.
    static func expand(_ path: String, home: String) -> String {
        if path == "~" { return home }
        if path.hasPrefix("~/") { return home + String(path.dropFirst(1)) }
        return path
    }
}
