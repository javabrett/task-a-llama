#!/usr/bin/env bash
# backup.sh - create a point-in-time backup of the Vikunja database and attachments.
#
# Produces two artifacts per run:
#   1. Binary snapshot: <backup.binary_dir>/task-a-llama-YYYY-MM-DD-HHMMSS.tgz
#      Contains a transaction-safe SQLite copy (via .backup) plus the files/ dir.
#      Retention: rolling <backup.retention_days> days (default 7).
#   2. SQL dump: <backup.sql_dump_target>
#      Plain SQL for diffable Git history; overwrites each run.
#
# Flags:
#   --commit   After the dump, git-commit the data repo (no push).
#   --push     Imply --commit and also push to origin.
#   --no-prune Skip retention pruning (debugging / catastrophic-avoidance).
#
# The stack does NOT need to be stopped - .backup is online-safe.

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/config.sh"
require_config
require_cmd sqlite3
require_cmd tar

do_commit=0
do_push=0
do_prune=1
for arg in "$@"; do
  case "$arg" in
    --commit) do_commit=1 ;;
    --push) do_commit=1; do_push=1 ;;
    --no-prune) do_prune=0 ;;
    -h|--help)
      sed -n '2,17p' "${BASH_SOURCE[0]}"
      exit 0
      ;;
    *) tal_die "unknown argument: $arg" ;;
  esac
done

runtime_dir="$(config_runtime_dir)"
db_file="${runtime_dir}/db/vikunja.db"
files_dir="${runtime_dir}/files"
binary_dir="$(config_backup_binary_dir)"
sql_target="$(config_sql_dump_target)"
retention_days="$(config_retention_days)"

[[ -f "$db_file" ]] || tal_die "database not found: ${db_file}"
mkdir -p "$binary_dir"
mkdir -p "$(dirname "$sql_target")"

stamp="$(date +%Y-%m-%d-%H%M%S)"
tgz_path="${binary_dir}/task-a-llama-${stamp}.tgz"

# Stage snapshot + files in a temp dir, then tar.
work_dir="$(mktemp -d -t tal-backup.XXXXXX)"
trap 'rm -rf "$work_dir"' EXIT

tal_log "Creating online snapshot via sqlite3 .backup"
sqlite3 "$db_file" ".backup '${work_dir}/vikunja.db'"

# Copy attachments (may be empty for TODO-style usage).
mkdir -p "${work_dir}/files"
if [[ -d "$files_dir" ]]; then
  # cp -R copies dot-files too via the /. source form.
  cp -R "${files_dir}/." "${work_dir}/files/"
fi

tal_log "Archiving to ${tgz_path}"
tar -czf "$tgz_path" -C "$work_dir" vikunja.db files

# Prune old tgz backups. Only prune files matching our naming pattern so we
# never touch anything else a user might have parked in binary_dir.
if [[ "$do_prune" == "1" ]]; then
  tal_log "Pruning backups older than ${retention_days} days in ${binary_dir}"
  find "$binary_dir" -maxdepth 1 -type f -name 'task-a-llama-*.tgz' -mtime "+${retention_days}" -print -delete || true
fi

tal_log "Writing SQL dump to ${sql_target}"
sqlite3 "$db_file" ".dump" > "$sql_target"

if [[ "$do_commit" == "1" ]]; then
  data_local="$(config_data_repo_local)"
  [[ -n "$data_local" ]] || tal_die "--commit requires sources.data.local in config.yml"
  [[ -d "${data_local}/.git" ]] || tal_die "--commit requires a git repo at ${data_local}"

  rel_dump="${sql_target#${data_local}/}"
  if [[ "$rel_dump" == "$sql_target" ]]; then
    tal_err "WARN: sql_dump_target (${sql_target}) is not inside data repo (${data_local})."
    tal_err "      Commit will operate on the repo's tracked state anyway."
  fi

  tal_log "Committing dump in ${data_local}"
  git -C "$data_local" add "$sql_target"
  if git -C "$data_local" diff --cached --quiet; then
    tal_log "No changes to commit (dump matches last commit)"
  else
    git -C "$data_local" commit -m "backup: ${stamp}" >/dev/null
    tal_log "Committed backup: ${stamp}"
    if [[ "$do_push" == "1" ]]; then
      tal_log "Pushing to origin"
      git -C "$data_local" push
    fi
  fi
fi

tal_log "Backup complete."
tal_log "  Binary: ${tgz_path}"
tal_log "  SQL:    ${sql_target}"
