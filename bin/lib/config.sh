#!/usr/bin/env bash
# config.sh - shared helpers for bin/ scripts.
#
# Sourced (not executed) by lifecycle, bootstrap, backup, and restore scripts.
# Provides:
#   - TAL_ROOT, TAL_CONFIG, TAL_ENV paths resolved from BASH_SOURCE
#   - require_cmd <bin> [install hint] - fail fast if a prereq is missing
#   - config_get <yq-path> - read a value from config.yml
#   - path_expand <path> - expand leading ~ without invoking eval
#   - Slug helpers: config_active_slug, config_resolve_slug, config_slug_env,
#                   config_slug_overlay, config_runtime_dir, slug_get
#   - env_get <runtime_dir> <var> - read a Docker-side .env variable
#   - detect_backend_mode, require_local_backend
#   - config_backup_binary_dir, config_sql_dump_target, ...
#
# Callers should: set -euo pipefail; source "<framework>/bin/lib/config.sh"

# shellcheck shell=bash

# Resolve the framework repo root from this file's location
# (bin/lib/config.sh -> bin/lib -> bin -> repo root).
__tal_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TAL_ROOT="$(cd "${__tal_lib_dir}/../.." && pwd)"
TAL_CONFIG="${TAL_ROOT}/config.yml"
TAL_CONFIG_EXAMPLE="${TAL_ROOT}/config.example.yml"
TAL_ENV_EXAMPLE="${TAL_ROOT}/.env.example"
TAL_COMPOSE="${TAL_ROOT}/docker-compose.yml"
export TAL_ROOT TAL_CONFIG TAL_CONFIG_EXAMPLE TAL_ENV_EXAMPLE TAL_COMPOSE

tal_log() {
  printf '[task-a-llama] %s\n' "$*"
}

tal_warn() {
  printf '[task-a-llama] warn: %s\n' "$*" >&2
}

tal_err() {
  printf '[task-a-llama] error: %s\n' "$*" >&2
}

tal_die() {
  tal_err "$*"
  exit 1
}

# require_cmd <command> [install-hint]
# Fails with a clear message if the command is not on PATH.
require_cmd() {
  local cmd="$1"
  local hint="${2:-}"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    if [[ -n "$hint" ]]; then
      tal_die "required command not found: ${cmd}. Try: ${hint}"
    else
      tal_die "required command not found: ${cmd}"
    fi
  fi
}

# Ensure config.yml exists. Most scripts need it; bootstrap will create it.
require_config() {
  if [[ ! -f "$TAL_CONFIG" ]]; then
    tal_die "config.yml not found at ${TAL_CONFIG}. Copy config.example.yml to config.yml and edit it, or run ./bin/bootstrap.sh."
  fi
  require_cmd yq "brew install yq"
}

# Read a single value from config.yml by yq path (e.g. '.runtime_dir').
# Trims a trailing newline. Returns empty string for null/missing keys.
config_get() {
  local path="$1"
  local value
  value="$(yq eval "$path" "$TAL_CONFIG")"
  if [[ "$value" == "null" ]]; then
    echo ""
  else
    echo "$value"
  fi
}

# Expand a leading ~ or ~/ in a path without invoking eval.
# Non-tilde paths pass through unchanged.
path_expand() {
  local p="$1"
  if [[ "$p" == "~" ]]; then
    echo "$HOME"
  elif [[ "$p" == "~/"* ]]; then
    echo "$HOME/${p:2}"
  else
    echo "$p"
  fi
}

# ---------------------------------------------------------------------------
# Slug helpers
# ---------------------------------------------------------------------------

# Read the active slug from ~/.config/task-a-llama/active.
# Falls back to $TAL_SLUG env var. Errors if neither is set.
config_active_slug() {
  if [[ -n "${TAL_SLUG:-}" ]]; then
    echo "$TAL_SLUG"; return 0
  fi
  local f="$HOME/.config/task-a-llama/active"
  [[ -f "$f" ]] || tal_die "no active environment selected; run bin/mode.sh <slug> or pass a slug argument"
  local slug
  slug="$(tr -d '[:space:]' < "$f")"
  [[ -n "$slug" ]] || tal_die "active file is empty: $f"
  echo "$slug"
}

# Resolve a slug arg (or active slug if arg is empty). Validates slug shape.
config_resolve_slug() {
  local slug="${1:-}"
  [[ -z "$slug" ]] && slug="$(config_active_slug)"
  [[ "$slug" =~ ^[a-z0-9][a-z0-9_-]*$ ]] || tal_die "invalid slug: '$slug' (expected [a-z0-9][a-z0-9_-]*)"
  echo "$slug"
}

# Path to the TAL-side env file (URL + token) for a slug.
config_slug_env() {
  echo "$HOME/.config/task-a-llama/$1/env"
}

# Path to the per-slug overlay file (may not exist; caller checks).
config_slug_overlay() {
  echo "$HOME/.config/task-a-llama/$1/overlay.yml"
}

# Path to the local Docker runtime dir for a slug.
# Always returns the path; caller is responsible for not using when cloud.
config_runtime_dir() {
  echo "$HOME/vikunja-$1"
}

# Read a variable from a slug's TAL-side env file.
# Returns empty string if the file or variable is absent.
slug_get() {
  local slug="$1" var="$2"
  local f
  f="$(config_slug_env "$slug")"
  [[ -f "$f" ]] || return 0
  grep "^${var}=" "$f" 2>/dev/null \
    | head -1 \
    | cut -d= -f2- \
    | sed -e 's/^"//' -e "s/^'//" -e 's/"$//' -e "s/'$//"
}

# ---------------------------------------------------------------------------
# Convenience accessors for config.yml fields (backup, sources)
# ---------------------------------------------------------------------------

config_backup_binary_dir() {
  local v
  v="$(config_get '.backup.binary_dir')"
  [[ -n "$v" ]] || tal_die "config.yml: backup.binary_dir is required"
  path_expand "$v"
}

config_sql_dump_target() {
  local v
  v="$(config_get '.backup.sql_dump_target')"
  [[ -n "$v" ]] || tal_die "config.yml: backup.sql_dump_target is required"
  path_expand "$v"
}

config_retention_days() {
  local v
  v="$(config_get '.backup.retention_days')"
  echo "${v:-7}"
}

config_public_skills_repo() {
  config_get '.sources.public_skills.repo'
}

config_public_skills_local() {
  local v
  v="$(config_get '.sources.public_skills.local')"
  [[ -n "$v" ]] && path_expand "$v" || echo ""
}

config_private_skills_path() {
  local v
  v="$(config_get '.sources.private_skills.path')"
  [[ -n "$v" ]] && path_expand "$v" || echo ""
}

config_data_repo_local() {
  local v
  v="$(config_get '.sources.data.local')"
  [[ -n "$v" ]] && path_expand "$v" || echo ""
}

# env_get <runtime_dir> <var>
# Read one VAR=value line from a runtime instance's .env file.
# Strips surrounding single/double quotes. Returns empty string if the
# file is absent or the variable is not present.
env_get() {
  local runtime_dir="$1" var="$2"
  local env_file="${runtime_dir}/.env"
  [ -f "$env_file" ] || return 0
  grep "^${var}=" "$env_file" 2>/dev/null \
    | head -1 \
    | cut -d= -f2- \
    | sed -e 's/^"//' -e "s/^'//" -e 's/"$//' -e "s/'$//"
}

# detect_backend_mode <url>
# Classify a VIKUNJA_BASE_URL value by hostname.
# Echoes one of: local | cloud | unknown
detect_backend_mode() {
  local url="$1"
  case "$url" in
    *vikunja.cloud*)          echo cloud ;;
    *://localhost[:/]*|*://127.0.0.1[:/]*) echo local ;;
    *)                        echo unknown ;;
  esac
}

# require_local_backend [slug]
# Fail-fast guard for scripts that only make sense against a locally-hosted
# stack. Reads VIKUNJA_BASE_URL from the slug's TAL-side env file; if backend
# is cloud or unknown, prints a tailored message and exits 1.
# If the env file is absent (e.g. first-ever bootstrap), the URL defaults to
# localhost and the check passes - preserving the bootstrap chicken-and-egg.
require_local_backend() {
  local slug
  slug="$(config_resolve_slug "${1:-}")"
  local url
  url="$(slug_get "$slug" VIKUNJA_BASE_URL)"
  url="${url:-http://localhost:3456/api/v1}"
  case "$(detect_backend_mode "$url")" in
    local)   return 0 ;;
    cloud)
      tal_die "$(basename "$0") is a local-stack operation; slug '${slug}' targets Vikunja Cloud (${url}). Cloud lifecycle is managed by the provider."
      ;;
    unknown)
      tal_die "$(basename "$0") cannot classify VIKUNJA_BASE_URL='${url}' for slug '${slug}'. Supported: localhost / 127.0.0.1 (local) or *.vikunja.cloud (Cloud). LAN/WAN hosts are not yet supported."
      ;;
  esac
}
