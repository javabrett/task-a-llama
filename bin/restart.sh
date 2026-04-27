#!/usr/bin/env bash
# restart.sh - restart the Vikunja stack.
# Use after editing .env (e.g. flipping ENABLEREGISTRATION off).

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"${script_dir}/down.sh"
"${script_dir}/up.sh"
