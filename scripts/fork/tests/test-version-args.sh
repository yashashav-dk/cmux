#!/usr/bin/env bash
# fork_version_args derives the fork version from the pbxproj; fork_assert_updater_disabled guards the wiring.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib.sh
source "$here/../lib.sh"

fail=0
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

check() { # <name> <expected> <actual>
  if [ "$2" = "$3" ]; then echo "ok: $1"; else echo "FAIL: $1"; diff <(printf '%s\n' "$2") <(printf '%s\n' "$3") | sed 's/^/  /'; fail=1; fi
}

cat > "$tmp/project.pbxproj" <<'P'
		AAA /* Debug */ = {
			buildSettings = {
				CURRENT_PROJECT_VERSION = 113;
				MARKETING_VERSION = 0.65.2;
			};
		};
P
check "version args" "CURRENT_PROJECT_VERSION=10113
MARKETING_VERSION=0.65.2-fork" "$(fork_version_args "$tmp/project.pbxproj")"

: > "$tmp/empty.pbxproj"
if fork_version_args "$tmp/empty.pbxproj" >/dev/null 2>&1; then echo "FAIL: empty pbxproj must fail"; fail=1; else echo "ok: empty pbxproj fails"; fi

mkdir -p "$tmp/Sources/Fork"
echo '        isDisabledByPolicy: ForkBuildPolicy.isUpdaterDisabled' > "$tmp/Sources/AppDelegate.swift"
echo '    var updaterDisabled: Bool { true }' > "$tmp/Sources/Fork/ForkBuildPolicy.swift"
if fork_assert_updater_disabled "$tmp" 2>/dev/null; then echo "ok: guard passes"; else echo "FAIL: guard should pass"; fail=1; fi
echo '        isDisabledByPolicy: { ManagedDevicePolicy().isEnforced(.disableAutoUpdate) }' > "$tmp/Sources/AppDelegate.swift"
if fork_assert_updater_disabled "$tmp" 2>/dev/null; then echo "FAIL: guard must reject reverted AppDelegate"; fail=1; else echo "ok: guard rejects reverted AppDelegate"; fi
echo '        isDisabledByPolicy: ForkBuildPolicy.isUpdaterDisabled' > "$tmp/Sources/AppDelegate.swift"
echo '    var updaterDisabled: Bool { false }' > "$tmp/Sources/Fork/ForkBuildPolicy.swift"
if fork_assert_updater_disabled "$tmp" 2>/dev/null; then echo "FAIL: guard must reject enabled policy"; fail=1; else echo "ok: guard rejects enabled policy"; fi

if [ "$fail" -ne 0 ]; then echo "test-version-args: FAIL"; exit 1; fi
echo "test-version-args: PASS"
