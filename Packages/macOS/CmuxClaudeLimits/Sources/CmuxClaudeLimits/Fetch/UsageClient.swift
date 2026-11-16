public import Foundation

/// One GET of the OAuth usage endpoint. The access token goes only into the
/// `Authorization` header; it never appears in a result.
public struct UsageClient: Sendable {
    public static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    private let transport: any UsageTransport
    private let timeout: TimeInterval

    public init(transport: any UsageTransport, timeout: TimeInterval = 15) {
        self.transport = transport
        self.timeout = timeout
    }

    public func fetch(accessToken: String) async -> UsageFetchResult {
        var request = URLRequest(
            url: Self.endpoint,
            cachePolicy: .reloadIgnoringLocalAndRemoteCacheData,
            timeoutInterval: timeout
        )
        request.httpMethod = "GET"
        request.httpShouldHandleCookies = false
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport.get(request)
        } catch {
            return .transport(Self.describe(error))
        }
        switch response.statusCode {
        case 200..<300:
            return .success(data)
        case 401:
            return .unauthorized
        case 429:
            return .rateLimited(retryAfter: Self.retryAfter(response.value(forHTTPHeaderField: "Retry-After")))
        default:
            return .serverError(response.statusCode)
        }
    }

    /// Delta-seconds only; an HTTP-date or junk value yields `nil` (plain backoff applies).
    private static func retryAfter(_ value: String?) -> TimeInterval? {
        guard let value, let seconds = TimeInterval(value.trimmingCharacters(in: .whitespaces)),
              seconds.isFinite, seconds >= 0 else { return nil }
        return seconds
    }

    private static func describe(_ error: any Error) -> String {
        if error is CancellationError { return "cancelled" }
        let message: String
        if let urlError = error as? URLError {
            message = "network error \(urlError.code.rawValue): \(urlError.localizedDescription)"
        } else {
            message = "network error: \(error.localizedDescription)"
        }
        return SecretRedactor().redact(message)
    }
}
