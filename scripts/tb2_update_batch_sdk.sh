#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib_tb2.sh
. "$SCRIPT_DIR/lib_tb2.sh"

repo_root="$(tb2_repo_root)"
cd "$repo_root"

exec bun "$SCRIPT_DIR/tb2_update_batch_sdk.mjs" --repo-root "$repo_root" "$@"
