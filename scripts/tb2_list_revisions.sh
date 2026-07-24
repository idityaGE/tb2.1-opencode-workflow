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
list_output="$(stb submissions list -p "$TB2_PROJECT_ID" 2>&1)"
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
submission_index=-1
folder_index=-1
assignment_index=-1
while IFS='│' read -r -a cells; do
  for ((index = 0; index < ${#cells[@]}; index++)); do
    cell="$(trim "${cells[$index]}")"
    case "$cell" in
      "Submission ID") submission_index=$index ;;
      "Folder Name") folder_index=$index ;;
      "Assignment State") assignment_index=$index ;;
    esac
  done

  [ "$submission_index" -ge 0 ] && [ "$assignment_index" -ge 0 ] || continue
  submission_id="$(trim "${cells[$submission_index]:-}")"
  assignment_state="$(trim "${cells[$assignment_index]:-}")"
  folder_name=""
  if [ "$folder_index" -ge 0 ]; then
    folder_name="$(trim "${cells[$folder_index]:-}")"
  fi

  if [ "$assignment_state" = "NEEDS_REVISION" ] \
    && [[ "$submission_id" =~ ^[0-9a-fA-F-]{36}$ ]]; then
    printf '%s\t%s\t%s\n' "$submission_id" "$folder_name" "$assignment_state"
  fi
done <<< "$list_output"
