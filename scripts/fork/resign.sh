#!/usr/bin/env bash
# Re-sign an app bundle inside-out and verify it.
#
# Usage: resign.sh <app_path> [identity] [entitlements]
#   identity      default: cmux-fork-local
#   entitlements  default: scripts/fork/cmux.fork.entitlements
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$here/lib.sh"

if [ $# -lt 1 ] || [ $# -gt 3 ]; then
  echo "usage: resign.sh <app_path> [identity] [entitlements]" >&2
  exit 2
fi
APP="$1"
IDENTITY="${2:-$FORK_SIGN_IDENTITY}"
ENTITLEMENTS="${3:-$here/cmux.fork.entitlements}"

fork_resign "$APP" "$IDENTITY" "$ENTITLEMENTS"
fork_verify_signature "$APP"
