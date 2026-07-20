#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib_tb2.sh
. "$SCRIPT_DIR/lib_tb2.sh"

usage() {
  cat <<'EOF'
Usage: tb2_hook_task_check.sh --task TASK_DIR

Runs the fast structural task lint used by the opencode post-edit hook.
Full validation, including ruff, NOP, and oracle, lives in tb2_validate_task.sh.
EOF
}

task=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --task) task="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) tb2_usage_error "unknown argument: $1" ;;
  esac
done

[ -n "$task" ] || tb2_usage_error "--task is required"

python3 "$SCRIPT_DIR/tb2_task_lint.py" --context revision "$task"
