public import CmuxSettings

/// Settings key for the top-level `claudeLimits` object in `cmux.json`.
///
/// Deliberately not registered in `SettingCatalog`; callers read it through
/// `SettingsRuntime.jsonStore.values(for:)` so edits reload live.
public enum ClaudeLimitsSettingsKey {
    public static let configuration = JSONKey<ClaudeLimitsConfiguration>(
        id: "claudeLimits",
        defaultValue: .default
    )
}
