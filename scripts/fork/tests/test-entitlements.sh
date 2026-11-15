#!/usr/bin/env bash
# cmux.fork.entitlements = release entitlements minus the team-restricted keys.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ent="$here/../cmux.fork.entitlements"

fail=0
if plutil -lint "$ent" >/dev/null 2>&1; then
  echo "ok: plutil -lint"
else
  echo "FAIL: plutil -lint $ent"
  fail=1
fi

dump="$(plutil -p "$ent" 2>/dev/null || true)"

for key in application-identifier team-identifier keychain-access-groups application-groups \
           networkextension system-extension.install web-browser.public-key-credential; do
  if printf '%s\n' "$dump" | grep -qF "$key"; then
    echo "FAIL: must not contain $key"
    fail=1
  else
    echo "ok: absent $key"
  fi
done

for key in cs.allow-jit cs.allow-unsigned-executable-memory cs.disable-library-validation \
           automation.apple-events device.camera device.audio-input \
           personal-information.calendars personal-information.addressbook \
           personal-information.location personal-information.photos-library; do
  if printf '%s\n' "$dump" | grep -qF "\"com.apple.security.$key\" => true"; then
    echo "ok: present $key"
  else
    echo "FAIL: must contain com.apple.security.$key = true"
    fail=1
  fi
done

if [ "$fail" -ne 0 ]; then
  echo "test-entitlements: FAIL"
  exit 1
fi
echo "test-entitlements: PASS"
