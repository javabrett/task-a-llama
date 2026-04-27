#!/usr/bin/env bash
# restore.sh - restore the Vikunja database from a backup.
#
# Usage:
#   restore.sh binary <path-to-tgz>   Restore from a task-a-llama-*.tgz snapshot
#   restore.sh sql    <path-to-sql>   Restore from a sqlite3 .dump SQL file
#
# Behaviour:
#   - Confirms before overwriting the live database.
#   - Stops the stack, swaps data, starts the stack.
#   - For binary: replaces db/vikunja.db AND files/ (attachments).
#   - For sql: replaces db/vikunja.db only (SQL dump does not carry files).

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/config.sh"
require_config
require_cmd sqlite3
require_cmd tar

if [[ $# -lt 2 ]]; then
  sed -n '2,13p' "${BASH_SOURCE[0]}"
  exit 1
fi

mode="$1"
src="$2"
[[ -f "$src" ]] || tal_die "source file not found: ${src}"

runtime_dir="$(config_runtime_dir)"
db_file="${runtime_dir}/db/vikunja.db"
files_dir="${runtime_dir}/files"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

tal_log "Restore plan:"
tal_log "  mode:         ${mode}"
tal_log "  source:       ${src}"
tal_log "  target db:    ${db_file}"
if [[ "$mode" == "binary" ]]; then
  tal_log "  target files: ${files_dir}"
fi

if [[ -t 0 ]]; then
  read -r -p "This will overwrite the current database. Proceed? [y/N] " reply
  [[ "$reply" =~ ^[Yy] ]] || tal_die "aborted by user"
else
  tal_die "non-interactive restore is not supported (safety). Run from a TTY."
fi

# Bring the stack down so we have exclusive access to the DB file.
if [[ -f "${runtime_dir}/docker-compose.yml" ]]; then
  tal_log "Stopping stack"
  "${script_dir}/down.sh"
fi

case "$mode" in
  binary)
    work_dir="$(mktemp -d -t tal-restore.XXXXXX)"
    trap 'rm -rf "$work_dir"' EXIT
    tal_log "Extracting ${src}"
    tar -xzf "$src" -C "$work_dir"
    [[ -f "${work_dir}/vikunja.db" ]] || tal_die "archive missing vikunja.db"

    mkdir -p "$(dirname "$db_file")"
    cp "${work_dir}/vikunja.db" "$db_file"
    tal_log "Restored DB from snapshot"

    if [[ -d "${work_dir}/files" ]]; then
      mkdir -p "$files_dir"
      # Clear existing files, then copy extracted.
      rm -rf "${files_dir:?}"/*
      cp -R "${work_dir}/files/." "$files_dir/"
      tal_log "Restored attachments"
    fi
    ;;
  sql)
    mkdir -p "$(dirname "$db_file")"
    rm -f "$db_file" "${db_file}-journal" "${db_file}-wal" "${db_file}-shm"
    tal_log "Replaying SQL dump into new database"
    sqlite3 "$db_file" < "$src"
    tal_log "Note: SQL dump does not carry attachments. files/ left untouched."
    ;;
  *)
    tal_die "unknown mode: ${mode} (expected 'binary' or 'sql')"
    ;;
esac

tal_log "Starting stack"
"${script_dir}/up.sh"
tal_log "Restore complete."
