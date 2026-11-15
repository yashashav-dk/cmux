#!/usr/bin/env bash
# Link the local pre-push hook to the scanner kept outside the repository.
set -euo pipefail
src="$HOME/.config/cmux-fork/hooks/prepush-scan.sh"
if [ ! -f "$src" ]; then
  echo "missing $src" >&2
  exit 1
fi
hooks_dir=$(git rev-parse --git-path hooks)
mkdir -p "$hooks_dir"
ln -sf "$src" "$hooks_dir/pre-push"
echo "installed $hooks_dir/pre-push -> $src"
