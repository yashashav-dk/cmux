import CmuxSettings
import Foundation

/// Fork-build policy. The fork replaces the official app, so Sparkle must never
/// update it back to an upstream build; updates come from `scripts/fork/sync.sh`.
struct ForkBuildPolicy: Sendable {
    init() {}

    /// Always true in fork builds. `scripts/fork/lib.sh` greps for this exact line.
    var updaterDisabled: Bool { true }

    /// Feeds `UpdateController`'s `isDisabledByPolicy` closure.
    static func isUpdaterDisabled() -> Bool {
        ForkBuildPolicy().updaterDisabled || ManagedDevicePolicy().isEnforced(.disableAutoUpdate)
    }

    static let updatesMenuTitle: String = String(
        localized: "fork.menu.updatesViaSync",
        defaultValue: "Updates: run scripts/fork/sync.sh"
    )
}
