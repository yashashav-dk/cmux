#!/usr/bin/env bash
# Tagged builds must not claim the real cmux:// scheme: fork_apply_url_scheme
# rewrites the .auth URL type to cmux-dev-fork-<tag> and leaves untagged builds alone.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib.sh
source "$here/../lib.sh"

fail=0
check() { # <name> <expected> <actual>
  if [ "$2" = "$3" ]; then echo "ok: $1"; else echo "FAIL: $1 (expected '$2', got '$3')"; fail=1; fi
}
work="$(mktemp -d "${TMPDIR:-/tmp}/fork-url-scheme-test.XXXXXX")"
trap 'rm -rf "$work"' EXIT

# Same CFBundleURLTypes layout as the built app's Info.plist (web, auth, ssh).
fixture() { # <path> <auth-entry-name> <auth-scheme>
  cat > "$1" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.cmuxterm.app.debug.fork-spike</string>
<key>CFBundleURLTypes</key><array>
  <dict><key>CFBundleURLName</key><string>com.cmuxterm.app.debug.fork-spike.web</string>
    <key>CFBundleURLSchemes</key><array><string>http</string><string>https</string></array></dict>
  <dict><key>CFBundleURLName</key><string>$2</string>
    <key>CFBundleURLSchemes</key><array><string>$3</string></array></dict>
  <dict><key>CFBundleURLName</key><string>SSH URL</string>
    <key>CFBundleURLSchemes</key><array><string>ssh</string></array></dict>
</array></dict></plist>
PLIST
}
scheme_at() { /usr/libexec/PlistBuddy -c "Print :CFBundleURLTypes:$2:CFBundleURLSchemes:$3" "$1" 2>/dev/null; }

check "tag auth scheme" "cmux-dev-fork-spike" "$(fork_tag_auth_scheme spike 2>&1)"

fixture "$work/tagged.plist" com.cmuxterm.app.debug.fork-spike.auth cmux
fork_apply_url_scheme "$work/tagged.plist" spike >/dev/null 2>&1
check "tagged: apply exit" 0 "$?"
check "tagged: auth scheme rewritten" "cmux-dev-fork-spike" "$(scheme_at "$work/tagged.plist" 1 0)"
check "tagged: web schemes kept" "http https" "$(scheme_at "$work/tagged.plist" 0 0) $(scheme_at "$work/tagged.plist" 0 1)"
check "tagged: ssh scheme kept" "ssh" "$(scheme_at "$work/tagged.plist" 2 0)"

fixture "$work/untagged.plist" com.cmuxterm.app.auth cmux
cp "$work/untagged.plist" "$work/untagged.orig"
fork_apply_url_scheme "$work/untagged.plist" >/dev/null 2>&1
check "untagged: apply exit" 0 "$?"
if cmp -s "$work/untagged.plist" "$work/untagged.orig"; then echo "ok: untagged: file untouched"; else echo "FAIL: untagged: file changed"; fail=1; fi

fixture "$work/stale.plist" com.cmuxterm.app.auth cmux-dev-fork-old
fork_apply_url_scheme "$work/stale.plist" >/dev/null 2>&1
check "untagged: stale tag scheme rejected" 1 "$?"

fixture "$work/moved.plist" com.cmuxterm.app.something-else cmux
cp "$work/moved.plist" "$work/moved.orig"
fork_apply_url_scheme "$work/moved.plist" spike >/dev/null 2>&1
check "tagged: non-auth entry at index 1 rejected" 1 "$?"
if cmp -s "$work/moved.plist" "$work/moved.orig"; then echo "ok: rejected file untouched"; else echo "FAIL: rejected file changed"; fail=1; fi

if [ "$fail" -ne 0 ]; then
  echo "test-url-scheme: FAIL"
  exit 1
fi
echo "test-url-scheme: PASS"
