#!/usr/bin/env bash
# up.sh - bring the Vikunja stack up.
#
# Thin wrapper around `docker compose up -d`, rooted at runtime_dir
# so .env and bind mounts resolve correctly.

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/config.sh"
require_config
require_cmd docker

runtime_dir="$(config_runtime_dir)"
[[ -d "$runtime_dir" ]] || tal_die "runtime_dir does not exist: ${runtime_dir}. Run ./bin/bootstrap.sh first."
[[ -f "${runtime_dir}/docker-compose.yml" ]] || tal_die "docker-compose.yml not found in ${runtime_dir}. Run ./bin/bootstrap.sh first."
[[ -f "${runtime_dir}/.env" ]] || tal_die ".env not found in ${runtime_dir}. Run ./bin/bootstrap.sh first."

tal_log "Starting Vikunja stack in ${runtime_dir}"
cd "$runtime_dir"
docker compose up -d
tal_log "Open http://localhost:3456"
