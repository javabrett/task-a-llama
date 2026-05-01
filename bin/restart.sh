#!/usr/bin/env bash
# restart.sh - restart the Vikunja stack.
# Use after editing the Docker-side .env (e.g. updating TZ).
#
# Usage:
#   restart.sh [<slug>]    # default: active slug

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/config.sh"

slug="$(config_resolve_slug "${1:-}")"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"${script_dir}/down.sh" "$slug"
"${script_dir}/up.sh" "$slug"
