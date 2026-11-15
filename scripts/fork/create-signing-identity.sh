#!/usr/bin/env bash
# One-time: create the self-signed code-signing identity cmux-fork-local in the
# login keychain. Signing every fork build with it keeps the designated
# requirement stable, so privacy grants and keychain ACLs survive rebuilds.
#
# Run it yourself in Terminal.app: it asks for your login keychain password.
# Safe to re-run: it does nothing when the certificate already exists.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$here/lib.sh"

NAME="$FORK_SIGN_IDENTITY"
KEYCHAIN="$FORK_LOGIN_KEYCHAIN"

print_trust_step() {
  cat <<EOF

One manual step (trusting a certificate system-wide needs admin, so it is not scripted):
  1. Open Keychain Access (open "/System/Library/CoreServices/Applications/Keychain Access.app"),
     select the login keychain, find the certificate "$NAME".
  2. Double-click it and expand "Trust".
  3. Set "Code Signing" to "Always Trust", close the window, enter your password.
  4. Check: security find-identity -v -p codesigning | grep $NAME
EOF
}

# find-certificate, not find-identity -v: the latter lists only trusted
# identities, so a not-yet-trusted certificate would be created again.
if security find-certificate -c "$NAME" "$KEYCHAIN" >/dev/null 2>&1; then
  echo "$NAME already exists in the login keychain; nothing to create."
  valid=$(security find-identity -v -p codesigning "$KEYCHAIN" 2>/dev/null) || valid=""
  case "$valid" in
    *"\"$NAME\""*) echo "It is trusted for code signing." ;;
    *) print_trust_step ;;
  esac
  exit 0
fi

if [ ! -t 0 ]; then
  echo "error: run this in Terminal.app; it prompts for your login keychain password" >&2
  exit 1
fi

umask 077
work=$(mktemp -d "${TMPDIR:-/tmp}/cmux-fork-identity.XXXXXX")
trap 'rm -rf "$work"' EXIT

cat > "$work/openssl.cnf" <<'EOF'
[req]
distinguished_name = dn
x509_extensions = codesign
[dn]
[codesign]
keyUsage = digitalSignature
extendedKeyUsage = critical,codeSigning
EOF

# /usr/bin/openssl (LibreSSL) writes PKCS#12 that `security import` accepts;
# a Homebrew OpenSSL 3 earlier on PATH would need -legacy.
/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
  -subj "/CN=$NAME" -config "$work/openssl.cnf" \
  -keyout "$work/key.pem" -out "$work/cert.pem"

P12_PASS=$(/usr/bin/openssl rand -hex 16)
export P12_PASS
/usr/bin/openssl pkcs12 -export -name "$NAME" \
  -inkey "$work/key.pem" -in "$work/cert.pem" \
  -out "$work/identity.p12" -passout env:P12_PASS

security import "$work/identity.p12" -k "$KEYCHAIN" -P "$P12_PASS" \
  -T /usr/bin/codesign -T /usr/bin/security
unset P12_PASS

# Let codesign use the key without a prompt. -l limits the change to this key.
read -r -s -p "Login keychain password (lets codesign use the new key): " KEYCHAIN_PASSWORD
echo
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -l "$NAME" \
  -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN" >/dev/null
unset KEYCHAIN_PASSWORD

echo "Created $NAME in the login keychain."
print_trust_step
