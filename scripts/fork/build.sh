#!/usr/bin/env bash
# Build cmux Release into the fixed fork DerivedData, re-sign it with the
# self-signed identity, verify, and stage it.
#
# Usage: build.sh [--tag <t>] [--launch] [--dry-run] [--skip-setup]
#   (no --tag)  bundle id com.cmuxterm.app, staged at $FORK_STAGING_DIR/cmux.app.
#               Never launched by this script.
#   --tag <t>   bundle id com.cmuxterm.app.debug.fork-<t>, staged at
#               $FORK_STAGING_DIR/<t>/cmux.app.
#   --launch    after staging, run launch-tagged.sh <t> (requires --tag).
#   --dry-run   print every command without running anything.
#   --skip-setup  skip scripts/setup.sh (submodules, Rust toolchain, GhosttyKit).
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$here/lib.sh"

usage() { sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; }

TAG=""
LAUNCH=0
DRY_RUN=0
SKIP_SETUP=0
while [ $# -gt 0 ]; do
  case "$1" in
    --tag) TAG="${2:-}"; [ -n "$TAG" ] || { echo "error: --tag needs a value" >&2; exit 2; }; shift 2 ;;
    --launch) LAUNCH=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    --skip-setup) SKIP_SETUP=1; shift ;;
    -h | --help) usage; exit 0 ;;
    *) echo "error: unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

if [ -n "$TAG" ] && [[ ! "$TAG" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then
  echo "error: tag must match [a-z0-9][a-z0-9-]*: $TAG" >&2
  exit 2
fi
if [ "$LAUNCH" -eq 1 ] && [ -z "$TAG" ]; then
  echo "error: --launch needs --tag; the untagged build shares the stable bundle id and is never launched here" >&2
  exit 2
fi

if [ -n "$TAG" ]; then
  BUNDLE_ID="com.cmuxterm.app.debug.fork-$TAG"
  STAGED_APP="$FORK_STAGING_DIR/$TAG/cmux.app"
else
  BUNDLE_ID="$FORK_BUNDLE_ID"
  STAGED_APP="$FORK_STAGING_DIR/cmux.app"
fi
BUILT_APP="$FORK_DERIVED_DATA/Build/Products/Release/cmux.app"
ENTITLEMENTS="$here/cmux.fork.entitlements"
REPO_ROOT="$(cd "$here/../.." && pwd)"

XCODEBUILD_ARGS=()
while IFS= read -r arg; do
  XCODEBUILD_ARGS+=("$arg")
done < <(fork_xcodebuild_args "$BUNDLE_ID" "$TAG")
# Fork version: upstream build + 10000, marketing version suffixed -fork.
while IFS= read -r arg; do
  XCODEBUILD_ARGS+=("$arg")
done < <(fork_version_args "$(cd "$here/../.." && pwd)/cmux.xcodeproj/project.pbxproj")
XCODEBUILD_ARGS+=(build)

run() {
  if [ "$DRY_RUN" -eq 1 ]; then
    printf '+'
    printf ' %q' "$@"
    printf '\n'
  else
    "$@"
  fi
}

check_built_app() {
  local actual
  actual=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$BUILT_APP/Contents/Info.plist")
  if [ "$actual" != "$BUNDLE_ID" ]; then
    echo "error: $BUILT_APP has bundle id $actual, expected $BUNDLE_ID" >&2
    return 1
  fi
}

refuse_if_staged_running() {
  local pids
  pids=$(fork_tagged_app_pids "$STAGED_APP/Contents/MacOS/cmux")
  if [ -n "$pids" ]; then
    echo "error: the staged app is running (pid $pids); quit it before restaging" >&2
    return 1
  fi
}

# zig 0.16 and rustup must be on PATH for setup.sh and for xcodebuild's
# build-phase scripts (Ghostty CLI helper, diff sidecar).
NEW_PATH="$FORK_ZIG_BIN:$HOME/.cargo/bin:$PATH"
if [ "$DRY_RUN" -eq 1 ]; then
  printf '+ cd %q\n' "$REPO_ROOT"
  # shellcheck disable=SC2016 # $PATH is printed literally
  printf '+ export PATH=%q:%q:$PATH\n' "$FORK_ZIG_BIN" "$HOME/.cargo/bin"
fi
cd "$REPO_ROOT"
export PATH="$NEW_PATH"

run fork_assert_updater_disabled "$REPO_ROOT"
run fork_preflight
run fork_require_sign_identity "$FORK_SIGN_IDENTITY"
if [ "$SKIP_SETUP" -eq 0 ]; then
  run ./scripts/setup.sh
fi
run xcodebuild "${XCODEBUILD_ARGS[@]}"
run check_built_app
# Tagged builds get their own auth URL scheme instead of cmux:// (before signing).
run fork_apply_url_scheme "$BUILT_APP/Contents/Info.plist" "$TAG"
run fork_resign "$BUILT_APP" "$FORK_SIGN_IDENTITY" "$ENTITLEMENTS"
run fork_verify_signature "$BUILT_APP"
run refuse_if_staged_running
run mkdir -p "$(dirname "$STAGED_APP")"
run rm -rf "$STAGED_APP"
run ditto "$BUILT_APP" "$STAGED_APP"
run fork_verify_signature "$STAGED_APP"
# The build registers its products with LaunchServices; keep them out of it so
# no fork bundle can take cmux:// links or stand in for the installed app.
run fork_lsunregister "$BUILT_APP"
run fork_lsunregister "$STAGED_APP"
if [ "$DRY_RUN" -eq 0 ]; then
  echo "Staged $BUNDLE_ID at $STAGED_APP"
fi
if [ "$LAUNCH" -eq 1 ]; then
  run "$here/launch-tagged.sh" "$TAG"
fi
