#!/usr/bin/env bash
set -euo pipefail

TB2_PROJECT_ID="bfe79c33-8ab0-4061-9849-08d3207c9927"
TB2_CACHE_DIR_NAME=".tb2-cache"

tb2_require_ruff() {
  command -v ruff >/dev/null 2>&1 || tb2_die "ruff is required; install it with: uv tool install ruff"
}

tb2_run_platform_ruff() {
  local task_path="$1"
  tb2_require_ruff
  ruff check --isolated --preview --select I,UP,PLW,ISC,PERF "$task_path"
}

tb2_run_advisory_ruff() {
  local task_path="$1"
  local report_dir report_file temp_report task_name ruff_rc summary
  tb2_require_ruff
  printf 'Advisory Ruff command (non-blocking): ruff check --select I,UP,PLW,ISC,E,Q,C,RUF100\n'
  report_dir="$(tb2_cache_root)/tb2-validation/advisory-ruff"
  mkdir -p "$report_dir"
  task_name="$(basename "$task_path")"
  report_file="$report_dir/$task_name.log"
  temp_report="$(mktemp "$report_dir/.$task_name.XXXXXX")"
  if ruff check --select I,UP,PLW,ISC,E,Q,C,RUF100 "$task_path" >"$temp_report" 2>&1; then
    rm -f "$temp_report" "$report_file"
    printf 'Advisory Ruff: 0 findings.\n'
    return 0
  else
    ruff_rc=$?
  fi
  mv "$temp_report" "$report_file"
  summary="$(python3 - "$report_file" <<'PY'
from __future__ import annotations

import collections
import re
import sys

counts: collections.Counter[str] = collections.Counter()
with open(sys.argv[1], encoding="utf-8", errors="replace") as handle:
    for line in handle:
        match = re.match(r"^([A-Z]+\d+)\b", line)
        if match:
            counts[match.group(1)] += 1

total = sum(counts.values())
ordered = sorted(counts.items(), key=lambda item: (-item[1], item[0]))
shown = ordered[:8]
parts = [f"{code}={count}" for code, count in shown]
if len(ordered) > len(shown):
    parts.append(f"other={sum(count for _, count in ordered[len(shown):])}")
print(f"{total}\t{', '.join(parts) if parts else 'unclassified'}")
PY
)"
  printf 'Advisory Ruff: %s findings (%s); non-blocking. Full report: %s\n' "${summary%%$'\t'*}" "${summary#*$'\t'}" "$report_file"
  if [ "$ruff_rc" -ne 1 ]; then
    printf 'warning: advisory Ruff exited with status %s; validation continues because this pass is non-blocking.\n' "$ruff_rc" >&2
  fi
  printf 'Do not rewrite task semantics, NOP behavior, or oracle behavior solely to satisfy advisory findings.\n'
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

tb2_cache_root() {
  local cache_root
  cache_root="$(tb2_repo_root)/$TB2_CACHE_DIR_NAME"
  mkdir -p "$cache_root"
  printf '%s\n' "$cache_root"
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
