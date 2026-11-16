import Foundation
import Testing
@testable import CmuxClaudeLimits

@Suite struct UsageClientTests {
    @Test func requestShape() async {
        let transport = FakeUsageTransport(reply: .http(200, body: UsageFixtures.teamActive))
        _ = await UsageClient(transport: transport).fetch(accessToken: "tok")
        #expect(transport.requests.count == 1)
        let request = transport.requests.first
        #expect(UsageClient.endpoint.absoluteString == "https://api.anthropic.com/api/oauth/usage")
        #expect(request?.url == UsageClient.endpoint)
        #expect(request?.httpMethod == "GET")
        #expect(request?.value(forHTTPHeaderField: "Authorization") == "Bearer tok")
        #expect(request?.value(forHTTPHeaderField: "anthropic-beta") == "oauth-2025-04-20")
        #expect(request?.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(request?.timeoutInterval == 15)
    }

    @Test func customTimeout() async {
        let transport = FakeUsageTransport(reply: .http(200, body: "{}"))
        _ = await UsageClient(transport: transport, timeout: 3).fetch(accessToken: "tok")
        #expect(transport.requests.first?.timeoutInterval == 3)
    }

    @Test func okReturnsBody() async {
        let transport = FakeUsageTransport(reply: .http(200, body: UsageFixtures.teamActive))
        let result = await UsageClient(transport: transport).fetch(accessToken: "tok")
        #expect(result == .success(Data(UsageFixtures.teamActive.utf8)))
    }

    @Test func expiredTokenIsUnauthorized() async {
        let transport = FakeUsageTransport(reply: .http(401, body: UsageFixtures.expiredToken))
        #expect(await UsageClient(transport: transport).fetch(accessToken: "tok") == .unauthorized)
    }

    @Test func tooManyRequestsHonorsRetryAfter() async {
        let transport = FakeUsageTransport(reply: .http(429, headers: ["Retry-After": "120"]))
        #expect(await UsageClient(transport: transport).fetch(accessToken: "tok") == .rateLimited(retryAfter: 120))
    }

    @Test func tooManyRequestsWithoutUsableRetryAfter() async {
        let missing = FakeUsageTransport(reply: .http(429))
        #expect(await UsageClient(transport: missing).fetch(accessToken: "tok") == .rateLimited(retryAfter: nil))
        let httpDate = FakeUsageTransport(reply: .http(429, headers: ["Retry-After": "Wed, 21 Oct 2026 07:28:00 GMT"]))
        #expect(await UsageClient(transport: httpDate).fetch(accessToken: "tok") == .rateLimited(retryAfter: nil))
        let negative = FakeUsageTransport(reply: .http(429, headers: ["Retry-After": "-5"]))
        #expect(await UsageClient(transport: negative).fetch(accessToken: "tok") == .rateLimited(retryAfter: nil))
    }

    @Test func serviceUnavailableIsServerError() async {
        let transport = FakeUsageTransport(reply: .http(503))
        #expect(await UsageClient(transport: transport).fetch(accessToken: "tok") == .serverError(503))
    }

    @Test func thrownErrorIsTransportWithoutToken() async {
        let transport = FakeUsageTransport(reply: .failure(.notConnectedToInternet))
        let result = await UsageClient(transport: transport).fetch(accessToken: "sk-ant-oat01-secret")
        guard case .transport(let message) = result else {
            Issue.record("expected transport, got \(result)")
            return
        }
        #expect(!message.isEmpty)
        #expect(!message.contains("sk-ant"))
    }
}
