#!/usr/bin/env bash
# install-launchd.sh - install or uninstall the nightly backup LaunchAgent.
#
# Reads bin/launchd/com.task-a-llama.backup.plist, substitutes
# __BIN_DIR__ and __LOG_DIR__, and (un)loads via launchctl.
#
# Idempotent install: re-running cleanly replaces the previous load.
#
# Usage:
#   ./bin/install-launchd.sh             # install
#   ./bin/install-launchd.sh --uninstall # remove

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/config.sh"
require_local_backend

mode="install"
for arg in "$@"; do
  case "$arg" in
    --uninstall) mode="uninstall" ;;
    -h|--help)
      sed -n '2,11p' "${BASH_SOURCE[0]}"
      exit 0
      ;;
    *) tal_die "unknown argument: $arg" ;;
  esac
done

require_cmd launchctl "ships with macOS"

template="${TAL_ROOT}/bin/launchd/com.task-a-llama.backup.plist"
[[ -f "$template" ]] || tal_die "template not found at ${template}"

label="com.task-a-llama.backup"
plist_dest="${HOME}/Library/LaunchAgents/${label}.plist"
log_dir="${HOME}/Library/Logs/task-a-llama"
bin_dir="${TAL_ROOT}/bin"
uid="$(id -u)"
domain="gui/${uid}"

unload_if_loaded() {
  if launchctl print "${domain}/${label}" >/dev/null 2>&1; then
    tal_log "Unloading existing agent (${domain}/${label})..."
    launchctl bootout "${domain}" "${plist_dest}" 2>/dev/null || \
      launchctl bootout "${domain}/${label}" 2>/dev/null || true
  fi
}

if [[ "$mode" == "uninstall" ]]; then
  unload_if_loaded
  if [[ -f "$plist_dest" ]]; then
    rm "$plist_dest"
    tal_log "Removed ${plist_dest}"
  else
    tal_log "Nothing to remove at ${plist_dest}"
  fi
  exit 0
fi

# Install path.
mkdir -p "$log_dir" "${HOME}/Library/LaunchAgents"

# Substitute placeholders into the destination plist.
# sed with | as delimiter is safe; bin_dir and log_dir don't contain | on macOS.
sed \
  -e "s|__BIN_DIR__|${bin_dir}|g" \
  -e "s|__LOG_DIR__|${log_dir}|g" \
  "$template" > "$plist_dest"

# Quick sanity: the destination plist should no longer contain placeholders.
if grep -q '__BIN_DIR__\|__LOG_DIR__' "$plist_dest"; then
  tal_die "placeholder substitution failed; check ${plist_dest}"
fi

unload_if_loaded
tal_log "Loading ${plist_dest}..."
launchctl bootstrap "$domain" "$plist_dest"

tal_log ""
tal_log "Installed. Verify:"
tal_log "  launchctl print ${domain}/${label}"
tal_log "  tail -f ${log_dir}/backup.log"
tal_log ""
tal_log "Trigger a one-off run:"
tal_log "  launchctl kickstart ${domain}/${label}"
tal_log ""
tal_log "Uninstall: ./bin/install-launchd.sh --uninstall"
