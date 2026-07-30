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
must pass. Every platform attempt is written to the shared update ledger.
Transient stb failures are attempted at most five times; platform static-check
failures stop immediately so they can be repaired before retrying.
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

snorkel_config="$task_path/.snorkel_config"
current_config_submission=""
if [ -f "$snorkel_config" ]; then
  while IFS=: read -r key value; do
    key="${key#"${key%%[![:space:]]*}"}"
    key="${key%"${key##*[![:space:]]}"}"
    value="${value:-}"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    if [ "$key" = "submission_id" ]; then
      current_config_submission="$value"
      break
    fi
  done < "$snorkel_config"
fi

if [ "$current_config_submission" != "$submission_id" ]; then
  printf 'submission_id: %s\n' "$submission_id" > "$snorkel_config"
  if [ -n "$current_config_submission" ]; then
    printf 'updated .snorkel_config submission_id: %s -> %s\n' "$current_config_submission" "$submission_id"
  else
    printf 'wrote .snorkel_config submission_id: %s\n' "$submission_id"
  fi
fi

prep_output="$("$SCRIPT_DIR/tb2_prepare_upload.sh" --task "$task_path")"
printf '%s\n' "$prep_output"

if [[ "$prep_output" =~ removed\ __pycache__\ directories:\ [1-9][0-9]* ]] \
  || [[ "$prep_output" =~ removed\ root\ task\ \.zip\ files:\ [1-9][0-9]* ]]; then
  tb2_die "upload preparation changed files; validate and rerun this helper"
fi

printf '\n== Platform-aligned Ruff check ==\n'
tb2_run_platform_ruff "$task_path" || tb2_die "local Ruff check failed; repair the findings, revalidate, and rerun this helper"

minutes="$(tb2_random_time_minutes)"
printf 'selected_time_minutes=%s\n' "$minutes"

update_command=(stb submissions update "$task_path" -s "$submission_id" --time "$minutes")
update_mode="reviewer"
if [ -z "$send_to_reviewer" ]; then
  update_command+=(--no-send-to-reviewer)
  update_mode="checks"
fi

state_helper="$SCRIPT_DIR/tb2_update_state.py"
active_attempt_id=""
latest_attempts=0

finish_attempt() {
  local outcome="$1" finish_output key value
  [ -n "$active_attempt_id" ] || return 0
  finish_output="$(python3 "$state_helper" finish-platform-attempt \
    --submission-id "$submission_id" \
    --attempt-id "$active_attempt_id" \
    --outcome "$outcome")"
  printf '%s\n' "$finish_output"
  while IFS='=' read -r key value; do
    if [ "$key" = "platform_attempts" ]; then
      latest_attempts="$value"
    fi
  done <<< "$finish_output"
  active_attempt_id=""
}

finish_unknown() {
  if [ -n "$active_attempt_id" ]; then
    set +e
    python3 "$state_helper" record-unknown \
      --submission-id "$submission_id" \
      --attempt-id "$active_attempt_id" >&2
    active_attempt_id=""
    set -e
  fi
}

trap finish_unknown EXIT
trap 'finish_unknown; exit 130' INT
trap 'finish_unknown; exit 143' TERM

max_attempts=5
for attempt in $(seq 1 "$max_attempts"); do
  printf 'update_mode=%s\n' "$update_mode"
  begin_output="$(python3 "$state_helper" begin-platform-attempt \
    --submission-id "$submission_id" \
    --mode "$update_mode" \
    --task "$task_path")"
  printf '%s\n' "$begin_output"
  while IFS='=' read -r key value; do
    case "$key" in
      platform_attempt_id) active_attempt_id="$value" ;;
      platform_attempts) latest_attempts="$value" ;;
    esac
  done <<< "$begin_output"
  [ -n "$active_attempt_id" ] || tb2_die "state helper did not return a platform attempt ID"
  set +e
  update_output="$("${update_command[@]}" 2>&1)"
  update_rc=$?
  set -e
  printf '%s\n' "$update_output"
  if [ "$update_rc" -eq 0 ]; then
    if [ "$update_mode" = "checks" ]; then
      finish_attempt checks_submitted
      printf 'update_result=CHECKS SUBMITTED\n'
    else
      finish_attempt reviewer_submitted
      printf 'update_result=SENT TO REVIEWER\n'
    fi
    printf 'update_attempt=%s\n' "$attempt"
    printf 'update_attempts=%s\n' "$latest_attempts"
    exit 0
  fi
  if [[ "${update_output,,}" == *"platform checks failed"* ]] \
    || [[ "${update_output,,}" == *"static checks failed"* ]]; then
    finish_attempt static_checks_failed
    printf 'update_static_checks=failed\n'
    printf 'update_attempts=%s\n' "$latest_attempts"
    printf 'error: platform static checks failed; repair the reported findings, revalidate, and rerun this helper\n' >&2
    exit 3
  fi
  if [ "$attempt" -lt "$max_attempts" ]; then
    finish_attempt transient_failure
  else
    finish_attempt definitive_failure
  fi
  printf 'update_attempt=%s\n' "$attempt"
  if [ "$attempt" -lt "$max_attempts" ]; then
    printf 'warning: update attempt %s failed; retrying\n' "$attempt" >&2
    sleep $((attempt * 2))
  fi
done

printf 'update_attempts=%s\n' "$latest_attempts"
printf 'error: update failed after %s attempts\n' "$max_attempts" >&2
exit "$update_rc"
