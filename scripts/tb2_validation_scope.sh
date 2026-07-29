#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib_tb2.sh
. "$SCRIPT_DIR/lib_tb2.sh"

usage() {
  cat <<'EOF'
Usage: tb2_validation_scope.sh --task TASK_DIR

Classifies the current task-local change scope for update-task.
Prints mode=fast-only or mode=full, plus the reason. fast-only means the
changed task files are limited to instruction.md and/or task.toml, so NOP and
oracle are not needed.
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
task_rel="$(tb2_task_rel_path "$task_path")"
baseline_file="$(tb2_cache_root)/tb2-validation/$(basename "$task_path").runtime.sha256"

cd "$repo_root"

changed_files="$(git status --short -- "$task_rel" | while IFS= read -r line; do printf '%s\n' "${line#???}"; done)"
runtime_changed=""
if [ -n "$changed_files" ]; then
  while IFS= read -r file_path; do
    [ -n "$file_path" ] || continue
    if ! tb2_is_fast_validation_path "$file_path"; then
      runtime_changed=1
      break
    fi
  done <<EOF
$changed_files
EOF
fi

if [ -n "$runtime_changed" ]; then
  printf 'mode=full\nreason=runtime-affecting task files are changed\n'
  exit 0
fi

if [ -f "$baseline_file" ]; then
  current_baseline="$(mktemp)"
  git ls-files -co --exclude-standard -- "$task_rel" |
    while IFS= read -r file_path; do
      if ! tb2_is_fast_validation_path "$file_path"; then
        printf '%s\0' "$file_path"
      fi
    done |
    xargs -0 -r sha256sum > "$current_baseline"
  if ! cmp -s "$baseline_file" "$current_baseline"; then
    rm -f "$current_baseline"
    printf 'mode=full\nreason=runtime-affecting files differ from last full-validation baseline\n'
    exit 0
  fi
  rm -f "$current_baseline"
fi

if [ -n "$changed_files" ]; then
  instruction_changed=""
  task_toml_changed=""
  while IFS= read -r file_path; do
    [ -n "$file_path" ] || continue
    if tb2_is_instruction_path "$file_path"; then
      instruction_changed=1
    elif [ "${file_path#tasks/*/}" != "$file_path" ] && [ "${file_path##*/}" = "task.toml" ]; then
      task_toml_changed=1
    fi
  done <<EOF
$changed_files
EOF
  if [ -n "$instruction_changed" ] && [ -n "$task_toml_changed" ]; then
    printf 'mode=fast-only\nreason=only instruction and task.toml files changed\n'
  elif [ -n "$task_toml_changed" ]; then
    printf 'mode=fast-only\nreason=only task.toml changed\n'
  else
    printf 'mode=fast-only\nreason=only instruction files changed\n'
  fi
else
  printf 'mode=fast-only\nreason=no task-local file changes detected\n'
fi
