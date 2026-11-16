public import Foundation
import CMUXDebugLog

/// One account's fetch state machine: read credentials, refresh proactively when the
/// token is about to expire, GET usage, refresh once on 401, back off on failures.
public actor AccountPipeline {
    /// Refresh first when the token expires within this window.
    static let proactiveRefreshWindow: TimeInterval = 60

    private let account: ClaudeLimitsAccount
    private let configDir: String?
    private let service: String
    private let credentials: KeychainCredentialReader
    private let refresher: TokenRefresher
    private let client: UsageClient
    private let decoder: UsagePayloadDecoder
    private let backoff: BackoffPolicy
    private let now: @Sendable () -> Date
    private var consecutiveFailures = 0

    public init(
        account: ClaudeLimitsAccount,
        configDir: String?,
        credentials: KeychainCredentialReader,
        refresher: TokenRefresher,
        client: UsageClient,
        decoder: UsagePayloadDecoder = UsagePayloadDecoder(),
        backoff: BackoffPolicy = BackoffPolicy(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.account = account
        self.configDir = configDir
        self.service = ClaudeKeychainService.serviceName(configDir: configDir)
        self.credentials = credentials
        self.refresher = refresher
        self.client = client
        self.decoder = decoder
        self.backoff = backoff
        self.now = now
    }

    private enum CredentialStep {
        case token(String, expiresAt: Date?)
        case stop(PipelineStep)
    }

    /// `previous` is the card's current state; its snapshot is kept as stale on failure.
    /// `progress` receives `.refreshingLogin` before any refresh runs. A cancelled run
    /// returns `previous` without making further requests.
    public func runOnce(
        previous: AccountCardState,
        progress: @Sendable (AccountCardState) async -> Void = { _ in }
    ) async -> PipelineStep {
        var token: String
        var expiresAt: Date?
        switch await readCredentials(previous: previous) {
        case .stop(let step): return step
        case .token(let value, let expiry): (token, expiresAt) = (value, expiry)
        }

        var refreshAttempted = false
        var refreshAllowedAt: Date?
        if let expiry = expiresAt, expiry <= now().addingTimeInterval(Self.proactiveRefreshWindow) {
            if Task.isCancelled { return PipelineStep(state: previous) }
            refreshAttempted = true
            await progress(.refreshingLogin)
            switch await refresher.refresh(accountID: account.id, configDir: configDir) {
            case .refreshed:
                switch await readCredentials(previous: previous) {
                case .stop(let step): return step
                case .token(let value, let expiry): (token, expiresAt) = (value, expiry)
                }
            case .guardTripped:
                return loginNeeded()
            case .rateLimited(let nextAllowedAt):
                refreshAllowedAt = nextAllowedAt
            case .loginNeeded, .disabled:
                // The current token may still be accepted; the server decides.
                break
            }
        }

        if Task.isCancelled { return PipelineStep(state: previous) }
        var result = await client.fetch(accessToken: token)
        if result == .unauthorized {
            if refreshAttempted { return loginNeeded(retryAt: refreshAllowedAt) }
            if Task.isCancelled { return PipelineStep(state: previous) }
            await progress(.refreshingLogin)
            switch await refresher.refresh(accountID: account.id, configDir: configDir) {
            case .refreshed:
                break
            case .rateLimited(let nextAllowedAt):
                return loginNeeded(retryAt: nextAllowedAt)
            case .loginNeeded, .guardTripped, .disabled:
                return loginNeeded()
            }
            switch await readCredentials(previous: previous) {
            case .stop(let step): return step
            case .token(let value, _): token = value
            }
            if Task.isCancelled { return PipelineStep(state: previous) }
            result = await client.fetch(accessToken: token)
            if result == .unauthorized { return loginNeeded() }
        }
        return step(for: result, previous: previous)
    }

    private func readCredentials(previous: AccountCardState) async -> CredentialStep {
        switch await credentials.read(service: service) {
        case .found(let found):
            return .token(found.accessToken, expiresAt: found.expiresAt)
        case .missing, .malformed:
            return .stop(loginNeeded())
        case .failed(let reason):
            return .stop(failure("keychain read failed: \(reason)", previous: previous, retryAfter: nil))
        }
    }

    private func step(for result: UsageFetchResult, previous: AccountCardState) -> PipelineStep {
        switch result {
        case .success(let data):
            consecutiveFailures = 0
            do {
                return PipelineStep(state: .ok(try decoder.decode(data, fetchedAt: now())))
            } catch UsageDecodeError.notJSON {
                return unavailable("usage response was not JSON")
            } catch {
                return unavailable("usage response had no usage fields")
            }
        case .unauthorized:
            return loginNeeded()
        case .rateLimited(let retryAfter):
            return failure("HTTP 429", previous: previous, retryAfter: retryAfter)
        case .serverError(let status):
            return failure("HTTP \(status)", previous: previous, retryAfter: nil)
        case .transport(let message):
            return failure(message, previous: previous, retryAfter: nil)
        }
    }

    /// Keeps the last good snapshot as stale (preserving when it first went stale)
    /// and backs off exponentially.
    private func failure(_ message: String, previous: AccountCardState, retryAfter: TimeInterval?) -> PipelineStep {
        consecutiveFailures += 1
        let delay = backoff.delay(consecutiveFailures: consecutiveFailures, retryAfter: retryAfter)
        log("fetch failed (\(consecutiveFailures)): \(message); retry in \(Int(delay))s")
        let state: AccountCardState
        switch previous {
        case .ok(let snapshot):
            state = .stale(snapshot, error: message, since: now())
        case .stale(let snapshot, _, let since):
            state = .stale(snapshot, error: message, since: since)
        case .loading, .refreshingLogin, .loginNeeded, .unavailable:
            state = .unavailable(reason: message)
        }
        return PipelineStep(state: state, retryDelay: delay)
    }

    private func unavailable(_ reason: String) -> PipelineStep {
        log(reason)
        return PipelineStep(state: .unavailable(reason: reason))
    }

    /// `retryAt` is when the refresher accepts another refresh; retrying then beats
    /// waiting a full interval.
    private func loginNeeded(retryAt: Date? = nil) -> PipelineStep {
        consecutiveFailures = 0
        log("login needed")
        let retryDelay = retryAt.map { max(1, $0.timeIntervalSince(now())) }
        return PipelineStep(state: .loginNeeded(detail: configDir ?? "~/.claude"), retryDelay: retryDelay)
    }

    private func log(_ message: String) {
        let line = SecretRedactor().redact("claudeLimits.fetch account=\(account.id) \(message)")
        logDebugEvent(line)
    }
}
