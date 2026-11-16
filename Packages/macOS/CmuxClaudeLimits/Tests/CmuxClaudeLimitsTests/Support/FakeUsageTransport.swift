import Foundation
@testable import CmuxClaudeLimits

/// Scripted HTTP transport keyed by bearer token. Each token's replies are consumed
/// in order; the last one repeats. Held tokens suspend until released and ignore
/// task cancellation, so tests can deliver a response after its caller was cancelled.
final class FakeUsageTransport: UsageTransport, @unchecked Sendable {
    enum Reply: Sendable {
        case http(Int, body: String = "", headers: [String: String] = [:])
        case failure(URLError.Code)
    }

    private struct Waiter {
        let token: String
        let continuation: CheckedContinuation<Void, Never>
    }

    private let lock = NSLock()
    private var script: [String: [Reply]]
    private let fallback: Reply
    private let log: CallLog?
    private var recorded: [URLRequest] = []
    private var heldTokens: Set<String> = []
    private var holdingAll = false
    private var waiters: [Waiter] = []

    init(reply: Reply) {
        self.script = [:]
        self.fallback = reply
        self.log = nil
    }

    init(script: [String: [Reply]], fallback: Reply = .http(500), log: CallLog? = nil) {
        self.script = script
        self.fallback = fallback
        self.log = log
    }

    static func token(of request: URLRequest) -> String {
        let header = request.value(forHTTPHeaderField: "Authorization") ?? ""
        return header.hasPrefix("Bearer ") ? String(header.dropFirst(7)) : header
    }

    var requests: [URLRequest] { lock.withLock { recorded } }
    var tokens: [String] { requests.map(Self.token(of:)) }
    var pendingCount: Int { lock.withLock { waiters.count } }

    func hold(token: String) { lock.withLock { _ = heldTokens.insert(token) } }
    func holdAll() { lock.withLock { holdingAll = true } }

    func release(token: String) {
        let ready = lock.withLock { () -> [Waiter] in
            heldTokens.remove(token)
            let ready = waiters.filter { $0.token == token }
            waiters.removeAll { $0.token == token }
            return ready
        }
        ready.forEach { $0.continuation.resume() }
    }

    func releaseAll() {
        let ready = lock.withLock { () -> [Waiter] in
            holdingAll = false
            heldTokens.removeAll()
            defer { waiters.removeAll() }
            return waiters
        }
        ready.forEach { $0.continuation.resume() }
    }

    func get(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let token = Self.token(of: request)
        let reply = lock.withLock { () -> Reply in
            recorded.append(request)
            guard var queue = script[token], let next = queue.first else { return fallback }
            if queue.count > 1 {
                queue.removeFirst()
                script[token] = queue
            }
            return next
        }
        log?.append("get " + token)
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let resumeNow = lock.withLock { () -> Bool in
                guard holdingAll || heldTokens.contains(token) else { return true }
                waiters.append(Waiter(token: token, continuation: continuation))
                return false
            }
            if resumeNow { continuation.resume() }
        }
        switch reply {
        case .http(let status, let body, let headers):
            let response = HTTPURLResponse(
                url: request.url ?? UsageClient.endpoint,
                statusCode: status,
                httpVersion: "HTTP/1.1",
                headerFields: headers
            )!
            return (Data(body.utf8), response)
        case .failure(let code):
            throw URLError(code)
        }
    }
}
