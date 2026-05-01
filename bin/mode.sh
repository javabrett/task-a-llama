#!/usr/bin/env bash
# mode.sh - set or read the active task-a-llama environment slug.
#
# State lives at ~/.config/task-a-llama/active (one line: the slug name).
# The /tal skill reads this file on each turn to select the right
# backend URL and API token. Mid-session switching: no Claude restart needed.
#
# Usage:
#   mode.sh               # print active slug
#   mode.sh <slug>        # switch to the named slug (must have a TAL env file)

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/config.sh"

active_file="${HOME}/.config/task-a-llama/active"

print_current() {
  if [[ -f "$active_file" ]]; then
    local current
    current="$(tr -d '[:space:]' < "$active_file")"
    if [[ -n "$current" ]]; then
      echo "$current"
    else
      echo "(no active slug)"
    fi
  else
    echo "(no active slug)"
  fi
}

if [[ $# -eq 0 ]]; then
  print_current
  exit 0
fi

case "$1" in
  -h|--help)
    sed -n '2,9p' "${BASH_SOURCE[0]}"
    exit 0
    ;;
esac

slug="$(config_resolve_slug "$1")"

tal_env_file="$(config_slug_env "$slug")"
[[ -f "$tal_env_file" ]] || tal_die "no env file for slug '${slug}' at ${tal_env_file}. Run ./bin/bootstrap.sh ${slug} first."

# Verify the target is reachable before committing the switch.
_base_url="$(slug_get "$slug" VIKUNJA_BASE_URL)"
_base_url="${_base_url:-http://localhost:3456/api/v1}"
_web_base="${_base_url%/api/v1}"

tal_log "Checking ${_web_base}..."
if ! curl -sf "${_base_url}/info" >/dev/null 2>&1; then
  case "$(detect_backend_mode "$_base_url")" in
    cloud)   tal_die "Vikunja Cloud is not responding at ${_web_base}. Check your network connection, then retry." ;;
    *)       tal_die "Stack is not running at ${_web_base}. Start it with bin/up.sh ${slug}, then retry." ;;
  esac
fi

mkdir -p "$(dirname "$active_file")"
echo "$slug" > "$active_file"
echo "[task-a-llama] Active slug: ${slug} (${_web_base})"
