import Foundation
import Testing
@testable import CmuxClaudeLimits

@Suite struct BackoffPolicyTests {
    private let policy = BackoffPolicy()

    @Test func defaults() {
        #expect(policy == BackoffPolicy(base: 60, cap: 1800))
    }

    @Test func doublesFromOneMinuteAndCapsAtThirtyMinutes() {
        let delays = (1...7).map { policy.delay(consecutiveFailures: $0, retryAfter: nil) }
        #expect(delays == [60, 120, 240, 480, 960, 1800, 1800])
    }

    @Test func largerRetryAfterWins() {
        #expect(policy.delay(consecutiveFailures: 1, retryAfter: 120) == 120)
        #expect(policy.delay(consecutiveFailures: 6, retryAfter: 10) == 1800)
        #expect(policy.delay(consecutiveFailures: 2, retryAfter: 120) == 120)
    }

    @Test func degenerateCountsStayBounded() {
        #expect(policy.delay(consecutiveFailures: 0, retryAfter: nil) == 60)
        #expect(policy.delay(consecutiveFailures: -3, retryAfter: nil) == 60)
        #expect(policy.delay(consecutiveFailures: 10_000, retryAfter: nil) == 1800)
    }
}
