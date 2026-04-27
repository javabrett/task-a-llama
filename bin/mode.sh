#!/usr/bin/env bash
# mode.sh - flip the /tal skill between production and test backends.
#
# State lives at ~/.config/task-a-llama/active-mode (one line: "production"
# or "test"). The /tal skill reads this file each turn to pick which
# backend's .env, port, and token to use. Mid-session switching: no Claude
# restart required.
#
# Usage:
#   mode.sh                 # print current mode
#   mode.sh production      # switch to production
#   mode.sh test            # switch to test
#
# Idempotent: writing the current mode again is a no-op.

set -euo pipefail

mode_file="${HOME}/.config/task-a-llama/active-mode"

print_current() {
  if [[ -f "$mode_file" ]]; then
    local current
    current="$(tr -d '[:space:]' < "$mode_file")"
    echo "${current:-production}"
  else
    echo "production"
  fi
}

if [[ $# -eq 0 ]]; then
  print_current
  exit 0
fi

target="$1"
case "$target" in
  production|test) ;;
  -h|--help)
    sed -n '2,15p' "${BASH_SOURCE[0]}"
    exit 0
    ;;
  *)
    echo "error: unknown mode '${target}' (valid: production, test)" >&2
    exit 1
    ;;
esac

mkdir -p "$(dirname "$mode_file")"
echo "$target" > "$mode_file"
echo "Active mode: ${target}"
