import Testing
@testable import CmuxClaudeLimits

@Suite struct PanelLayoutMetricsTests {
    @Test func expanded() {
        #expect(PanelLayoutMetrics.reservedHeight(accountCount: 4, visibleRows: 8, enabled: true, expanded: true) == 242)
    }
    @Test func collapsed() {
        #expect(PanelLayoutMetrics.reservedHeight(accountCount: 4, visibleRows: 8, enabled: true, expanded: false) == 34)
    }
    @Test func noAccounts() {
        #expect(PanelLayoutMetrics.reservedHeight(accountCount: 0, visibleRows: 0, enabled: true, expanded: true) == 0)
    }
    @Test func disabled() {
        #expect(PanelLayoutMetrics.reservedHeight(accountCount: 4, visibleRows: 8, enabled: false, expanded: true) == 0)
    }
    @Test func capped() {
        #expect(PanelLayoutMetrics.reservedHeight(accountCount: 12, visibleRows: 24, enabled: true, expanded: true) == 280)
    }
}
