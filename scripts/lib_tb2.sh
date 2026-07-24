#!/usr/bin/env bash
set -euo pipefail

TB2_PROJECT_ID="bfe79c33-8ab0-4061-9849-08d3207c9927"

tb2_require_ruff() {
  command -v ruff >/dev/null 2>&1 || tb2_die "ruff is required; install it with: uv tool install ruff"
}

tb2_run_platform_ruff() {
  local task_path="$1"
  tb2_require_ruff
  ruff check --isolated --preview --select I,UP,PLW,ISC,PERF "$task_path"
}

tb2_random_time_minutes() {
  local bucket
  bucket=$((RANDOM % 8))
  printf '%s\n' $((280 + (bucket * 10)))
}

tb2_die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

tb2_script_dir() {
  local src
  src="${BASH_SOURCE[0]}"
  while [ -L "$src" ]; do
    src="$(readlink "$src")"
  done
  cd "$(dirname "$src")" && pwd
}

tb2_repo_root() {
  local dir
  dir="$(pwd)"
  while [ "$dir" != "/" ]; do
    if [ -f "$dir/docs/cli-user-guide.md" ] && [ -d "$dir/tasks" ]; then
      printf '%s\n' "$dir"
      return 0
    fi
    dir="$(dirname "$dir")"
  done

  dir="$(tb2_script_dir)"
  while [ "$dir" != "/" ]; do
    if [ -f "$dir/docs/cli-user-guide.md" ] && [ -d "$dir/tasks" ]; then
      printf '%s\n' "$dir"
      return 0
    fi
    dir="$(dirname "$dir")"
  done

  tb2_die "could not find repo root containing docs/cli-user-guide.md and tasks/"
}

tb2_abs_path() {
  local path="$1"
  if [ -d "$path" ]; then
    cd "$path" && pwd
  else
    local dir base
    dir="$(dirname "$path")"
    base="$(basename "$path")"
    cd "$dir" && printf '%s/%s\n' "$(pwd)" "$base"
  fi
}

tb2_usage_error() {
  printf '%s\n' "$1" >&2
  exit 2
}

tb2_task_rel_path() {
  local path="$1"
  local repo_root abs_path
  repo_root="$(tb2_repo_root)"
  abs_path="$(tb2_abs_path "$path")"
  case "$abs_path" in
    "$repo_root"/tasks/*) printf 'tasks/%s\n' "${abs_path#"$repo_root/tasks/"}" ;;
    *) tb2_die "task path must be under $repo_root/tasks: $abs_path" ;;
  esac
}

tb2_is_instruction_path() {
  case "$1" in
    tasks/*/instruction.md) return 0 ;;
    tasks/*/steps/milestone_*/instruction.md) return 0 ;;
    *) return 1 ;;
  esac
}

tb2_is_fast_validation_path() {
  case "$1" in
    tasks/*/task.toml) return 0 ;;
    *) tb2_is_instruction_path "$1" ;;
  esac
}
