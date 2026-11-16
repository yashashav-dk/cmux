import Foundation

/// Every user-facing string of the panel. The package catalog is the single source.
enum PanelStrings {
    static var header: String { String(localized: "limits.header", defaultValue: "LIMITS", bundle: .module) }
    static var idle: String { String(localized: "limits.idle", defaultValue: "idle", bundle: .module) }
    static var reset: String { String(localized: "limits.reset", defaultValue: "reset", bundle: .module) }
    static var inShort: String { String(localized: "limits.inShort", defaultValue: "in %@", bundle: .module) }
    static var loading: String { String(localized: "limits.loading", defaultValue: "loading", bundle: .module) }
    static var stale: String { String(localized: "limits.stale", defaultValue: "stale", bundle: .module) }
    static var refreshingLogin: String {
        String(localized: "limits.refreshingLogin", defaultValue: "refreshing login", bundle: .module)
    }
    static var loginNeeded: String {
        String(localized: "limits.loginNeeded", defaultValue: "login needed", bundle: .module)
    }
    static var unavailable: String {
        String(localized: "limits.unavailable", defaultValue: "unavailable", bundle: .module)
    }
    static var refresh: String { String(localized: "limits.refresh", defaultValue: "Refresh", bundle: .module) }
    static var collapse: String { String(localized: "limits.collapse", defaultValue: "Collapse", bundle: .module) }
    static var expand: String { String(localized: "limits.expand", defaultValue: "Expand", bundle: .module) }
    static var tooltipResetAt: String {
        String(
            localized: "limits.tooltipResetAt",
            defaultValue: "Resets %@ · %@ used · fetched %@",
            bundle: .module
        )
    }
    static var tooltipConfigDir: String {
        String(localized: "limits.tooltipConfigDir", defaultValue: "Config dir: %@", bundle: .module)
    }
    static var tooltipStale: String {
        String(localized: "limits.tooltipStale", defaultValue: "Last refresh failed: %@ (%@)", bundle: .module)
    }
    static var tooltipCached: String {
        String(
            localized: "limits.tooltipCached",
            defaultValue: "Showing cached values until the first refresh",
            bundle: .module
        )
    }
    static var tooltipWindowState: String {
        String(
            localized: "limits.tooltipWindowState",
            defaultValue: "Window %@ · %@ used · fetched %@",
            bundle: .module
        )
    }
    static var justNow: String { String(localized: "limits.justNow", defaultValue: "just now", bundle: .module) }
    static var agoFormat: String { String(localized: "limits.agoFormat", defaultValue: "%@ ago", bundle: .module) }
    static var session: String { String(localized: "limits.session", defaultValue: "5h", bundle: .module) }
    static var weekly: String { String(localized: "limits.weekly", defaultValue: "wk", bundle: .module) }

    /// Strings handed to `ResetTextFormatter`. A translation whose placeholders differ from
    /// English falls back to English, so `String(format:)` can never receive a mismatched format.
    static var resetTextStrings: ResetTextStrings {
        let english = ResetTextStrings.english
        return ResetTextStrings(
            idle: idle,
            reset: reset,
            inFormat: safeFormat(inShort, fallback: english.inFormat),
            tooltipFormat: safeFormat(tooltipResetAt, fallback: english.tooltipFormat),
            justNow: justNow,
            agoFormat: safeFormat(agoFormat, fallback: english.agoFormat)
        )
    }

    static func safeFormat(_ localized: String, fallback: String) -> String {
        placeholderCount(localized) == placeholderCount(fallback) ? localized : fallback
    }

    static func placeholderCount(_ format: String) -> Int {
        let pattern = #"%(?:\d+\$)?[@dsfl]+"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return 0 }
        let range = NSRange(format.startIndex..., in: format)
        return regex.numberOfMatches(in: format, range: range)
    }
}
