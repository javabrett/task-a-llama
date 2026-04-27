#!/usr/bin/env bash
# nuke.sh - destroy containers AND bind-mounted data in runtime_dir.
#
# This is destructive and irreversible. Binary/SQL backups OUTSIDE runtime_dir
# are never touched by this script.
#
# Flags:
#   --keep-env       Leave runtime_dir/.env alone (default: removed)
#   --keep-compose   Leave runtime_dir/docker-compose.yml symlink alone (default: removed)
#   --yes            Skip the typed confirmation (use only from known-safe automation)

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/config.sh"
require_config
require_cmd docker

keep_env=0
keep_compose=0
skip_prompt=0
for arg in "$@"; do
  case "$arg" in
    --keep-env) keep_env=1 ;;
    --keep-compose) keep_compose=1 ;;
    --yes) skip_prompt=1 ;;
    -h|--help)
      sed -n '2,12p' "${BASH_SOURCE[0]}"
      exit 0
      ;;
    *) tal_die "unknown argument: $arg" ;;
  esac
done

runtime_dir="$(config_runtime_dir)"
[[ -d "$runtime_dir" ]] || tal_die "runtime_dir does not exist: ${runtime_dir}"

tal_log ""
tal_log "This will PERMANENTLY destroy:"
tal_log "  - docker compose containers + volumes for the stack"
tal_log "  - ${runtime_dir}/db/ (the SQLite database)"
tal_log "  - ${runtime_dir}/files/ (attachments)"
[[ "$keep_env" == "0" ]] && tal_log "  - ${runtime_dir}/.env (secrets)"
[[ "$keep_compose" == "0" ]] && tal_log "  - ${runtime_dir}/docker-compose.yml (symlink to framework repo)"
tal_log ""
tal_log "Backups outside runtime_dir are NOT touched."
tal_log ""

if [[ "$skip_prompt" == "0" ]]; then
  if [[ ! -t 0 ]]; then
    tal_die "non-interactive nuke is blocked. Run from a TTY, or pass --yes if you really mean it."
  fi
  tal_log "To proceed, type the runtime_dir path exactly:"
  tal_log "  ${runtime_dir}"
  read -r -p "> " reply
  if [[ "$reply" != "$runtime_dir" ]]; then
    tal_die "path did not match. Aborted."
  fi
fi

# Stop & remove containers + named/anonymous volumes for this stack.
if [[ -f "${runtime_dir}/docker-compose.yml" ]]; then
  tal_log "Tearing down containers (docker compose down -v)"
  ( cd "$runtime_dir" && docker compose down -v ) || true
fi

tal_log "Removing runtime data"
rm -rf "${runtime_dir}/db"
rm -rf "${runtime_dir}/files"
[[ "$keep_env" == "0" ]] && rm -f "${runtime_dir}/.env"
[[ "$keep_compose" == "0" ]] && rm -f "${runtime_dir}/docker-compose.yml"

tal_log "Nuke complete. Framework repo and backups left intact."
tal_log "Re-run ./bin/bootstrap.sh to start fresh."
