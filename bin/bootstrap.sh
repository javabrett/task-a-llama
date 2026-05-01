#!/usr/bin/env bash
# bootstrap.sh - first-run setup for task-a-llama.
#
# Idempotent. Safe to re-run; each step is a no-op when already complete.
#
# Usage:
#   bootstrap.sh [production|test] [flags]    # default: production
#
# What this does:
#   1. Validates required commands are installed (docker, yq, sqlite3, openssl)
#   2. Seeds config.yml from config.example.yml if missing (then asks the user to edit and re-run)
#   3. Creates runtime_dir/{db,files} for the given instance
#   4. Symlinks docker-compose.yml into runtime_dir
#   5. Seeds runtime_dir/.env from .env.example if missing (and generates a JWT secret)
#   6. For test instance: rewrites port/container-name overrides to localhost:4567
#   7. Reports status of companion repo paths (informational only - bootstrap never clones)
#   8. Optionally brings the stack up (use --up to skip the interactive prompt)

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/config.sh"

instance="production"
auto_up=0
for arg in "$@"; do
  case "$arg" in
    production|test) instance="$arg" ;;
    --up) auto_up=1 ;;
    --no-up) auto_up=-1 ;;
    -h|--help)
      sed -n '2,18p' "${BASH_SOURCE[0]}"
      exit 0
      ;;
    *) tal_die "unknown argument: $arg" ;;
  esac
done

tal_log "Validating prerequisites..."
require_cmd docker "install Docker Desktop, OrbStack, or Colima"
require_cmd yq "brew install yq"
require_cmd sqlite3 "ships with macOS; or brew install sqlite"
require_cmd openssl "ships with macOS"
docker compose version >/dev/null 2>&1 || tal_die "'docker compose' subcommand not available. Install Docker Desktop v2+ or the compose plugin."

if [[ ! -f "$TAL_CONFIG" ]]; then
  tal_log "config.yml not found - copying from config.example.yml"
  cp "$TAL_CONFIG_EXAMPLE" "$TAL_CONFIG"
  tal_log ""
  tal_log "Edit $TAL_CONFIG to match your setup (runtime_dir, source paths, timezone),"
  tal_log "then re-run ./bin/bootstrap.sh"
  exit 0
fi

runtime_dir="$(config_runtime_dir "$instance")"
tal_log "runtime_dir resolved to ${runtime_dir} (instance: ${instance})"
require_local_backend "$instance"
mkdir -p "${runtime_dir}/db" "${runtime_dir}/files"

# Symlink docker-compose.yml into runtime_dir.
# ln -sf is idempotent: it replaces any existing symlink at the target.
if [[ -f "${runtime_dir}/docker-compose.yml" && ! -L "${runtime_dir}/docker-compose.yml" ]]; then
  tal_err "${runtime_dir}/docker-compose.yml exists and is a regular file, not a symlink."
  tal_err "If you have local edits, back them up; otherwise remove it and re-run bootstrap."
  exit 1
fi
ln -sf "$TAL_COMPOSE" "${runtime_dir}/docker-compose.yml"
tal_log "Symlinked docker-compose.yml into runtime_dir"

# Seed .env if missing.
env_file="${runtime_dir}/.env"
fresh_env=0
if [[ ! -f "$env_file" ]]; then
  fresh_env=1
  tal_log "Creating ${env_file} from .env.example"
  cp "$TAL_ENV_EXAMPLE" "$env_file"
  # Generate a JWT secret and replace the placeholder in-place.
  jwt_secret="$(openssl rand -base64 32)"
  # Use a Python one-liner for safe in-place replacement without sed escaping pitfalls.
  TAL_JWT="$jwt_secret" python3 - "$env_file" <<'PY'
import os, sys, pathlib
path = pathlib.Path(sys.argv[1])
placeholder = "generate_with_openssl_rand_base64_32"
text = path.read_text()
if placeholder in text:
    text = text.replace(placeholder, os.environ["TAL_JWT"])
    path.write_text(text)
PY
  tal_log "Generated VIKUNJA_JWT_SECRET in ${env_file}"

  # For the test instance, rewrite production defaults to test-specific values.
  if [[ "$instance" == "test" ]]; then
    TAL_INSTANCE="test" python3 - "$env_file" <<'PY'
import re, sys, pathlib
path = pathlib.Path(sys.argv[1])
text = path.read_text()

replacements = {
    r'^VIKUNJA_SERVICE_PUBLICURL=.*$': 'VIKUNJA_SERVICE_PUBLICURL=http://localhost:4567/',
    r'^VIKUNJA_PORT=.*$':              'VIKUNJA_PORT=4567',
    r'^VIKUNJA_CONTAINER_NAME=.*$':    'VIKUNJA_CONTAINER_NAME=vikunja-test',
    r'^VIKUNJA_WATCHTOWER_NAME=.*$':   'VIKUNJA_WATCHTOWER_NAME=task-a-llama-watchtower-test',
    r'^VIKUNJA_BASE_URL=.*$':          'VIKUNJA_BASE_URL=http://localhost:4567/api/v1',
}
for pattern, replacement in replacements.items():
    text = re.sub(pattern, replacement, text, flags=re.MULTILINE)
path.write_text(text)
PY
    tal_log "Rewrote test-instance overrides in ${env_file} (port 4567, container vikunja-test)"
  fi

  tal_log ""
  tal_log "Review ${env_file} and confirm:"
  tal_log "  - TZ is correct (currently: $(grep '^TZ=' "$env_file" | cut -d= -f2-))"
  tal_log "  - VIKUNJA_API_TOKEN left as placeholder; run ./bin/first-run.sh ${instance} to capture it"
else
  tal_log ".env already exists at ${env_file}, leaving as-is"
fi

# Report companion repo paths. Bootstrap never clones or creates these --
# how they got there (git clone, stow, manual) is not our concern.
# backup.sh checks git capability at backup time when it actually matters.
tal_log ""
tal_log "Companion repos:"
for label_path in \
  "public skills:$(config_public_skills_local)" \
  "private skills:$(config_private_skills_path)" \
  "data repo:$(config_data_repo_local)"; do
  label="${label_path%%:*}"
  path="${label_path#*:}"
  if [[ -z "$path" ]]; then
    tal_log "  ${label}: not configured"
  elif [[ -d "$path" ]]; then
    tal_log "  ${label}: present (${path})"
  else
    tal_warn "${label}: not found at ${path}"
  fi
done

tal_log ""
tal_log "Bootstrap complete."
tal_log "Runtime: ${runtime_dir}"

# Decide whether to bring the stack up.
if [[ "$auto_up" == "1" ]]; then
  do_up=1
elif [[ "$auto_up" == "-1" ]]; then
  do_up=0
else
  if [[ -t 0 ]]; then
    read -r -p "Bring the Vikunja stack up now? [Y/n] " reply
    reply="${reply:-Y}"
    [[ "$reply" =~ ^[Yy] ]] && do_up=1 || do_up=0
  else
    tal_log "Non-interactive; skipping 'up'. Run ./bin/up.sh when ready."
    do_up=0
  fi
fi

if [[ "$do_up" == "1" ]]; then
  bin_dir="$(dirname "${BASH_SOURCE[0]}")"

  # Resolve instance-specific URL/container values for the up + ready check.
  port="$(grep '^VIKUNJA_PORT=' "$env_file" | cut -d= -f2-)"
  port="${port:-3456}"
  web_base="http://localhost:${port}"
  api_base="${web_base}/api/v1"
  container_name="$(grep '^VIKUNJA_CONTAINER_NAME=' "$env_file" | cut -d= -f2-)"
  container_name="${container_name:-vikunja}"

  if [[ "$fresh_env" == "1" ]]; then
    # First-run: create the initial account via the Vikunja CLI running inside
    # the container. This bypasses VIKUNJA_SERVICE_ENABLEREGISTRATION entirely --
    # registration stays disabled throughout; no toggle required.
    "$bin_dir/up.sh" "$instance"

    tal_log ""
    tal_log "Waiting for Vikunja (${instance}) to be ready..."
    ready=0
    for i in $(seq 1 30); do
      if curl -sf "${api_base}/info" >/dev/null 2>&1; then
        ready=1
        break
      fi
      sleep 1
    done
    if [[ "$ready" == "0" ]]; then
      tal_die "Vikunja did not become ready within 30 seconds. Check: docker logs ${container_name}"
    fi

    init_user="admin"
    init_email="admin@example.com"
    init_pass="$(openssl rand -base64 18)"

    tal_log "Creating initial account..."
    if docker exec "$container_name" /app/vikunja/vikunja user create \
        --username "$init_user" \
        --email    "$init_email" \
        --password "$init_pass" 2>&1; then
      tal_log ""
      tal_log "================================================================"
      tal_log "  Initial account created - save these in your password manager"
      tal_log "  URL:      ${web_base}"
      tal_log "  Username: ${init_user}"
      tal_log "  Password: ${init_pass}"
      tal_log "================================================================"
    else
      tal_warn "User creation via CLI failed - an account may already exist."
      tal_warn "Log in at ${web_base} with your existing credentials."
    fi
  else
    exec "$bin_dir/up.sh" "$instance"
  fi
fi
