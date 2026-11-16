public import CoreGraphics
public import Foundation
public import Observation

@MainActor
@Observable
public final class ClaudeLimitsPanelModel {
    public static let collapsedDefaultsKey = "claudeLimits.panelCollapsed"

    public private(set) var cards: [AccountCard] = []
    public var lastSuccessfulRefresh: Date?
    public private(set) var configuration: ClaudeLimitsConfiguration

    public var isCollapsed: Bool {
        didSet {
            guard isCollapsed != oldValue else { return }
            defaults.set(isCollapsed, forKey: Self.collapsedDefaultsKey)
        }
    }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let timeZone: TimeZone
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private var accounts: [ClaudeLimitsAccount] = []
    @ObservationIgnored private var states: [String: AccountCardState] = [:]
    @ObservationIgnored private var seeded: [String: CachedSnapshot] = [:]

    public init(
        configuration: ClaudeLimitsConfiguration,
        defaults: UserDefaults,
        timeZone: TimeZone = .current,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.configuration = configuration
        self.defaults = defaults
        self.timeZone = timeZone
        self.now = now
        self.isCollapsed = defaults.bool(forKey: Self.collapsedDefaultsKey)
        self.accounts = Self.dedupe(configuration.accounts)
        rebuild()
    }

    public var isVisible: Bool { configuration.enabled && !cards.isEmpty }

    public var reservedHeight: CGFloat {
        PanelLayoutMetrics.reservedHeight(
            accountCount: cards.count,
            visibleRows: cards.reduce(0) { $0 + $1.rows.count },
            enabled: configuration.enabled,
            expanded: !isCollapsed
        )
    }

    /// True when the cards need an internal scroll view (height hit the cap).
    public var needsScroll: Bool { reservedHeight >= PanelLayoutMetrics.maxHeight }

    /// Minutes (or hours) since the last successful refresh, e.g. "2m".
    public var refreshAgeText: String? {
        guard let last = lastSuccessfulRefresh else { return nil }
        return Self.shortDuration(max(0, now().timeIntervalSince(last)))
    }

    public func apply(states: [String: AccountCardState]) {
        self.states = states
        let newest = states.values.compactMap { state -> Date? in
            if case .ok(let snapshot) = state { return snapshot.fetchedAt }
            return nil
        }.max()
        if let newest, newest > (lastSuccessfulRefresh ?? .distantPast) {
            lastSuccessfulRefresh = newest
        }
        rebuild()
    }

    public func apply(configuration: ClaudeLimitsConfiguration) {
        self.configuration = configuration
        accounts = Self.dedupe(configuration.accounts)
        rebuild()
    }

    /// Renders cached snapshots as `.stale` until the first fetch result arrives.
    public func seed(cache: [String: CachedSnapshot]) {
        seeded = cache
        rebuild()
    }

    /// Re-renders time-dependent text (reset countdowns, ages) with the current clock.
    public func refreshPresentation() {
        rebuild()
    }

    private func rebuild() {
        let current = now()
        let formatter = ResetTextFormatter(timeZone: timeZone, strings: PanelStrings.resetTextStrings)
        cards = accounts.map { card(for: $0, now: current, formatter: formatter) }
    }

    private func card(for account: ClaudeLimitsAccount, now: Date, formatter: ResetTextFormatter) -> AccountCard {
        var state = states[account.id] ?? .loading
        var cachedNotice = false
        if case .loading = state, let cached = seeded[account.id] {
            state = .stale(cached.snapshot, error: "", since: cached.storedAt)
            cachedNotice = true
        }
        var rows: [RowPresentation] = []
        var statusText: String?
        var statusTooltip: String?
        switch state {
        case .loading:
            statusText = PanelStrings.loading
        case .ok(let snapshot):
            rows = Self.rows(snapshot, cardID: account.id, now: now, formatter: formatter)
        case .stale(let snapshot, let error, let since):
            rows = Self.rows(snapshot, cardID: account.id, now: now, formatter: formatter)
            statusText = PanelStrings.stale
            if cachedNotice {
                statusTooltip = PanelStrings.tooltipCached
            } else {
                let age = Self.shortDuration(max(0, now.timeIntervalSince(since)))
                let ago = String(format: PanelStrings.safeFormat(PanelStrings.agoFormat, fallback: "%@ ago"), age)
                statusTooltip = String(
                    format: PanelStrings.safeFormat(PanelStrings.tooltipStale, fallback: "%@ (%@)"),
                    error,
                    ago
                )
            }
        case .refreshingLogin:
            statusText = PanelStrings.refreshingLogin
        case .loginNeeded(let detail):
            statusText = PanelStrings.loginNeeded
            statusTooltip = String(
                format: PanelStrings.safeFormat(PanelStrings.tooltipConfigDir, fallback: "Config dir: %@"),
                detail
            )
        case .unavailable(let reason):
            statusText = PanelStrings.unavailable
            statusTooltip = reason
        }
        return AccountCard(
            id: account.id,
            label: account.label,
            style: account.style,
            color: account.color,
            state: state,
            rows: rows,
            statusText: statusText,
            statusTooltip: statusTooltip
        )
    }

    private static func rows(
        _ snapshot: UsageSnapshot,
        cardID: String,
        now: Date,
        formatter: ResetTextFormatter
    ) -> [RowPresentation] {
        let resolver = BarToneResolver()
        func make(id: String, title: String, window: UsageWindow?) -> RowPresentation {
            guard let window = window?.normalized(now: now) else {
                let empty = UsageWindow(kind: .session, percent: 0)
                return RowPresentation(
                    id: id,
                    title: title,
                    percent: 0,
                    resetText: formatter.text(for: nil, now: now),
                    tooltip: stateTooltip(
                        formatter.text(for: nil, now: now), window: empty, fetched: snapshot.fetchedAt, now: now
                    ),
                    tone: .normal
                )
            }
            let resetText = formatter.text(for: window, now: now)
            let hasFutureReset = window.resetsAt.map { $0 >= now } ?? false
            return RowPresentation(
                id: id,
                title: title,
                percent: clamped(window.percent),
                resetText: resetText,
                tooltip: hasFutureReset
                    ? formatter.tooltip(for: window, lastFetched: snapshot.fetchedAt, now: now)
                    : stateTooltip(resetText, window: window, fetched: snapshot.fetchedAt, now: now),
                tone: resolver.tone(for: window)
            )
        }
        var rows = [
            make(id: "session", title: PanelStrings.session, window: snapshot.session),
            make(id: "weekly", title: PanelStrings.weekly, window: snapshot.weekly),
        ]
        for (index, scoped) in snapshot.scoped.enumerated() {
            let window = scoped.normalized(now: now)
            guard clamped(window.percent) > 0 || window.isActive else { continue }
            rows.append(make(id: "scoped\(index)", title: scoped.scopeLabel ?? PanelStrings.weekly, window: scoped))
        }
        return rows
    }

    /// Tooltip for windows without a future reset ("idle" / "reset"), which must not read "Resets reset".
    private static func stateTooltip(_ state: String, window: UsageWindow, fetched: Date, now: Date) -> String {
        let age = max(0, now.timeIntervalSince(fetched))
        let fetchedText = age < 60
            ? PanelStrings.justNow
            : String(
                format: PanelStrings.safeFormat(PanelStrings.agoFormat, fallback: "%@ ago"),
                shortDuration(age)
            )
        return String(
            format: PanelStrings.safeFormat(PanelStrings.tooltipWindowState, fallback: "Window %@ · %@ used · fetched %@"),
            state,
            "\(Int(clamped(window.percent).rounded()))%",
            fetchedText
        )
    }

    private static func clamped(_ value: Double) -> Double {
        value.isFinite ? min(100, max(0, value)) : 0
    }

    private static func dedupe(_ accounts: [ClaudeLimitsAccount]) -> [ClaudeLimitsAccount] {
        var seen = Set<String>()
        return accounts.filter { seen.insert($0.id).inserted }
    }

    private static func shortDuration(_ interval: TimeInterval) -> String {
        let minutes = Int(interval / 60)
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h" }
        return "\(hours / 24)d"
    }
}
