#!/usr/bin/env bash
# create-signing-identity.sh never handles the login keychain password itself:
# no set-key-partition-list call or printed hint passes -k, and the script reads
# no password into a shell variable (security prompts on the terminal instead).
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
script="$here/../create-signing-identity.sh"

fail=0
# Join backslash-continued lines so a -k on a continuation line is caught.
joined="$(awk '{ if (sub(/\\$/, "")) { buf = buf $0 } else { print buf $0; buf = "" } }' "$script")"

partition_lines="$(printf '%s\n' "$joined" | grep -n 'set-key-partition-list' || true)"
if [ -z "$partition_lines" ]; then
  echo "FAIL: no set-key-partition-list call found"
  fail=1
elif printf '%s\n' "$partition_lines" | grep -E -- '[[:space:]]-k([[:space:]]|$)'; then
  echo "FAIL: set-key-partition-list must not take -k (password on the command line)"
  fail=1
else
  echo "ok: set-key-partition-list never gets -k"
fi

if grep -nE 'KEYCHAIN_PASSWORD|read[^#]*-s' "$script"; then
  echo "FAIL: the script must not read the keychain password into a variable"
  fail=1
else
  echo "ok: no password variable"
fi

if [ "$fail" -ne 0 ]; then
  echo "test-no-password-argv: FAIL"
  exit 1
fi
echo "test-no-password-argv: PASS"
