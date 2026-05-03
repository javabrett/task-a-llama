#!/usr/bin/env bash
# migrate-to-slugs.sh - one-shot upgrade from the old prod/test layout to slugs.
#
# Idempotent: re-running after a successful migration exits 0 with a message.
#
# What this does:
#   1. Detects ~/vikunja/ and ~/vikunja-test/ (old layout).
#   2. Prompts for the slug name to use for the existing production stack
#      (default: prod).
#   3. Renames ~/vikunja/ to ~/vikunja-<prod-slug>/.
#   4. Splits each .env: extracts VIKUNJA_BASE_URL and VIKUNJA_API_TOKEN
#      into ~/.config/task-a-llama/<slug>/env; removes those lines from
#      ~/vikunja-<slug>/.env.
#   5. Migrates ~/.config/task-a-llama/active-mode to active.
#
# Usage:
#   ./bin/migrate-to-slugs.sh

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/config.sh"

TAL_CONF_DIR="$HOME/.config/task-a-llama"

# ---------------------------------------------------------------------------
# Detect whether already migrated
# ---------------------------------------------------------------------------
if [[ -f "${TAL_CONF_DIR}/active" && ! -f "${TAL_CONF_DIR}/active-mode" && ! -d "${HOME}/vikunja" ]]; then
  tal_log "Already migrated to slug layout."
  current="$(tr -d '[:space:]' < "${TAL_CONF_DIR}/active" 2>/dev/null || echo '(none)')"
  tal_log "Active slug: ${current}"
  exit 0
fi

tal_log "=== task-a-llama: migrate to slug-based layout ==="
tal_log ""

# ---------------------------------------------------------------------------
# Determine prod slug name
# ---------------------------------------------------------------------------
prod_slug=""
if [[ -d "${HOME}/vikunja" ]]; then
  if [[ -t 0 ]]; then
    read -r -p "[task-a-llama] Slug name for existing ~/vikunja/ stack [prod]: " prod_slug
    prod_slug="${prod_slug:-prod}"
  else
    prod_slug="prod"
    tal_log "Non-interactive: using slug name 'prod' for ~/vikunja/"
  fi
  [[ "$prod_slug" =~ ^[a-z0-9][a-z0-9_-]*$ ]] || tal_die "invalid slug: '$prod_slug'"
fi

# ---------------------------------------------------------------------------
# Preview and confirm
# ---------------------------------------------------------------------------
tal_log ""
tal_log "Planned changes:"
[[ -n "$prod_slug" ]] && tal_log "  mv ~/vikunja/ ~/vikunja-${prod_slug}/"
[[ -d "${HOME}/vikunja-test" ]] && tal_log "  ~/vikunja-test/ stays (slug: test)"
[[ -n "$prod_slug" ]] && tal_log "  extract VIKUNJA_BASE_URL + VIKUNJA_API_TOKEN from ~/vikunja-${prod_slug}/.env -> ~/.config/task-a-llama/${prod_slug}/env"
[[ -d "${HOME}/vikunja-test" ]] && tal_log "  extract VIKUNJA_BASE_URL + VIKUNJA_API_TOKEN from ~/vikunja-test/.env -> ~/.config/task-a-llama/test/env"
[[ -f "${TAL_CONF_DIR}/active-mode" ]] && tal_log "  rename active-mode -> active"
tal_log ""

if [[ -t 0 ]]; then
  read -r -p "Proceed? [y/N] " reply
  [[ "$reply" =~ ^[Yy] ]] || tal_die "Aborted."
else
  tal_log "Non-interactive: proceeding."
fi

# ---------------------------------------------------------------------------
# Move ~/vikunja/ -> ~/vikunja-<prod-slug>/
# ---------------------------------------------------------------------------
if [[ -n "$prod_slug" && -d "${HOME}/vikunja" ]]; then
  dest="${HOME}/vikunja-${prod_slug}"
  if [[ -d "$dest" ]]; then
    tal_die "Destination ${dest} already exists. Move or rename it first."
  fi
  mv "${HOME}/vikunja" "$dest"
  tal_log "Moved ~/vikunja/ -> ~/vikunja-${prod_slug}/"
fi

# ---------------------------------------------------------------------------
# Split .env for each slug
# ---------------------------------------------------------------------------
split_env() {
  local slug="$1"
  local runtime_dir="${HOME}/vikunja-${slug}"
  local docker_env="${runtime_dir}/.env"
  local tal_dir="${TAL_CONF_DIR}/${slug}"
  local tal_env="${tal_dir}/env"

  [[ -f "$docker_env" ]] || { tal_log "  no .env found at ${docker_env}; skipping split"; return 0; }

  # Extract the TAL-side vars.
  local base_url token
  base_url="$(grep '^VIKUNJA_BASE_URL=' "$docker_env" 2>/dev/null | head -1 | cut -d= -f2- || true)"
  token="$(grep '^VIKUNJA_API_TOKEN=' "$docker_env" 2>/dev/null | head -1 | cut -d= -f2- || true)"

  mkdir -p "$tal_dir"
  if [[ ! -f "$tal_env" ]]; then
    cat > "$tal_env" <<TALENV
VIKUNJA_BASE_URL=${base_url:-http://localhost:3456/api/v1}
VIKUNJA_API_TOKEN=${token:-create_in_vikunja_ui_after_first_login}
TALENV
    tal_log "  Created ${tal_env}"
  else
    tal_log "  ${tal_env} already exists; leaving as-is"
  fi

  # Remove TAL-side vars from the Docker .env.
  python3 - "$docker_env" <<'PY'
import re, sys, pathlib
path = pathlib.Path(sys.argv[1])
text = path.read_text()
for key in ("VIKUNJA_BASE_URL", "VIKUNJA_API_TOKEN"):
    text = re.sub(r'^' + key + r'=.*\n?', '', text, flags=re.MULTILINE)
path.write_text(text)
PY
  tal_log "  Removed VIKUNJA_BASE_URL and VIKUNJA_API_TOKEN from ${docker_env}"
}

if [[ -n "$prod_slug" && -d "${HOME}/vikunja-${prod_slug}" ]]; then
  tal_log "Splitting .env for slug '${prod_slug}'..."
  split_env "$prod_slug"
fi

if [[ -d "${HOME}/vikunja-test" ]]; then
  tal_log "Splitting .env for slug 'test'..."
  split_env "test"
fi

# ---------------------------------------------------------------------------
# Migrate active-mode -> active
# ---------------------------------------------------------------------------
old_mode_file="${TAL_CONF_DIR}/active-mode"
new_active_file="${TAL_CONF_DIR}/active"

if [[ -f "$old_mode_file" ]]; then
  old_mode="$(tr -d '[:space:]' < "$old_mode_file")"
  if [[ "$old_mode" == "production" || -z "$old_mode" ]]; then
    new_slug="${prod_slug:-prod}"
  else
    new_slug="$old_mode"
  fi
  mkdir -p "$TAL_CONF_DIR"
  echo "$new_slug" > "$new_active_file"
  rm "$old_mode_file"
  tal_log "Migrated active-mode ('${old_mode:-production}') -> active ('${new_slug}')"
elif [[ -n "$prod_slug" && ! -f "$new_active_file" ]]; then
  mkdir -p "$TAL_CONF_DIR"
  echo "$prod_slug" > "$new_active_file"
  tal_log "Created active file with slug '${prod_slug}'"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
tal_log ""
tal_log "Migration complete."
[[ -n "$prod_slug" ]] && tal_log "  Production stack: ~/vikunja-${prod_slug}/"
[[ -d "${HOME}/vikunja-test" ]] && tal_log "  Test stack: ~/vikunja-test/"
tal_log "  Active slug: $(cat "${new_active_file:-${TAL_CONF_DIR}/active}" 2>/dev/null || echo '?')"
tal_log ""
tal_log "Next: verify everything is working with:"
[[ -n "$prod_slug" ]] && tal_log "  bin/up.sh ${prod_slug}"
tal_log "  bin/mode.sh"
