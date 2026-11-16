public import Foundation

/// Tolerant decoder for the undocumented `/api/oauth/usage` payload.
/// Unknown keys are ignored, `null` is accepted anywhere, malformed rows are dropped.
public struct UsagePayloadDecoder: Sendable {
    public init() {}

    public func decode(_ data: Data, fetchedAt: Date) throws -> UsageSnapshot {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw UsageDecodeError.notJSON
        }
        var windows: [UsageWindow] = []
        if let rows = root["limits"] as? [Any] {
            windows = rows.compactMap { ($0 as? [String: Any]).flatMap(Self.window(fromLimit:)) }
        }
        if windows.isEmpty {
            if let w = Self.legacyWindow(root["five_hour"], kind: .session) { windows.append(w) }
            if let w = Self.legacyWindow(root["seven_day"], kind: .weeklyAll) { windows.append(w) }
        }
        guard !windows.isEmpty else { throw UsageDecodeError.noUsageFields }
        return UsageSnapshot(windows: windows, fetchedAt: fetchedAt)
    }

    private static func window(fromLimit row: [String: Any]) -> UsageWindow? {
        guard let kindRaw = row["kind"] as? String,
              let kind = UsageLimitKind(rawValue: kindRaw),
              let percent = number(row["percent"]) else { return nil }
        let severity = (row["severity"] as? String).map(UsageSeverity.init(raw:)) ?? .normal
        return UsageWindow(
            kind: kind,
            percent: percent,
            resetsAt: date(row["resets_at"]),
            severity: severity,
            isActive: (row["is_active"] as? Bool) ?? false,
            scopeLabel: scopeLabel(row["scope"])
        )
    }

    private static func legacyWindow(_ value: Any?, kind: UsageLimitKind) -> UsageWindow? {
        guard let dict = value as? [String: Any], let percent = number(dict["utilization"]) else {
            return nil
        }
        return UsageWindow(kind: kind, percent: percent, resetsAt: date(dict["resets_at"]))
    }

    private static func scopeLabel(_ value: Any?) -> String? {
        guard let scope = value as? [String: Any] else { return nil }
        for key in ["model", "surface"] {
            if let inner = scope[key] as? [String: Any],
               let name = inner["display_name"] as? String, !name.isEmpty {
                return name
            }
        }
        return nil
    }

    /// JSON numbers only; strings and booleans are rejected.
    private static func number(_ value: Any?) -> Double? {
        guard let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else { return nil }
        return n.doubleValue
    }

    private static func date(_ value: Any?) -> Date? {
        guard let string = value as? String else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = fractional.date(from: string) { return d }
        return ISO8601DateFormatter().date(from: string)
    }
}
