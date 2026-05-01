#!/usr/bin/env bash
# first-run.sh - capture a Vikunja API token into runtime_dir/.env.
#
# Idempotent. Re-running when the token already looks real is a no-op.
#
# Vikunja has no CLI for managing API tokens, so this is a guided
# paste flow:
#   1. Confirm the stack is up.
#   2. If .env already has a real-looking VIKUNJA_API_TOKEN, exit.
#   3. Open the API Tokens UI in the browser.
#   4. Read the pasted tk_... value from stdin (re-prompt on bad format).
#   5. Write it back into .env in place of the placeholder.
#
# Run after ./bin/bootstrap.sh and after creating an API token in the
# Vikunja UI: Settings -> API Tokens -> Create. Scope to the routes the
# /tal skill needs (projects, tasks, labels - read+write).
#
# Usage:
#   first-run.sh [production|test]    # default: production

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/config.sh"

require_config

instance="${1:-production}"
runtime_dir="$(config_runtime_dir "$instance")"
env_file="${runtime_dir}/.env"
[[ -f "$env_file" ]] || tal_die ".env not found at ${env_file}. Run ./bin/bootstrap.sh ${instance} first."

# Detect backend mode from VIKUNJA_BASE_URL to set the right UI/API endpoints.
_base_url="$(env_get "$runtime_dir" VIKUNJA_BASE_URL)"
_base_url="${_base_url:-http://localhost:3456/api/v1}"
_backend_mode="$(detect_backend_mode "$_base_url")"

case "$_backend_mode" in
  cloud)
    web_base="https://app.vikunja.cloud"
    api_base="${web_base}/api/v1"
    ;;
  local)
    port="$(env_get "$runtime_dir" VIKUNJA_PORT)"
    port="${port:-3456}"
    web_base="http://localhost:${port}"
    api_base="${web_base}/api/v1"
    ;;
  unknown)
    tal_die "Cannot classify VIKUNJA_BASE_URL='${_base_url}'. Supported: localhost / 127.0.0.1 (local) or *.vikunja.cloud (Cloud)."
    ;;
esac

placeholder="create_in_vikunja_ui_after_first_login"
token_re='^tk_[0-9a-f]{40,}$'

current="$(grep '^VIKUNJA_API_TOKEN=' "$env_file" | cut -d= -f2- || true)"
if [[ -n "$current" && "$current" != "$placeholder" && "$current" =~ $token_re ]]; then
  tal_log "VIKUNJA_API_TOKEN already configured (tk_${current:3:6}...). Nothing to do."
  exit 0
fi

tal_log "Confirming Vikunja (${instance}) is reachable on ${web_base}..."
if ! curl -sf "${api_base}/info" >/dev/null 2>&1; then
  case "$_backend_mode" in
    cloud) tal_die "Vikunja Cloud is not responding at ${api_base}. Check your network connection." ;;
    *)     tal_die "Vikunja is not responding. Run ./bin/up.sh ${instance} first." ;;
  esac
fi

tal_log ""
tal_log "Opening the Vikunja API Tokens UI in your browser..."
tal_log "  URL: ${web_base}/user/settings/api-tokens"
tal_log "  Steps to follow there:"
tal_log "    1. Click 'Create token'."
tal_log "    2. Name it: claude-code (or claude-code-test for the test instance)"
tal_log "    3. Scope to the minimum: projects, tasks, labels (read + write)."
tal_log "    4. Copy the tk_... value."
open "${web_base}/user/settings/api-tokens" 2>/dev/null || tal_warn "Could not auto-open browser; visit ${web_base}/user/settings/api-tokens manually."
tal_log ""

token=""
while [[ -z "$token" ]]; do
  read -r -p "Paste the tk_... token (or 'q' to abort): " token
  if [[ "$token" == "q" ]]; then
    tal_die "Aborted. Re-run when you have a token."
  fi
  if ! [[ "$token" =~ $token_re ]]; then
    tal_warn "That doesn't look like a Vikunja API token (expected: tk_<hex>, 40+ chars)."
    token=""
  fi
done

tal_log "Verifying the token against the API..."
if ! curl -sf -H "Authorization: Bearer $token" "${api_base}/projects" >/dev/null 2>&1; then
  tal_die "Token did not authenticate. Re-mint and try again."
fi
tal_log "Token verified OK."

TAL_TOKEN="$token" python3 - "$env_file" <<'PY'
import os, re, sys, pathlib
path = pathlib.Path(sys.argv[1])
text = path.read_text()
new = re.sub(
    r'^VIKUNJA_API_TOKEN=.*$',
    f'VIKUNJA_API_TOKEN={os.environ["TAL_TOKEN"]}',
    text,
    flags=re.MULTILINE,
)
if new == text:
    sys.exit("could not find VIKUNJA_API_TOKEN line in .env to replace")
path.write_text(new)
PY

tal_log ""
tal_log "Token written to ${env_file}."
tal_log ""
tal_log "Next steps:"
tal_log "  - Install the /tal skill: see task-a-llama-skills/README.md."
tal_log "  - Then in any Claude Code session, try:"
tal_log "      'add a todo to vikunja: write the phase 2 retro'"
