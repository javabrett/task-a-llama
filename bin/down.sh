#!/usr/bin/env bash
# down.sh - stop the Vikunja stack without removing data.
#
# Usage:
#   down.sh [production|test]    # default: production

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/config.sh"
require_config
require_cmd docker

instance="${1:-production}"
require_local_backend "$instance"
runtime_dir="$(config_runtime_dir "$instance")"
[[ -d "$runtime_dir" ]] || tal_die "runtime_dir does not exist: ${runtime_dir}"

tal_log "Stopping Vikunja stack (${instance}) in ${runtime_dir}"
cd "$runtime_dir"
docker compose down
