public import CmuxSettings
import Foundation

/// Tolerant decoding: unknown keys are ignored, missing or malformed fields take
/// their defaults, the refresh interval is clamped to at least 60 seconds, and
/// accounts without a label are dropped. A hand-edited config never disables
/// the whole panel because of one typo.
extension ClaudeLimitsConfiguration: SettingCodable {
    public static func decodeFromUserDefaults(_ raw: Any?) -> ClaudeLimitsConfiguration? {
        decodeFromJSON(raw)
    }

    public func encodeForUserDefaults() -> Any {
        encodeForJSON()
    }

    public static func decodeFromJSON(_ raw: Any?) -> ClaudeLimitsConfiguration? {
        guard let object = raw as? [String: Any] else { return nil }
        let defaults = ClaudeLimitsConfiguration.default
        let interval = (object["refreshIntervalSeconds"] as? NSNumber).flatMap { number -> Int? in
            guard CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
            return number.intValue
        } ?? defaults.refreshIntervalSeconds
        let accounts = (object["accounts"] as? [Any] ?? []).compactMap { decodeAccount($0) }
        return ClaudeLimitsConfiguration(
            enabled: object["enabled"] as? Bool ?? defaults.enabled,
            refreshIntervalSeconds: max(60, interval),
            claudeBinary: nonEmptyString(object["claudeBinary"]) ?? defaults.claudeBinary,
            mutedColor: hexColor(object["mutedColor"]) ?? defaults.mutedColor,
            accounts: accounts
        )
    }

    public func encodeForJSON() -> Any {
        guard let data = try? JSONEncoder().encode(self),
              let object = try? JSONSerialization.jsonObject(with: data) else {
            return NSNull()
        }
        return object
    }

    private static func decodeAccount(_ raw: Any) -> ClaudeLimitsAccount? {
        guard let object = raw as? [String: Any],
              let label = nonEmptyString(object["label"]) else { return nil }
        let style = (object["style"] as? String).flatMap(AccountLabelStyle.init(rawValue:)) ?? .solo
        return ClaudeLimitsAccount(
            label: label,
            configDir: nonEmptyString(object["configDir"]),
            style: style,
            color: hexColor(object["color"])
        )
    }

    private static func nonEmptyString(_ value: Any?) -> String? {
        guard let string = value as? String, !string.isEmpty else { return nil }
        return string
    }

    private static func hexColor(_ value: Any?) -> String? {
        guard let string = value as? String,
              string.range(of: "^#[0-9a-fA-F]{6}$", options: .regularExpression) != nil else { return nil }
        return string
    }
}
