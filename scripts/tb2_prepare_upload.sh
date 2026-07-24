#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib_tb2.sh
. "$SCRIPT_DIR/lib_tb2.sh"

usage() {
  cat <<'EOF'
Usage: tb2_prepare_upload.sh --task TASK_DIR

Prepares a task directory for platform upload by repairing environment/.dockerignore,
removing generated cache directories, and deleting the generated root-level archive.
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
repo_root="$(tb2_repo_root)"
task_path="$(tb2_abs_path "$task")"
[ -d "$task_path" ] || tb2_die "task directory not found: $task_path"

tasks_root="$repo_root/tasks"
if [ "$(dirname "$task_path")" != "$tasks_root" ]; then
  tb2_die "task directory must be a direct child of $tasks_root: $task_path"
fi
[ -f "$task_path/task.toml" ] || tb2_die "task.toml not found in task directory: $task_path"

environment_dir="$task_path/environment"
[ -d "$environment_dir" ] || tb2_die "environment directory not found: $environment_dir"
dockerignore="$environment_dir/.dockerignore"
touch "$dockerignore"

required_dockerignore_entries=(
  ".git"
  ".env"
  "node_modules/"
  "__pycache__/"
  "**/__pycache__/"
  "*.pyc"
  "**/*.pyc"
  ".pytest_cache/"
  "**/.pytest_cache/"
  "solution/"
  "tests/"
)
missing_dockerignore_entries=()
for entry in "${required_dockerignore_entries[@]}"; do
  if ! grep -Fqx -- "$entry" "$dockerignore"; then
    missing_dockerignore_entries+=("$entry")
  fi
done
if [ "${#missing_dockerignore_entries[@]}" -gt 0 ]; then
  if [ -s "$dockerignore" ] && [ -n "$(tail -c 1 "$dockerignore")" ]; then
    printf '\n' >> "$dockerignore"
  fi
  printf '%s\n' "${missing_dockerignore_entries[@]}" >> "$dockerignore"
fi

pycache_removed=0
while IFS= read -r -d '' cache_dir; do
  rm -rf "$cache_dir"
  pycache_removed=$((pycache_removed + 1))
done < <(find "$task_path" -type d -name __pycache__ -prune -print0)

zip_removed=0
zip_file="$task_path/$(basename "$task_path").zip"
if [ -f "$zip_file" ]; then
  rm -f "$zip_file"
  zip_removed=1
fi

printf 'Upload preparation completed for %s\n' "$task_path"
printf 'added required .dockerignore entries: %s\n' "${#missing_dockerignore_entries[@]}"
printf 'removed __pycache__ directories: %s\n' "$pycache_removed"
printf 'removed root task .zip files: %s\n' "$zip_removed"
