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

Placeholder (filled in a later task).
