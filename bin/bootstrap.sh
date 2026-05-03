#!/usr/bin/env bash
# bootstrap.sh - first-run setup for a task-a-llama environment slug.
#
# Idempotent. Safe to re-run; each step is a no-op when already complete.
#
# Usage:
#   bootstrap.sh [<slug>] [flags]         # default: active slug
#   bootstrap.sh --cloud [<slug>]         # Vikunja Cloud slug (no Docker)
#
# Flags:
#   --cloud    Set up a Vikunja Cloud slug. Creates the TAL env file with
#              the Cloud API URL pre-filled. No Docker required. After
#              running, capture your token with: ./bin/first-run.sh <slug>
#   --up       Bring the local stack up after bootstrap (local slugs only).
#   --no-up    Skip the "bring stack up?" prompt.
#
# What this does (local slugs):
#   1. Validates required commands are installed (docker, yq, sqlite3, openssl)
#   2. Seeds config.yml from config.example.yml if missing (then asks the user
#      to edit and re-run)
#   3. Creates ~/vikunja-<slug>/{db,files} for the given slug
#   4. Symlinks docker-compose.yml into ~/vikunja-<slug>/
#   5. Seeds ~/vikunja-<slug>/.env from .env.example if missing (Docker-side
#      vars only: JWT secret, port, container names, TZ)
#   6. Creates ~/.config/task-a-llama/<slug>/env if missing (TAL-side vars:
#      VIKUNJA_BASE_URL, VIKUNJA_API_TOKEN placeholder)
#   7. Reports status of companion repo paths (informational only)
#   8. Optionally brings the stack up (use --up to skip the interactive prompt)

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/config.sh"

slug=""
auto_up=0
cloud_mode=0
for arg in "$@"; do
  case "$arg" in
    --cloud) cloud_mode=1 ;;
    --up) auto_up=1 ;;
    --no-up) auto_up=-1 ;;
    -h|--help)
      sed -n '2,30p' "${BASH_SOURCE[0]}"
      exit 0
      ;;
    -*) tal_die "unknown argument: $arg" ;;
    *)  slug="$arg" ;;
  esac
done

# Cloud slug path: no Docker, no local runtime. Just the TAL env file.
if [[ "$cloud_mode" == "1" ]]; then
  slug="$(config_resolve_slug "$slug")"
  cloud_url="https://app.vikunja.cloud/api/v1"
  tal_env_dir="$HOME/.config/task-a-llama/${slug}"
  tal_env_file="${tal_env_dir}/env"

  if [[ -f "$tal_env_file" ]]; then
    existing_url="$(grep '^VIKUNJA_BASE_URL=' "$tal_env_file" | cut -d= -f2-)"
    if [[ "$existing_url" == *"vikunja.cloud"* ]]; then
      tal_log "Cloud TAL env already exists at ${tal_env_file}, leaving as-is."
    else
      tal_die "TAL env at ${tal_env_file} already exists with a non-Cloud URL (${existing_url}). Remove it and re-run to reconfigure."
    fi
  else
    mkdir -p "$tal_env_dir"
    printf 'VIKUNJA_BASE_URL=%s\nVIKUNJA_API_TOKEN=create_in_vikunja_ui_after_first_login\n' \
      "$cloud_url" > "$tal_env_file"
    tal_log "Created Cloud TAL env at ${tal_env_file}"
  fi

  active_file="$HOME/.config/task-a-llama/active"
  if [[ ! -f "$active_file" ]]; then
    echo "$slug" > "$active_file"
    tal_log "Set active slug to '${slug}'."
  else
    current_active="$(tr -d '[:space:]' < "$active_file")"
    if [[ "$current_active" != "$slug" ]]; then
      tal_log "Active slug unchanged ('${current_active}'). Run ./bin/mode.sh ${slug} to switch."
    fi
  fi

  tal_log ""
  tal_log "Cloud slug '${slug}' ready."
  tal_log "Next step: ./bin/first-run.sh ${slug}"
  exit 0
fi

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
  tal_log "Edit $TAL_CONFIG to match your setup (source paths, backup config),"
  tal_log "then re-run ./bin/bootstrap.sh"
  exit 0
fi

slug="$(config_resolve_slug "$slug")"
tal_log "slug: ${slug}"
require_local_backend "$slug"
runtime_dir="$(config_runtime_dir "$slug")"
tal_log "runtime_dir: ${runtime_dir}"
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

# Assign a port for this slug.
# prod -> 3456 (historical default), test -> 4567, others -> prompt.
case "$slug" in
  prod) slug_port=3456 ;;
  test) slug_port=4567 ;;
  *)
    if [[ -t 0 ]]; then
      read -r -p "[task-a-llama] Port for slug '${slug}' [3000-9999]: " slug_port
    else
      tal_die "non-interactive bootstrap for slug '${slug}' requires an explicit port. Re-run from a TTY."
    fi
    ;;
esac

# Seed Docker-side .env if missing.
env_file="${runtime_dir}/.env"
fresh_env=0
if [[ ! -f "$env_file" ]]; then
  fresh_env=1
  tal_log "Creating ${env_file} from .env.example"
  cp "$TAL_ENV_EXAMPLE" "$env_file"

  # Generate a JWT secret and replace the placeholder in-place.
  jwt_secret="$(openssl rand -base64 32)"
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

  # Detect host timezone and populate TZ + VIKUNJA_SERVICE_TIMEZONE.
  detected_tz="$(readlink /etc/localtime 2>/dev/null | sed 's|.*/zoneinfo/||')"
  [[ -z "$detected_tz" ]] && detected_tz="UTC"
  TAL_TZ="$detected_tz" python3 - "$env_file" <<'PY'
import re, os, sys, pathlib
path = pathlib.Path(sys.argv[1])
tz = os.environ["TAL_TZ"]
text = path.read_text()
for key in ("TZ", "VIKUNJA_SERVICE_TIMEZONE"):
    text = re.sub(r'^' + key + r'=$', key + '=' + tz, text, flags=re.MULTILINE)
path.write_text(text)
PY
  tal_log "Set TZ and VIKUNJA_SERVICE_TIMEZONE to ${detected_tz} in ${env_file}"

  # Rewrite slug-specific Docker vars (port, container names, public URL).
  TAL_SLUG_NAME="$slug" TAL_PORT="$slug_port" python3 - "$env_file" <<'PY'
import re, os, sys, pathlib
slug = os.environ["TAL_SLUG_NAME"]
port = os.environ["TAL_PORT"]
path = pathlib.Path(sys.argv[1])
text = path.read_text()
replacements = {
    r'^VIKUNJA_SERVICE_PUBLICURL=.*$': f'VIKUNJA_SERVICE_PUBLICURL=http://localhost:{port}/',
    r'^VIKUNJA_PORT=.*$':              f'VIKUNJA_PORT={port}',
    r'^VIKUNJA_CONTAINER_NAME=.*$':    f'VIKUNJA_CONTAINER_NAME=vikunja-{slug}',
}
for pattern, replacement in replacements.items():
    text = re.sub(pattern, replacement, text, flags=re.MULTILINE)
path.write_text(text)
PY
  tal_log "Configured Docker .env for slug '${slug}' (port ${slug_port})"

  tal_log ""
  tal_log "Review ${env_file} and confirm:"
  tal_log "  - TZ and VIKUNJA_SERVICE_TIMEZONE are correct (currently: $(grep '^TZ=' "$env_file" | cut -d= -f2-))"
else
  tal_log "Docker .env already exists at ${env_file}, leaving as-is"
fi

# Seed TAL-side env file if missing.
tal_env_dir="$HOME/.config/task-a-llama/${slug}"
tal_env_file="${tal_env_dir}/env"
if [[ ! -f "$tal_env_file" ]]; then
  mkdir -p "$tal_env_dir"
  cat > "$tal_env_file" <<TALENV
VIKUNJA_BASE_URL=http://localhost:${slug_port}/api/v1
VIKUNJA_API_TOKEN=create_in_vikunja_ui_after_first_login
TALENV
  tal_log "Created TAL env at ${tal_env_file}"
  tal_log "  - Run ./bin/first-run.sh ${slug} to capture the API token"
else
  tal_log "TAL env already exists at ${tal_env_file}, leaving as-is"
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

# Set the active slug if none is set yet; otherwise leave it alone.
active_file="$HOME/.config/task-a-llama/active"
if [[ ! -f "$active_file" ]]; then
  echo "$slug" > "$active_file"
  tal_log "Set active slug to '${slug}'."
else
  current_active="$(tr -d '[:space:]' < "$active_file")"
  if [[ "$current_active" != "$slug" ]]; then
    tal_log "Active slug unchanged ('${current_active}'). Run ./bin/mode.sh ${slug} to switch."
  fi
fi

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

  # Resolve slug-specific URL/container values for the up + ready check.
  port="$(grep '^VIKUNJA_PORT=' "$env_file" | cut -d= -f2-)"
  port="${port:-${slug_port}}"
  web_base="http://localhost:${port}"
  api_base="${web_base}/api/v1"
  container_name="$(grep '^VIKUNJA_CONTAINER_NAME=' "$env_file" | cut -d= -f2-)"
  container_name="${container_name:-vikunja-${slug}}"

  if [[ "$fresh_env" == "1" ]]; then
    # First-run: create the initial account via the Vikunja CLI running inside
    # the container. This bypasses VIKUNJA_SERVICE_ENABLEREGISTRATION entirely --
    # registration stays disabled throughout; no toggle required.
    "$bin_dir/up.sh" "$slug"

    tal_log ""
    tal_log "Waiting for Vikunja (${slug}) to be ready..."
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
      tal_log "  Slug:     ${slug}"
      tal_log "  URL:      ${web_base}"
      tal_log "  Username: ${init_user}"
      tal_log "  Password: ${init_pass}"
      tal_log "================================================================"
    else
      tal_warn "User creation via CLI failed - an account may already exist."
      tal_warn "Log in at ${web_base} with your existing credentials."
    fi
  else
    exec "$bin_dir/up.sh" "$slug"
  fi
fi
