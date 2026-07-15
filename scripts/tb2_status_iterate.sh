#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib_tb2.sh
. "$SCRIPT_DIR/lib_tb2.sh"

usage() {
  cat <<'EOF'
Usage: tb2_status_iterate.sh --submission-id UUID

Fetches platform feedback, prints stb stdout/stderr, and reports optional files created by stb.
EOF
}

submission_id=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --submission-id) submission_id="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) tb2_usage_error "unknown argument: $1" ;;
  esac
done

[ -n "$submission_id" ] || tb2_usage_error "--submission-id is required"

printf 'Fetching feedback for %s\n' "$submission_id"
set +e
feedback_output="$(stb submissions feedback "$submission_id" 2>&1)"
feedback_rc=$?
set -e

printf '%s\n' "$feedback_output"
printf 'feedback_rc=%s\n' "$feedback_rc"

feedback_dir=""
while IFS= read -r line; do
  case "$line" in
    "Feedback written to "*) feedback_dir="${line#Feedback written to }" ;;
  esac
done <<< "$feedback_output"

if [ -n "$feedback_dir" ]; then
  printf 'Feedback directory: %s\n' "$feedback_dir"
  if [ -f "$feedback_dir/feedback.txt" ]; then
    printf 'Existing feedback file: %s/feedback.txt\n' "$feedback_dir"
  fi
  if [ -f "$feedback_dir/feedback.stderr" ]; then
    printf 'Existing feedback file: %s/feedback.stderr\n' "$feedback_dir"
  fi
else
  printf 'warning: stb did not report a feedback directory\n' >&2
fi

exit "$feedback_rc"
