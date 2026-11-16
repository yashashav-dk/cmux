#!/usr/bin/env bash
# fork_xcodebuild_args prints the exact Release xcodebuild argument list, one per line.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib.sh
source "$here/../lib.sh"

fail=0
expect_list() { # <name> <expected> <actual>
  if [ "$2" = "$3" ]; then
    echo "ok: $1"
  else
    echo "FAIL: $1"
    diff <(printf '%s\n' "$2") <(printf '%s\n' "$3") | sed 's/^/  /'
    fail=1
  fi
}

common="-project
cmux.xcodeproj
-scheme
cmux
-configuration
Release
-destination
platform=macOS
-derivedDataPath
$HOME/Library/Developer/Xcode/DerivedData/cmux-fork"

signing="CODE_SIGN_IDENTITY=-
CODE_SIGN_STYLE=Manual
DEVELOPMENT_TEAM=
CODE_SIGN_ENTITLEMENTS=
PROVISIONING_PROFILE_SPECIFIER="

# Fork addition: Xcode 26.3's swift-frontend crashes in Release (default CMO)
# on the duplicate ghostty_surface_clear_selection declaration.
# shellcheck disable=SC2016 # $(inherited) is an Xcode build-setting reference
no_cmo='OTHER_SWIFT_FLAGS=$(inherited) -disable-cmo'

expected_tagged="$common
PRODUCT_BUNDLE_IDENTIFIER=com.cmuxterm.app.debug.fork-spike
$signing
CMUX_SIDEBAR_EXTENSION_POINT_ID=com.cmuxterm.app.debug.fork-spike.cmux.sidebar
CMUX_CUA_HELPER_DISPLAY_NAME=cmux Computer Use
$no_cmo
ARCHS=arm64"

expected_untagged="$common
PRODUCT_BUNDLE_IDENTIFIER=com.cmuxterm.app
$signing
CMUX_CUA_HELPER_DISPLAY_NAME=cmux Computer Use
$no_cmo
ARCHS=arm64"

tagged="$(fork_xcodebuild_args com.cmuxterm.app.debug.fork-spike spike 2>&1)"
expect_list "tagged args" "$expected_tagged" "$tagged"

untagged="$(fork_xcodebuild_args com.cmuxterm.app 2>&1)"
expect_list "untagged args" "$expected_untagged" "$untagged"

if printf '%s\n' "$untagged" | grep -q '^CMUX_SIDEBAR_EXTENSION_POINT_ID='; then
  echo "FAIL: untagged args must omit CMUX_SIDEBAR_EXTENSION_POINT_ID"
  fail=1
else
  echo "ok: untagged omits CMUX_SIDEBAR_EXTENSION_POINT_ID"
fi

# Staging stays out of ~/Applications, which LaunchServices indexes on its own.
if [ "$FORK_STAGING_DIR" = "$HOME/Library/Application Support/cmux-fork/staging" ]; then
  echo "ok: staging dir outside ~/Applications"
else
  echo "FAIL: FORK_STAGING_DIR is $FORK_STAGING_DIR"
  fail=1
fi

if [ "$fail" -ne 0 ]; then
  echo "test-build-args: FAIL"
  exit 1
fi
echo "test-build-args: PASS"
