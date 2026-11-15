#!/usr/bin/env bash
# Shared helpers for fork tooling. Source this file; do not execute it.

FORK_BUNDLE_ID=com.cmuxterm.app
FORK_DERIVED_DATA="$HOME/Library/Developer/Xcode/DerivedData/cmux-fork"
FORK_TEST_DERIVED_DATA="$HOME/Library/Developer/Xcode/DerivedData/cmux-fork-tests"
FORK_STAGING_DIR="$HOME/Applications/cmux-fork-staging"
FORK_BACKUPS_DIR="$HOME/Library/Application Support/cmux-fork/backups"
FORK_ZIG_BIN=/opt/homebrew/opt/zig@0.16/bin
FORK_MIN_FREE_GB=${CMUX_FORK_MIN_FREE_GB:-15}

fork_repo_root() { git rev-parse --show-toplevel; }

# Merge-base of HEAD and upstream/main.
fork_upstream_base() { git merge-base HEAD upstream/main; }

# Latest upstream GitHub release tag (never sorted from tag names).
# CMUX_FORK_RELEASE_TAG overrides the lookup (used by tests).
fork_latest_release_tag() {
  local tag="${CMUX_FORK_RELEASE_TAG:-}"
  if [ -z "$tag" ]; then
    tag=$(gh api repos/manaflow-ai/cmux/releases/latest --jq .tag_name) || tag=""
  fi
  if [ -z "$tag" ]; then
    echo "fork_latest_release_tag: could not determine release tag" >&2
    return 1
  fi
  git fetch upstream --tags >/dev/null 2>&1 || true
  if ! git rev-parse -q --verify "refs/tags/$tag" >/dev/null; then
    echo "fork_latest_release_tag: tag $tag not present locally after fetch" >&2
    return 1
  fi
  printf '%s\n' "$tag"
}

# fork_require_gh_account <login>
fork_require_gh_account() {
  local want="${1:?login required}" active
  active=$(gh api user --jq .login 2>/dev/null) || active=""
  if [ "$active" != "$want" ]; then
    echo "gh is logged in as '${active:-none}', expected '$want'. Run: gh auth switch --user $want" >&2
    return 1
  fi
}
