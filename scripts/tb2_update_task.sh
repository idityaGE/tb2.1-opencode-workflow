#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib_tb2.sh
. "$SCRIPT_DIR/lib_tb2.sh"

usage() {
  cat <<'EOF'
Usage: tb2_update_task.sh --task TASK_DIR --submission-id SUBMISSION_ID [--send-to-reviewer]

Prepares upload cleanup, stops if that changed files, then updates for automated
checks by default. --send-to-reviewer omits --no-send-to-reviewer. Local Ruff
must pass. Transient stb failures are attempted at most five times; platform
static-check failures stop immediately so they can be repaired before retrying.
EOF
}

task=""
submission_id=""
send_to_reviewer=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --task) task="${2:-}"; shift 2 ;;
    --submission-id) submission_id="${2:-}"; shift 2 ;;
    --send-to-reviewer) send_to_reviewer=1; shift ;;
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

printf '\n== Platform-aligned Ruff check ==\n'
command -v ruff >/dev/null 2>&1 || tb2_die "ruff is required before a platform update"
tb2_run_platform_ruff "$task_path" || tb2_die "local Ruff check failed; repair the findings, revalidate, and rerun this helper"

minutes="$(tb2_random_time_minutes)"
printf 'selected_time_minutes=%s\n' "$minutes"

update_command=(stb submissions update "$task_path" -s "$submission_id" --time "$minutes")
update_mode="reviewer"
if [ -z "$send_to_reviewer" ]; then
  update_command+=(--no-send-to-reviewer)
  update_mode="checks"
fi

max_attempts=5
for attempt in $(seq 1 "$max_attempts"); do
  printf 'update_mode=%s\n' "$update_mode"
  set +e
  update_output="$("${update_command[@]}" 2>&1)"
  update_rc=$?
  set -e
  printf '%s\n' "$update_output"
  if [ "$update_rc" -eq 0 ]; then
    printf 'update_attempt=%s\n' "$attempt"
    printf 'update_attempts=%s\n' "$attempt"
    exit 0
  fi
  if [[ "${update_output,,}" == *"platform checks failed"* ]] \
    || [[ "${update_output,,}" == *"static checks failed"* ]]; then
    printf 'update_static_checks=failed\n'
    printf 'error: platform static checks failed; repair the reported findings, revalidate, and rerun this helper\n' >&2
    exit 3
  fi
  printf 'update_attempt=%s\n' "$attempt"
  if [ "$attempt" -lt "$max_attempts" ]; then
    printf 'warning: update attempt %s failed; retrying\n' "$attempt" >&2
    sleep $((attempt * 2))
  fi
done

printf 'error: update failed after %s attempts\n' "$max_attempts" >&2
exit "$update_rc"
