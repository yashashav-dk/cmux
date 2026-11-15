#!/usr/bin/env bash
# Launch a staged tagged fork build by path, isolated by its launch environment.
#
# Usage: launch-tagged.sh <tag>
#   Starts $FORK_STAGING_DIR/<tag>/cmux.app (bundle id com.cmuxterm.app.debug.fork-<tag>)
#   through a one-shot launchd job running `env -i ... cmux`, as reload.sh does
#   for tagged builds, so the app survives this shell and gets only the listed
#   environment. Refuses any bundle whose id is not the tagged one.
#   Quit it from its own menu; then remove the job with the printed bootout command.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$here/lib.sh"

TAG="${1:-}"
if [ -z "$TAG" ] || [[ ! "$TAG" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then
  echo "usage: launch-tagged.sh <tag>   (tag matches [a-z0-9][a-z0-9-]*)" >&2
  exit 2
fi

SLUG="fork-$TAG"
BUNDLE_ID="com.cmuxterm.app.debug.$SLUG"
APP="$FORK_STAGING_DIR/$TAG/cmux.app"
EXECUTABLE="$APP/Contents/MacOS/cmux"
LABEL="$BUNDLE_ID.launch"
DOMAIN="gui/$(id -u)"

if [ ! -x "$EXECUTABLE" ]; then
  echo "error: no staged app at $APP (run build.sh --tag $TAG)" >&2
  exit 1
fi
actual_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist")
if [ "$actual_id" != "$BUNDLE_ID" ]; then
  echo "error: refusing to launch $APP: bundle id is $actual_id, expected $BUNDLE_ID" >&2
  exit 1
fi

running=$(pgrep -f "$EXECUTABLE" || true)
if [ -n "$running" ]; then
  echo "already running: pid $running"
  exit 0
fi

tmp_root="${TMPDIR:-/tmp}"
work=$(mktemp -d "${tmp_root%/}/cmux-launch-$SLUG.XXXXXX")
LOG="$work/launch.out"
PLIST="$work/$LABEL.plist"
: > "$LOG"

ENV_ARGS=(
  /usr/bin/env -i
  HOME="$HOME"
  USER="$(id -un)"
  LOGNAME="$(id -un)"
  SHELL="${SHELL:-/bin/zsh}"
  TMPDIR="${TMPDIR:-/tmp}"
  PATH="/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
  CMUX_TAG="$SLUG"
  CMUX_BUNDLE_ID="$BUNDLE_ID"
  CMUX_SOCKET_PATH="/tmp/cmux-debug-$SLUG.sock"
  CMUXD_UNIX_PATH="$HOME/Library/Application Support/cmux/cmuxd-dev-$SLUG.sock"
  CMUX_AUTH_CALLBACK_SCHEME="cmux-dev-$SLUG"
  CMUX_SOCKET_ENABLE=1
  "$EXECUTABLE"
)

plutil -create xml1 "$PLIST"
plutil -insert Label -string "$LABEL" "$PLIST"
plutil -insert ProgramArguments -array "$PLIST"
i=0
for arg in "${ENV_ARGS[@]}"; do
  plutil -insert "ProgramArguments.$i" -string "$arg" "$PLIST"
  i=$((i + 1))
done
plutil -insert RunAtLoad -bool true "$PLIST"
plutil -insert KeepAlive -bool false "$PLIST"
plutil -insert ProcessType -string Interactive "$PLIST"
plutil -insert StandardOutPath -string "$LOG" "$PLIST"
plutil -insert StandardErrorPath -string "$LOG" "$PLIST"

# A previous run's job stays loaded after its app exits; the app is not running
# (checked above), so removing the stale job only clears the label.
launchctl bootout "$DOMAIN/$LABEL" >/dev/null 2>&1 || true
launchctl bootstrap "$DOMAIN" "$PLIST"

pid=""
for _ in $(seq 1 40); do
  pid=$(pgrep -f "$EXECUTABLE" || true)
  [ -n "$pid" ] && break
  sleep 0.5
done
if [ -z "$pid" ]; then
  echo "error: $BUNDLE_ID did not start within 20 s; log: $LOG" >&2
  tail -n 40 "$LOG" >&2 || true
  exit 1
fi
echo "launched $BUNDLE_ID pid $pid"
echo "  socket: /tmp/cmux-debug-$SLUG.sock   log: $LOG"
echo "  after quitting it: launchctl bootout $DOMAIN/$LABEL"
