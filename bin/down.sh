#!/usr/bin/env bash
# down.sh - stop the Vikunja stack without removing data.

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/config.sh"
require_config
require_cmd docker

runtime_dir="$(config_runtime_dir)"
[[ -d "$runtime_dir" ]] || tal_die "runtime_dir does not exist: ${runtime_dir}"

tal_log "Stopping Vikunja stack in ${runtime_dir}"
cd "$runtime_dir"
docker compose down
