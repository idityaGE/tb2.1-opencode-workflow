#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib_tb2.sh
. "$SCRIPT_DIR/lib_tb2.sh"

usage() {
  cat <<'EOF'
Usage: tb2_list_revisions.sh

Lists only NEEDS_REVISION submissions for the configured TB2 project as TSV.
EOF
}

if [ "$#" -gt 0 ]; then
  case "$1" in
    -h|--help) usage; exit 0 ;;
    *) tb2_usage_error "this helper accepts no arguments" ;;
  esac
fi

set +e
list_output="$(stb submissions list -p "$TB2_PROJECT_ID" --show-folder-names 2>&1)"
list_rc=$?
set -e

if [ "$list_rc" -ne 0 ]; then
  printf '%s\n' "$list_output" >&2
  exit "$list_rc"
fi

trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

printf 'submission_id\tfolder_name\tassignment_state\n'
while IFS='│' read -r _ row_number submission_id created_at folder_name assignment_state payment_status _; do
  submission_id="$(trim "${submission_id:-}")"
  folder_name="$(trim "${folder_name:-}")"
  assignment_state="$(trim "${assignment_state:-}")"
  if [ "$assignment_state" = "NEEDS_REVISION" ] \
    && [[ "$submission_id" =~ ^[0-9a-fA-F-]{36}$ ]]; then
    printf '%s\t%s\t%s\n' "$submission_id" "$folder_name" "$assignment_state"
  fi
done <<< "$list_output"
