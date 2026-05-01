#!/usr/bin/env bash
# down.sh - stop the Vikunja stack without removing data.
#
# Usage:
#   down.sh [<slug>]    # default: active slug

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/config.sh"
require_cmd docker

slug="$(config_resolve_slug "${1:-}")"
require_local_backend "$slug"
runtime_dir="$(config_runtime_dir "$slug")"
[[ -d "$runtime_dir" ]] || tal_die "runtime_dir does not exist: ${runtime_dir}"

tal_log "Stopping Vikunja stack (${slug}) in ${runtime_dir}"
cd "$runtime_dir"
docker compose down
