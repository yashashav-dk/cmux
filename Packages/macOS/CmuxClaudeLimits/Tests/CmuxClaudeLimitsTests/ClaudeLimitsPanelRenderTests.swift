import AppKit
import Foundation
import SwiftUI
import Testing
@testable import CmuxClaudeLimits

@MainActor
struct ClaudeLimitsPanelRenderTests {
    private struct NoopActions: PanelActions {
        func refreshNow() async {}
        func setCollapsed(_ collapsed: Bool) {}
    }

    private func makeModel(longTitlesOnly: Bool = false) -> ClaudeLimitsPanelModel {
        let now = Date(timeIntervalSince1970: 1_794_000_000)
        let defaults = UserDefaults(suiteName: "render-\(UUID().uuidString)")!
        var accounts = [
            ClaudeLimitsAccount(label: "personal-a", configDir: nil, style: .solo),
            ClaudeLimitsAccount(label: "personal-b", configDir: "/Users/test/.accounts/b", style: .solo),
            ClaudeLimitsAccount(label: "org-a", configDir: "/Users/test/.accounts/c", style: .badge, color: "#89b482"),
            ClaudeLimitsAccount(label: "org-b", configDir: "/Users/test/.accounts/d", style: .badge, color: "#7daea3"),
            ClaudeLimitsAccount(label: "long-titles", configDir: "/Users/test/.accounts/e", style: .solo),
        ]
        let longAccount = accounts.removeLast()
        if longTitlesOnly { accounts = [longAccount] }
        let configuration = ClaudeLimitsConfiguration(
            enabled: true, refreshIntervalSeconds: 300, claudeBinary: "~/.local/bin/claude",
            mutedColor: "#a89984", accounts: accounts
        )
        let model = ClaudeLimitsPanelModel(
            configuration: configuration, defaults: defaults,
            timeZone: TimeZone(identifier: "America/Los_Angeles")!, now: { now }
        )
        func snapshot(_ session: Double, _ weekly: Double, resetIn: TimeInterval, sev: UsageSeverity = .normal) -> UsageSnapshot {
            UsageSnapshot(windows: [
                UsageWindow(kind: .session, percent: session, resetsAt: now.addingTimeInterval(resetIn), severity: sev, isActive: session > 0),
                UsageWindow(kind: .weeklyAll, percent: weekly, resetsAt: now.addingTimeInterval(4 * 86_400)),
            ], fetchedAt: now.addingTimeInterval(-120))
        }
        var longTitles = snapshot(12, 8, resetIn: 3600)
        for label in ["Sonnet", "5 Std.", "5 小時", "5시간", "أسبوع", "Opus long"] {
            longTitles.windows.append(UsageWindow(
                kind: .weeklyScoped, percent: 5, resetsAt: now.addingTimeInterval(4 * 86_400), scopeLabel: label
            ))
        }
        model.apply(states: [
            "default": .ok(snapshot(42, 17, resetIn: 47 * 60)),
            "/Users/test/.accounts/b": .stale(snapshot(86, 30, resetIn: 3 * 3600, sev: .other("warning")), error: "HTTP 429", since: now.addingTimeInterval(-300)),
            "/Users/test/.accounts/c": .loginNeeded(detail: "/Users/test/.accounts/c"),
            "/Users/test/.accounts/d": .ok(snapshot(97, 61, resetIn: 130 * 60, sev: .other("critical"))),
            "/Users/test/.accounts/e": .ok(longTitles),
        ])
        model._setLastSuccessfulRefreshForTesting(now.addingTimeInterval(-120))
        return model
    }

    private func render(_ scheme: ColorScheme, to url: URL, longTitlesOnly: Bool = false) throws {
        let model = makeModel(longTitlesOnly: longTitlesOnly)
        let background = scheme == .dark ? Color(white: 0.13) : Color(white: 0.95)
        let view = ClaudeLimitsPanelView(model: model, actions: NoopActions())
            .frame(width: 240)
            .background(background)
            .environment(\.colorScheme, scheme)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        let image = try #require(renderer.nsImage)
        let tiff = try #require(image.tiffRepresentation)
        let rep = try #require(NSBitmapImageRep(data: tiff))
        let png = try #require(rep.representation(using: .png, properties: [:]))
        try png.write(to: url)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CMUX_LIMITS_RENDER"] == "1"))
    func rendersLightAndDark() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
        for (scheme, name) in [(ColorScheme.light, "light"), (ColorScheme.dark, "dark")] {
            let url = dir.appendingPathComponent("claude-limits-panel-\(name).png")
            try render(scheme, to: url)
            let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
            #expect(size > 0)
            print("RENDERED \(url.path)")
            let titles = dir.appendingPathComponent("claude-limits-panel-titles-\(name).png")
            try render(scheme, to: titles, longTitlesOnly: true)
            #expect(((try? FileManager.default.attributesOfItem(atPath: titles.path)[.size] as? Int) ?? 0) > 0)
            print("RENDERED \(titles.path)")
        }
    }
}
