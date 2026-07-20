#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib_tb2.sh
. "$SCRIPT_DIR/lib_tb2.sh"

usage() {
  cat <<'EOF'
Usage: tb2_submit_task.sh --task TASK_DIR [--skip-validate]

Prepares upload cleanup, validates, and submits with a random time multiple of
10 between 280 and 350 minutes.
EOF
}

task=""
skip_validate=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --task) task="${2:-}"; shift 2 ;;
    --skip-validate) skip_validate=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) tb2_usage_error "unknown argument: $1" ;;
  esac
done

[ -n "$task" ] || tb2_usage_error "--task is required"

task_path="$(tb2_abs_path "$task")"
[ -d "$task_path" ] || tb2_die "task directory not found: $task_path"

if [ "$skip_validate" -eq 0 ]; then
  "$SCRIPT_DIR/tb2_validate_task.sh" --context create --task "$task_path"
fi

"$SCRIPT_DIR/tb2_prepare_upload.sh" --task "$task_path"

minutes="$(tb2_random_time_minutes)"
printf 'selected_time_minutes=%s\n' "$minutes"

stb submissions create "$task_path" -p "$TB2_PROJECT_ID" --time "$minutes"
