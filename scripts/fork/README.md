# Fork tooling

Personal fork of cmux that adds a Claude usage-limits panel. This directory holds
fork-only helper scripts; nothing here is part of the app.

## Branch model

- `main` mirrors `upstream/main` (never commit here; the file-length budget script compares against `origin/main`).
- `fork/main` = upstream's latest GitHub release tag plus fork commits. The tag is
  resolved with `gh api repos/manaflow-ai/cmux/releases/latest --jq .tag_name`, never by sorting tags.
- Remotes: `origin` = the fork, `upstream` = `manaflow-ai/cmux`. HTTPS only.

## Commands

- `source scripts/fork/lib.sh` for helpers and constants (`fork_latest_release_tag`, `fork_upstream_base`, `fork_require_gh_account`).
- `bash scripts/fork/install-git-hooks.sh` links `.git/hooks/pre-push` to the pre-push scanner kept outside the repo at `~/.config/cmux-fork/hooks/`.
- `bash scripts/fork/create-signing-identity.sh` (once, by hand in Terminal.app): creates the
  self-signed code-signing certificate `cmux-fork-local` in the login keychain, asks for the login
  keychain password, then prints the Keychain Access step to mark it "Always Trust" for Code Signing.
  Re-running it is a no-op once the certificate exists.
- `bash scripts/fork/build.sh [--tag <t>] [--launch] [--dry-run] [--skip-setup]`: preflight
  (Xcode 26, Metal, zig 0.16, rustup, free space; lists other `cmux-*` DerivedData dirs), `scripts/setup.sh`,
  Release `xcodebuild` into `~/Library/Developer/Xcode/DerivedData/cmux-fork`, re-sign with
  `cmux-fork-local` + `cmux.fork.entitlements`, verify, stage. Untagged: bundle id `com.cmuxterm.app`,
  staged at `~/Library/Application Support/cmux-fork/staging/cmux.app`, never launched by tooling. `--tag <t>`:
  bundle id `com.cmuxterm.app.debug.fork-<t>`, staged at `~/Library/Application Support/cmux-fork/staging/<t>/cmux.app`,
  and its `.auth` URL type is rewritten from `cmux` to `cmux-dev-fork-<t>` before signing (as reload.sh does), so
  a tagged build never claims `cmux://`. Staging is outside `~/Applications`, which LaunchServices indexes on its
  own, and build.sh unregisters both the DerivedData product and the staged copy from LaunchServices at the end.
  The build passes `ARCHS=arm64`: the project's Release configuration defaults to arm64 + x86_64
  (`ONLY_ACTIVE_ARCH = NO`, no `ARCHS` override), and the fork only targets Apple Silicon, so this
  halves compile and link work. It also sets `CURRENT_PROJECT_VERSION` to upstream build + 10000 and
  `MARKETING_VERSION` to `<upstream>-fork` (read from the pbxproj by `fork_version_args`), and
  `fork_assert_updater_disabled` fails the build if the updater policy wiring is reverted.
  The build passes `OTHER_SWIFT_FLAGS=$(inherited) -disable-cmo`: with Xcode 26.3 the Release build's default
  cross-module optimization crashes swift-frontend (SIL deserialization of `ghostty_surface_clear_selection`,
  declared both in GhosttyKit's header and with `@_silgen_name` in CmuxTerminalCore). Upstream builds with Xcode 26.6.
- `bash scripts/fork/launch-tagged.sh <t>`: launches a staged tagged build by path through a one-shot
  launchd job running `env -i` with the tag's own `CMUX_TAG`, socket paths and auth scheme. It refuses any
  bundle whose id is not `com.cmuxterm.app.debug.fork-<t>`. When the app quits, the job unregisters it from
  LaunchServices and deletes its launch log dir (kept after a non-zero exit). Quit the app from its own menu,
  then run `bash scripts/fork/launch-tagged.sh --cleanup <t>` (unloads the job, unregisters, removes the
  socket and leftover logs).
- `bash scripts/fork/resign.sh <app> [identity] [entitlements]`: re-sign an app inside-out and verify it.
- Tests: `bash scripts/fork/tests/test-build-args.sh`, `bash scripts/fork/tests/test-entitlements.sh`,
  `bash scripts/fork/tests/test-url-scheme.sh`, `bash scripts/fork/tests/test-no-password-argv.sh`, `bash scripts/fork/tests/test-version-args.sh`.

## Updater and telemetry

- Sparkle is disabled in code: `Sources/AppDelegate.swift` passes `ForkBuildPolicy.isUpdaterDisabled`
  (`Sources/Fork/ForkBuildPolicy.swift`, always true) as the `isDisabledByPolicy` closure, so no check is
  scheduled or performed. "Check for Updates" in the app menu and the menu bar extra is relabelled
  "Updates: run scripts/fork/sync.sh". Fork updates come from `sync.sh`.
- Telemetry: the fork reports its version `0.65.2-fork` to upstream's PostHog when
  `app.sendAnonymousTelemetry` is on. Recommended: set it to `false` in `~/.config/cmux/cmux.json`.
  No code change (keeps the touch surface minimal).

## Anchor check at `v0.65.2.2`

All anchors resolve, except one that moved:

| Anchor | Result |
| --- | --- |
| `isDisabledByPolicy: { ManagedDevicePolicy` in `Sources/AppDelegate.swift` | found |
| `private struct SidebarFooter` in `Sources/ContentView.swift` | found |
| `SidebarFooter(` in `Sources/ContentView.swift` | found |
| `bottomScrimHeight` | found (`WindowChromeMetrics.swift:84,102`, `ContentView.swift:11696`) |
| `static func applyListInsets` in `SidebarWorkspaceTableController.swift` | MISSING; no such function exists in `Sources`. Relocated to the inline `scrollView.contentInsets = NSEdgeInsets(` block in the same file (~line 253), which uses `SidebarWorkspaceScrollInsets.workspaceList` (`WindowChromeMetrics.swift:~100`) |
| `"menu.app.checkForUpdates"` in `Sources/cmuxApp.swift` | found |
| `"menu.checkForUpdates"` in `Sources/App/MenuBarExtraController.swift` | found |
| `additionalProperties` in `web/data/cmux.schema.json` | found |
| `scripts/` generate-cmux-config-schema.py, swift_file_length_budget.py, sync-test-wiring, wire-app-sources.py, check-workspace-package-groups.py, normalize-pbxproj.py, localization_catalog.py, test-unit.sh | all present |

## Dropped entitlements

`cmux.fork.entitlements` is `cmux.release.entitlements` without the seven keys tied to the upstream
team and its provisioning profiles, which a self-signed identity cannot carry:
`com.apple.application-identifier`, `com.apple.developer.team-identifier`, `keychain-access-groups`,
`com.apple.security.application-groups`, `com.apple.developer.networking.networkextension`,
`com.apple.developer.system-extension.install`, `com.apple.developer.web-browser.public-key-credential`.

Because the NetworkExtension entitlement is gone, `fork_resign` deletes
`Contents/Library/SystemExtensions` (the Cloud tunnel extension) before signing, as upstream's
`scripts/sign-cmux-bundle.sh` does for any signing run without that entitlement. The Cloud tunnel is
therefore unavailable in fork builds.

Keys dropped because they stopped a self-signed build from launching: none. The tagged spike build
(`build.sh --tag spike`, 2026-11-14, Xcode 26.3) launched with all ten kept keys and no `amfid`/`taskgated` rejection.
