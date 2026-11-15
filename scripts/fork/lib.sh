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

# Self-signed code-signing identity created by create-signing-identity.sh.
FORK_SIGN_IDENTITY=cmux-fork-local
FORK_LOGIN_KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

# fork_preflight: toolchain and disk checks before a build. Lists other cmux-*
# DerivedData dirs and, on a TTY, offers to delete them (default: keep).
fork_preflight() {
  local result=0 xcode zig_version free_gb answer dir
  local dd_root="$HOME/Library/Developer/Xcode/DerivedData"
  local others=()

  # No `| head`: under pipefail its early exit SIGPIPEs xcodebuild and fails the check.
  xcode=$(xcodebuild -version 2>/dev/null) || xcode=""
  xcode=${xcode%%$'\n'*}
  case "$xcode" in
    "Xcode 26."*) echo "preflight: $xcode" ;;
    *) echo "preflight: need Xcode 26.x, found '${xcode:-none}'" >&2; result=1 ;;
  esac

  if xcrun metal --version >/dev/null 2>&1; then
    echo "preflight: Metal toolchain present"
  else
    echo "preflight: Metal toolchain missing (xcodebuild -downloadComponent MetalToolchain)" >&2
    result=1
  fi

  zig_version=$("$FORK_ZIG_BIN/zig" version 2>/dev/null) || zig_version=""
  case "$zig_version" in
    0.16.*) echo "preflight: zig $zig_version ($FORK_ZIG_BIN)" ;;
    *) echo "preflight: need zig 0.16.x at $FORK_ZIG_BIN (brew install zig@0.16), found '${zig_version:-none}'" >&2; result=1 ;;
  esac

  if [ -x "$HOME/.cargo/bin/rustup" ]; then
    echo "preflight: rustup present"
  else
    echo "preflight: rustup missing at ~/.cargo/bin/rustup (https://rustup.rs)" >&2
    result=1
  fi

  for dir in "$dd_root"/cmux-*; do
    [ -d "$dir" ] || continue
    [ "$dir" = "$FORK_DERIVED_DATA" ] && continue
    others+=("$dir")
  done
  if [ "${#others[@]}" -gt 0 ]; then
    echo "preflight: other cmux DerivedData dirs:"
    for dir in "${others[@]}"; do
      echo "  $(du -sh "$dir" 2>/dev/null | cut -f1)	$dir"
    done
    if [ -t 0 ]; then
      read -r -p "Delete these DerivedData dirs? [y/N] " answer
      if [ "$answer" = "y" ] || [ "$answer" = "Y" ]; then
        for dir in "${others[@]}"; do rm -rf "$dir"; done
        echo "preflight: deleted ${#others[@]} DerivedData dir(s)"
      fi
    else
      echo "preflight: not a TTY; keeping them (delete with rm -rf to free space)"
    fi
  fi

  free_gb=$(df -Pk "$HOME" | awk 'NR == 2 { print int($4 / 1048576) }')
  if [ "${free_gb:-0}" -ge "$FORK_MIN_FREE_GB" ]; then
    echo "preflight: ${free_gb} GB free (floor ${FORK_MIN_FREE_GB} GB)"
  else
    echo "preflight: only ${free_gb:-0} GB free, need ${FORK_MIN_FREE_GB} GB (CMUX_FORK_MIN_FREE_GB overrides)" >&2
    result=1
  fi

  return "$result"
}

# fork_xcodebuild_args <bundle_id> [tag]: the Release xcodebuild arguments, one
# per line (read them with `while IFS= read -r`; some contain spaces). The
# caller appends the action (`build`).
fork_xcodebuild_args() {
  local bundle_id="${1:?bundle id required}" tag="${2:-}"
  printf '%s\n' \
    -project cmux.xcodeproj \
    -scheme cmux \
    -configuration Release \
    -destination platform=macOS \
    -derivedDataPath "$FORK_DERIVED_DATA" \
    "PRODUCT_BUNDLE_IDENTIFIER=$bundle_id" \
    CODE_SIGN_IDENTITY=- \
    CODE_SIGN_STYLE=Manual \
    DEVELOPMENT_TEAM= \
    CODE_SIGN_ENTITLEMENTS= \
    PROVISIONING_PROFILE_SPECIFIER=
  # Scope the sidebar ExtensionKit point per tag, as reload.sh does.
  if [ -n "$tag" ]; then
    printf '%s\n' "CMUX_SIDEBAR_EXTENSION_POINT_ID=$bundle_id.cmux.sidebar"
  fi
  printf '%s\n' "CMUX_CUA_HELPER_DISPLAY_NAME=cmux Computer Use"
  # Xcode 26.3 (Swift 6.2.4) crashes in Release with default cross-module
  # optimization: CmuxTerminalCore's @_silgen_name ghostty_surface_clear_selection
  # and GhosttyKit's header declaration of it fail SIL deserialization in the
  # app module. Upstream CI builds with Xcode 26.6; re-check after upgrading.
  # shellcheck disable=SC2016 # $(inherited) is an Xcode build-setting reference
  printf '%s\n' 'OTHER_SWIFT_FLAGS=$(inherited) -disable-cmo'
}

# fork_require_sign_identity <identity>: fail unless the certificate exists in
# the login keychain; warn when it is not yet trusted for code signing.
fork_require_sign_identity() {
  local identity="${1:?identity required}"
  if ! security find-certificate -c "$identity" "$FORK_LOGIN_KEYCHAIN" >/dev/null 2>&1; then
    echo "signing identity '$identity' not found in the login keychain." >&2
    echo "Run in Terminal.app: bash scripts/fork/create-signing-identity.sh" >&2
    return 1
  fi
  local valid
  valid=$(security find-identity -v -p codesigning "$FORK_LOGIN_KEYCHAIN" 2>/dev/null) || valid=""
  case "$valid" in
    *"\"$identity\""*) ;;
    *) echo "warning: '$identity' is not marked Always Trust for Code Signing in Keychain Access" >&2 ;;
  esac
}

# fork_resign <app_path> <identity> <entitlements>: re-sign inside-out.
# 1. every Mach-O file under Contents/, 2. nested bundles deepest first
# (the dock tile plugin is CmuxDockTilePlugin.plugin), 3. the app itself with
# the hardened runtime and <entitlements>.
fork_resign() {
  local app="${1:?app path required}" identity="${2:?identity required}" entitlements="${3:?entitlements required}"
  local file_path bundle kind requested
  if [ ! -d "$app/Contents" ]; then
    echo "fork_resign: not an app bundle: $app" >&2
    return 1
  fi
  if [ ! -f "$entitlements" ]; then
    echo "fork_resign: entitlements not found: $entitlements" >&2
    return 1
  fi

  # Finder info and resource forks make codesign --strict fail (this xattr has no -r).
  find "$app" -exec xattr -cs {} +

  # The packet-tunnel system extension needs the NetworkExtension entitlement,
  # which a self-signed identity cannot carry. Upstream's signer drops the
  # extension in the same case (scripts/sign-cmux-bundle.sh).
  requested=$(plutil -p "$entitlements")
  if [ -d "$app/Contents/Library/SystemExtensions" ] &&
     [[ "$requested" != *com.apple.developer.networking.networkextension* ]]; then
    echo "fork_resign: removing Contents/Library/SystemExtensions (no Cloud tunnel entitlement)"
    rm -rf "$app/Contents/Library/SystemExtensions"
  fi

  while IFS= read -r -d '' file_path; do
    kind=$(file -b "$file_path")
    case "$kind" in
      *Mach-O*object* | *Mach-O*dSYM*) continue ;;
      *Mach-O*) codesign --force --timestamp=none --sign "$identity" "$file_path" || return 1 ;;
    esac
  done < <(find "$app/Contents" -type f -print0)

  while IFS= read -r bundle; do
    [ -n "$bundle" ] || continue
    codesign --force --timestamp=none --sign "$identity" "$bundle" || return 1
  done < <(find "$app/Contents" -type d \( -name '*.app' -o -name '*.appex' -o -name '*.xpc' \
             -o -name '*.framework' -o -name '*.systemextension' -o -name '*.docktileplugin' \
             -o -name '*.plugin' \) |
           awk -F/ '{ print NF "\t" $0 }' | sort -rn | cut -f2-)

  codesign --force --timestamp=none --options runtime --entitlements "$entitlements" \
    --sign "$identity" "$app"
}

# fork_verify_signature <app_path>
fork_verify_signature() {
  codesign --verify --deep --strict --verbose=2 "${1:?app path required}"
}
