#!/usr/bin/env bash
# restart.sh - restart the Vikunja stack.
# Use after editing .env (e.g. updating TZ or VIKUNJA_API_TOKEN).

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/config.sh"
require_config
require_local_backend

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"${script_dir}/down.sh"
"${script_dir}/up.sh"
