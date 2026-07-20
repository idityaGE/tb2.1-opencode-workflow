#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib_tb2.sh
. "$SCRIPT_DIR/lib_tb2.sh"

usage() {
  cat <<'EOF'
Usage: tb2_update_task.sh --task TASK_DIR --submission-id SUBMISSION_ID

Prepares upload cleanup, stops if that changed files, then updates without
sending to reviewer using a random time multiple of 10 between 280 and 350 minutes.
EOF
}

task=""
submission_id=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --task) task="${2:-}"; shift 2 ;;
    --submission-id) submission_id="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) tb2_usage_error "unknown argument: $1" ;;
  esac
done

[ -n "$task" ] || tb2_usage_error "--task is required"
[ -n "$submission_id" ] || tb2_usage_error "--submission-id is required"

task_path="$(tb2_abs_path "$task")"
[ -d "$task_path" ] || tb2_die "task directory not found: $task_path"

prep_output="$("$SCRIPT_DIR/tb2_prepare_upload.sh" --task "$task_path")"
printf '%s\n' "$prep_output"

if [[ "$prep_output" =~ removed\ __pycache__\ directories:\ [1-9][0-9]* ]] \
  || [[ "$prep_output" =~ removed\ root\ task\ \.zip\ files:\ [1-9][0-9]* ]]; then
  tb2_die "upload preparation changed files; validate and rerun this helper"
fi

minutes="$(tb2_random_time_minutes)"
printf 'selected_time_minutes=%s\n' "$minutes"

stb submissions update "$task_path" -s "$submission_id" --time "$minutes" --no-send-to-reviewer
