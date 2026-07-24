#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib_tb2.sh
. "$SCRIPT_DIR/lib_tb2.sh"

usage() {
  cat <<'EOF'
Usage: tb2_resolve_submission_task.sh --submission-id UUID [--folder-name NAME]

Resolves a submission to a direct tasks/ child. If no matching local task exists,
downloads the submitted task using the platform's default task folder name.
EOF
}

trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

is_transient_download_error() {
  local output
  output="${1,,}"
  case "$output" in
    *"http 500"*|*"http 502"*|*"http 503"*|*"http 504"*) return 0 ;;
    *"500 internal server error"*|*"502 bad gateway"*) return 0 ;;
    *"503 service unavailable"*|*"504 gateway timeout"*) return 0 ;;
    *"timed out"*|*"timeout"*|*"temporarily unavailable"*) return 0 ;;
    *"connection reset"*|*"connection refused"*|*"connection aborted"*) return 0 ;;
    *"remote end closed connection"*) return 0 ;;
    *) return 1 ;;
  esac
}

submission_id=""
folder_name=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --submission-id) submission_id="${2:-}"; shift 2 ;;
    --folder-name) folder_name="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) tb2_usage_error "unknown argument: $1" ;;
  esac
done

[[ "$submission_id" =~ ^[0-9a-fA-F-]{36}$ ]] \
  || tb2_usage_error "--submission-id must be a UUID"

repo_root="$(tb2_repo_root)"
tasks_dir="$repo_root/tasks"
matches=()

add_match() {
  local candidate="$1"
  local existing
  [ -d "$candidate" ] || return 0
  for existing in "${matches[@]}"; do
    [ "$existing" = "$candidate" ] && return 0
  done
  matches+=("$candidate")
}

for config_path in "$tasks_dir"/*/.snorkel_config; do
  [ -f "$config_path" ] || continue
  while IFS=: read -r key value; do
    key="$(trim "$key")"
    value="$(trim "${value:-}")"
    if [ "$key" = "submission_id" ] && [ "$value" = "$submission_id" ]; then
      add_match "$(dirname "$config_path")"
      break
    fi
  done < "$config_path"
done

if [ "${#matches[@]}" -eq 0 ] && [ -n "$folder_name" ]; then
  if [ "$(basename -- "$folder_name")" != "$folder_name" ]; then
    tb2_die "displayed folder name is not a direct task folder: $folder_name"
  fi

  if [[ "$folder_name" = *... ]]; then
    folder_prefix="${folder_name%...}"
    for candidate in "$tasks_dir"/"$folder_prefix"*; do
      [ -d "$candidate" ] || continue
      add_match "$candidate"
    done
  else
    add_match "$tasks_dir/$folder_name"
  fi
fi

if [ "${#matches[@]}" -gt 1 ]; then
  printf 'warning: submission matches multiple local tasks; downloading submitted artifact to disambiguate:\n' >&2
  for candidate in "${matches[@]}"; do
    printf 'candidate=%s\n' "${candidate#"$repo_root/"}" >&2
  done
fi

if [ "${#matches[@]}" -eq 1 ]; then
  printf 'task_path=%s\n' "${matches[0]#"$repo_root/"}"
  printf 'task_source=local\n'
  exit 0
fi

download_stage="$(mktemp -d "$tasks_dir/.tb2-download-${submission_id}.XXXXXX")"
cleanup() {
  rm -rf "$download_stage"
}
trap cleanup EXIT

printf 'No matching local task; downloading submission %s\n' "$submission_id"
max_download_attempts=5
download_rc=1
download_work=""
for attempt in $(seq 1 "$max_download_attempts"); do
  download_work="$download_stage/attempt-$attempt"
  mkdir -p "$download_work"

  set +e
  download_output="$(cd "$download_work" \
    && stb submissions download "$submission_id" 2>&1)"
  download_rc=$?
  set -e
  printf '%s\n' "$download_output"
  if [ "$download_rc" -eq 0 ]; then
    break
  fi
  if ! is_transient_download_error "$download_output" || [ "$attempt" -eq "$max_download_attempts" ]; then
    exit "$download_rc"
  fi
  printf 'warning: transient download failure on attempt %s; retrying\n' "$attempt" >&2
  sleep $((attempt * 2))
done

[ "$download_rc" -eq 0 ] || exit "$download_rc"

downloaded_tasks=()
for candidate in "$download_work"/*; do
  [ -d "$candidate" ] || continue
  [ -f "$candidate/task.toml" ] || continue
  downloaded_tasks+=("$candidate")
done

if [ "${#downloaded_tasks[@]}" -ne 1 ]; then
  printf 'error: expected exactly one downloaded task folder, found %s\n' "${#downloaded_tasks[@]}" >&2
  for candidate in "${downloaded_tasks[@]}"; do
    printf 'candidate=%s\n' "${candidate#"$download_work/"}" >&2
  done
  exit 3
fi

downloaded_name="$(basename -- "${downloaded_tasks[0]}")"
target="$tasks_dir/$downloaded_name"
if [ -e "$target" ]; then
  [ -d "$target" ] || tb2_die "download target exists but is not a directory: ${target#"$repo_root/"}"
  [ -f "$target/task.toml" ] || tb2_die "download target exists but is not a task folder: ${target#"$repo_root/"}"
  printf 'task_path=%s\n' "${target#"$repo_root/"}"
  printf 'task_source=local-from-download-name\n'
  exit 0
fi

mv "${downloaded_tasks[0]}" "$target"
printf 'task_path=%s\n' "${target#"$repo_root/"}"
printf 'task_source=downloaded\n'
