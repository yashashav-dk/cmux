import Foundation
@testable import CmuxClaudeLimits

/// Records every request and answers from a script keyed by `key(for:)`.
/// Each key's outcomes are consumed in order; the last one repeats.
final class FakeProcessRunner: ProcessRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [ProcessRequest] = []
    private var script: [String: [ProcessOutcome]]
    private let fallback: ProcessOutcome
    private let log: CallLog?

    /// Every request gets `outcome`.
    init(outcome: ProcessOutcome) {
        self.script = [:]
        self.fallback = outcome
        self.log = nil
    }

    /// Unscripted keys get `fallback`.
    init(
        script: [String: [ProcessOutcome]],
        fallback: ProcessOutcome = ProcessOutcome(launchError: "unscripted request"),
        log: CallLog? = nil
    ) {
        self.script = script
        self.fallback = fallback
        self.log = log
    }

    /// `security:<service>` for Keychain reads, otherwise the executable path.
    static func key(for request: ProcessRequest) -> String {
        if let index = request.arguments.firstIndex(of: "-s"), request.arguments.indices.contains(index + 1) {
            return "security:" + request.arguments[index + 1]
        }
        return request.executable
    }

    static func securityKey(configDir: String?) -> String {
        "security:" + ClaudeKeychainService.serviceName(configDir: configDir)
    }

    var requests: [ProcessRequest] {
        lock.withLock { recorded }
    }

    func requests(forKey key: String) -> [ProcessRequest] {
        requests.filter { Self.key(for: $0) == key }
    }

    func run(_ request: ProcessRequest) async -> ProcessOutcome {
        let key = Self.key(for: request)
        let outcome = lock.withLock { () -> ProcessOutcome in
            recorded.append(request)
            guard var queue = script[key], let next = queue.first else { return fallback }
            if queue.count > 1 {
                queue.removeFirst()
                script[key] = queue
            }
            return next
        }
        log?.append("run " + key)
        return outcome
    }
}

enum CredentialFixtures {
    static let clean = ProcessOutcome(
        exitStatus: 0,
        stdout: Data(#"{"is_error":false,"num_turns":0,"total_cost_usd":0}"#.utf8)
    )

    static let tripped = ProcessOutcome(
        exitStatus: 0,
        stdout: Data(#"{"is_error":false,"num_turns":2,"total_cost_usd":0.4}"#.utf8)
    )

    static func credentials(token: String, expiresAt: Date) -> ProcessOutcome {
        let ms = Int64((expiresAt.timeIntervalSince1970 * 1000).rounded())
        let json = #"{"claudeAiOauth":{"accessToken":"\#(token)","refreshToken":"r-\#(token)","expiresAt":\#(ms)}}"#
        return ProcessOutcome(exitStatus: 0, stdout: Data(json.utf8))
    }
}
