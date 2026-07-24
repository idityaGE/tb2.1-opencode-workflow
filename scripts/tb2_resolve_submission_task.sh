#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib_tb2.sh
. "$SCRIPT_DIR/lib_tb2.sh"

usage() {
  cat <<'EOF'
Usage: tb2_resolve_submission_task.sh --submission-id UUID [--folder-name NAME]

Resolves a submission to a direct tasks/ child. If no matching local task exists,
downloads the submitted task into tasks/<submission-id>.
EOF
}

trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
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
  printf 'error: submission matches multiple local tasks:\n' >&2
  for candidate in "${matches[@]}"; do
    printf 'candidate=%s\n' "${candidate#"$repo_root/"}" >&2
  done
  exit 3
fi

if [ "${#matches[@]}" -eq 1 ]; then
  printf 'task_path=%s\n' "${matches[0]#"$repo_root/"}"
  printf 'task_source=local\n'
  exit 0
fi

target="$tasks_dir/$submission_id"
if [ -f "$target/task.toml" ]; then
  printf 'task_path=tasks/%s\n' "$submission_id"
  printf 'task_source=local\n'
  exit 0
fi
[ ! -e "$target" ] || tb2_die "download target already exists but is not a task: $target"

download_stage="$(mktemp -d "$tasks_dir/.tb2-download-${submission_id}.XXXXXX")"
cleanup() {
  rm -rf "$download_stage"
}
trap cleanup EXIT
download_path="$download_stage/task"

printf 'No matching local task; downloading submission %s\n' "$submission_id"
set +e
download_output="$(cd "$tasks_dir" \
  && stb submissions download "$submission_id" --output "$download_path" 2>&1)"
download_rc=$?
set -e
printf '%s\n' "$download_output"
[ "$download_rc" -eq 0 ] || exit "$download_rc"
[ -f "$download_path/task.toml" ] \
  || tb2_die "downloaded submission does not contain task.toml at its root"

mv "$download_path" "$target"
printf 'task_path=tasks/%s\n' "$submission_id"
printf 'task_source=downloaded\n'
