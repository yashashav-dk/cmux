import Foundation
import Testing
@testable import CmuxClaudeLimits

@Suite struct RefreshSchedulerTests {
    private let scheduler = RefreshScheduler(interval: 300)

    @Test func defaults() {
        #expect(scheduler.jitterFraction == 0.1)
        #expect(scheduler.initialDelay == 5)
        #expect(scheduler.manualDebounce == 5)
    }

    @Test func jitterIsTenPercentEitherWay() {
        #expect(abs(scheduler.nextDelay(random: 0.5) - 300) < 1e-9)
        #expect(abs(scheduler.nextDelay(random: 0) - 270) < 1e-9)
        #expect(abs(scheduler.nextDelay(random: 1) - 330) < 1e-9)
    }

    @Test func manualRefreshIsDebouncedFiveSeconds() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(scheduler.manualAllowed(lastManual: nil, now: now))
        #expect(!scheduler.manualAllowed(lastManual: now.addingTimeInterval(-3), now: now))
        #expect(scheduler.manualAllowed(lastManual: now.addingTimeInterval(-6), now: now))
    }
}
