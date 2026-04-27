#!/usr/bin/env bash
# config.sh - shared helpers for bin/ scripts.
#
# Sourced (not executed) by lifecycle, bootstrap, backup, and restore scripts.
# Provides:
#   - TAL_ROOT, TAL_CONFIG, TAL_ENV paths resolved from BASH_SOURCE
#   - require_cmd <bin> [install hint] - fail fast if a prereq is missing
#   - config_get <yq-path> - read a value from config.yml
#   - path_expand <path> - expand leading ~ without invoking eval
#   - config_runtime_dir, config_backup_binary_dir, config_sql_dump_target, ...
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

# Convenience accessors with ~ expansion and required-field checks.
config_runtime_dir() {
  local v
  v="$(config_get '.runtime_dir')"
  [[ -n "$v" ]] || tal_die "config.yml: runtime_dir is required"
  path_expand "$v"
}

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
