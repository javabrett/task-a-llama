#!/usr/bin/env bash
# up.sh - bring the Vikunja stack up.
#
# Thin wrapper around `docker compose up -d`, rooted at runtime_dir
# so .env and bind mounts resolve correctly.
#
# Usage:
#   up.sh [production|test]    # default: production

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/config.sh"
require_config
require_cmd docker

instance="${1:-production}"
require_local_backend "$instance"
runtime_dir="$(config_runtime_dir "$instance")"
[[ -d "$runtime_dir" ]] || tal_die "runtime_dir does not exist: ${runtime_dir}. Run ./bin/bootstrap.sh ${instance} first."
[[ -f "${runtime_dir}/docker-compose.yml" ]] || tal_die "docker-compose.yml not found in ${runtime_dir}. Run ./bin/bootstrap.sh ${instance} first."
[[ -f "${runtime_dir}/.env" ]] || tal_die ".env not found in ${runtime_dir}. Run ./bin/bootstrap.sh ${instance} first."

# Resolve port from .env for the user-facing message
port="$(grep '^VIKUNJA_PORT=' "${runtime_dir}/.env" | cut -d= -f2- || true)"
port="${port:-3456}"

tal_log "Starting Vikunja stack (${instance}) in ${runtime_dir}"
cd "$runtime_dir"
docker compose up -d
tal_log "Open http://localhost:${port}"
