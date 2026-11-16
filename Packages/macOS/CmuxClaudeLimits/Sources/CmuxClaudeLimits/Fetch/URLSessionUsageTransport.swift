public import Foundation

public struct URLSessionUsageTransport: UsageTransport {
    let session: URLSession

    /// The default is a private ephemeral session (see `makeEphemeralSession()`), so the
    /// bearer-token request and its response are never written to disk.
    public init(session: URLSession = URLSessionUsageTransport.makeEphemeralSession()) {
        self.session = session
    }

    /// No URL cache, cookie store or credential store: request cache policy controls
    /// reads only, so a shared or default session could still persist the request.
    public static func makeEphemeralSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        return URLSession(configuration: configuration)
    }

    public func get(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        return (data, http)
    }
}
