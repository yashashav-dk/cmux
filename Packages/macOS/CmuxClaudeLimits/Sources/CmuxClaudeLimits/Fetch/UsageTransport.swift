public import Foundation

/// Performs the usage GET. Production uses `URLSessionUsageTransport`; tests script replies.
public protocol UsageTransport: Sendable {
    func get(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}
