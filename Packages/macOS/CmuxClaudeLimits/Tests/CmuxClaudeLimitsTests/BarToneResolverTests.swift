import Testing
@testable import CmuxClaudeLimits

@Suite struct BarToneResolverTests {
    private let resolver = BarToneResolver()
    private func tone(_ s: UsageSeverity, _ p: Double) -> BarTone {
        resolver.tone(for: UsageWindow(kind: .session, percent: p, severity: s))
    }

    @Test func normalIgnoresPercent() { #expect(tone(.normal, 99) == .normal) }
    @Test func knownBad() {
        for s in ["warning", "elevated", "approaching_limit"] { #expect(tone(.other(s), 0) == .warning) }
        for s in ["critical", "exceeded", "rejected"] { #expect(tone(.other(s), 0) == .critical) }
    }
    @Test func unknownFallsBackToThresholds() {
        #expect(tone(.other("zzz"), 85) == .warning)
        #expect(tone(.other("zzz"), 96) == .critical)
        #expect(tone(.other("zzz"), 79.9) == .normal)
        #expect(tone(.other("zzz"), 80) == .warning)
        #expect(tone(.other("zzz"), 95) == .critical)
        #expect(tone(.other("zzz"), 250) == .critical)
        #expect(tone(.other("zzz"), -5) == .normal)
    }
}
