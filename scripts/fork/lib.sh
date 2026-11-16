#!/usr/bin/env bash
# Shared helpers for fork tooling. Source this file; do not execute it.

FORK_BUNDLE_ID=com.cmuxterm.app
FORK_DERIVED_DATA="$HOME/Library/Developer/Xcode/DerivedData/cmux-fork"
FORK_TEST_DERIVED_DATA="$HOME/Library/Developer/Xcode/DerivedData/cmux-fork-tests"
# Not ~/Applications: LaunchServices indexes that on its own, so a staged bundle
# could claim cmux:// or the stable bundle id there.
FORK_STAGING_DIR="$HOME/Library/Application Support/cmux-fork/staging"
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
  # Apple Silicon only: the project's Release default builds arm64 and x86_64
  # (ONLY_ACTIVE_ARCH=NO), which doubles build time and size for no benefit here.
  printf '%s\n' 'ARCHS=arm64'
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

FORK_LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

# fork_tag_auth_scheme <tag>: the tag's auth-callback URL scheme (reload.sh's cmux-dev-<slug>).
fork_tag_auth_scheme() {
  printf 'cmux-dev-fork-%s\n' "${1:?tag required}"
}

# fork_apply_url_scheme <info_plist> [tag]: with a tag, point the .auth URL type
# (CFBundleURLTypes:1) at the tag's scheme so a tagged build never claims cmux://,
# as reload.sh's set_plist_url_scheme does. Without a tag, only check that it is
# still cmux. Fails, leaving the file alone, if entry 1 is not the .auth type.
fork_apply_url_scheme() {
  local plist="${1:?Info.plist path required}" tag="${2:-}" name current
  name=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleURLTypes:1:CFBundleURLName' "$plist" 2>/dev/null) || name=""
  case "$name" in
    *.auth) ;;
    *) echo "fork_apply_url_scheme: CFBundleURLTypes:1 is '${name:-missing}', not the .auth entry" >&2; return 1 ;;
  esac
  if [ -z "$tag" ]; then
    current=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleURLTypes:1:CFBundleURLSchemes:0' "$plist" 2>/dev/null) || current=""
    if [ "$current" != "cmux" ]; then
      echo "fork_apply_url_scheme: untagged build has auth scheme '${current:-missing}', expected cmux" >&2
      return 1
    fi
    return 0
  fi
  /usr/libexec/PlistBuddy -c "Set :CFBundleURLTypes:1:CFBundleURLSchemes:0 $(fork_tag_auth_scheme "$tag")" "$plist"
}

# fork_lsunregister <app_path>: remove the app and its nested apps from the
# LaunchServices database (builds and launches register them on their own).
fork_lsunregister() {
  local app="${1:?app path required}" nested
  [ -d "$app" ] || return 0
  while IFS= read -r -d '' nested; do
    "$FORK_LSREGISTER" -u "$nested" >/dev/null 2>&1 || true
  done < <(find "$app/Contents" -type d -name '*.app' -print0 2>/dev/null)
  "$FORK_LSREGISTER" -u "$app" >/dev/null 2>&1 || true
}

# fork_tagged_app_pids <executable>: pids running exactly that executable.
# -a: macOS pgrep otherwise skips our ancestors (e.g. run from a terminal in that app).
# Anchored so a wrapper whose arguments mention the path does not match.
fork_tagged_app_pids() {
  pgrep -a -f "^${1:?executable required}( |\$)" || true
}

# fork_version_args <pbxproj_path>: prints the fork version overrides, one per line:
# CURRENT_PROJECT_VERSION=<upstream build + 10000> and MARKETING_VERSION=<upstream>-fork.
fork_version_args() {
  local pbx="${1:?pbxproj path required}" build marketing
  build=$(sed -n 's/^[[:space:]]*CURRENT_PROJECT_VERSION = \([0-9][0-9]*\);.*/\1/p' "$pbx" | head -n 1)
  marketing=$(sed -n 's/^[[:space:]]*MARKETING_VERSION = \([^;]*\);.*/\1/p' "$pbx" | head -n 1)
  if [ -z "$build" ] || [ -z "$marketing" ]; then
    echo "fork_version_args: no CURRENT_PROJECT_VERSION/MARKETING_VERSION in $pbx" >&2
    return 1
  fi
  printf 'CURRENT_PROJECT_VERSION=%s\n' "$((build + 10000))"
  printf 'MARKETING_VERSION=%s-fork\n' "$marketing"
}

# fork_assert_updater_disabled <repo_root>: static guard that the policy wiring is
# intact. The behavioral proof is the app-target test lane run by sync.sh.
fork_assert_updater_disabled() {
  local root="${1:-.}"
  if ! grep -qF 'isDisabledByPolicy: ForkBuildPolicy.isUpdaterDisabled' "$root/Sources/AppDelegate.swift"; then
    echo "updater guard: Sources/AppDelegate.swift no longer uses ForkBuildPolicy.isUpdaterDisabled" >&2
    return 1
  fi
  if ! grep -qF 'var updaterDisabled: Bool { true }' "$root/Sources/Fork/ForkBuildPolicy.swift" 2>/dev/null; then
    echo "updater guard: Sources/Fork/ForkBuildPolicy.swift does not hard-disable the updater" >&2
    return 1
  fi
}
