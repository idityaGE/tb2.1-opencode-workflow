#!/usr/bin/env bash
set -euo pipefail

TB2_PROJECT_ID="bfe79c33-8ab0-4061-9849-08d3207c9927"

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

tb2_is_task_toml_path() {
  case "$1" in
    tasks/*/task.toml) return 0 ;;
    *) return 1 ;;
  esac
}

tb2_is_fast_validation_path() {
  tb2_is_instruction_path "$1"
}

tb2_task_toml_metadata_change_only() {
  local file_path="$1"
  python3 - "$file_path" <<'PY'
from __future__ import annotations

import subprocess
import sys
import tomllib

ALLOWED_METADATA_KEYS = {
    "metadata.author_name",
    "metadata.author_email",
    "metadata.category",
    "metadata.subcategories",
    "metadata.difficulty",
    "metadata.languages",
    "metadata.tags",
    "metadata.codebase_size",
}


def parse_toml(data: bytes) -> object:
    return tomllib.loads(data.decode("utf-8"))


def runtime_projection(value: object, prefix: tuple[str, ...] = ()) -> object:
    if not isinstance(value, dict):
        return value
    projected: dict[str, object] = {}
    for key, child in value.items():
        path = ".".join((*prefix, str(key)))
        if path in ALLOWED_METADATA_KEYS:
            continue
        projected[str(key)] = runtime_projection(child, (*prefix, str(key)))
    return projected


path = sys.argv[1]
head = subprocess.run(["git", "show", f"HEAD:{path}"], check=False, capture_output=True)
if head.returncode != 0:
    raise SystemExit(1)
try:
    with open(path, "rb") as handle:
        current = parse_toml(handle.read())
    previous = parse_toml(head.stdout)
except Exception:
    raise SystemExit(1)

raise SystemExit(0 if runtime_projection(current) == runtime_projection(previous) else 1)
PY
}

tb2_task_toml_runtime_fingerprint() {
  local file_path="$1"
  python3 - "$file_path" <<'PY'
from __future__ import annotations

import hashlib
import json
import sys
import tomllib

ALLOWED_METADATA_KEYS = {
    "metadata.author_name",
    "metadata.author_email",
    "metadata.category",
    "metadata.subcategories",
    "metadata.difficulty",
    "metadata.languages",
    "metadata.tags",
    "metadata.codebase_size",
}


def runtime_projection(value: object, prefix: tuple[str, ...] = ()) -> object:
    if not isinstance(value, dict):
        return value
    projected: dict[str, object] = {}
    for key, child in value.items():
        path = ".".join((*prefix, str(key)))
        if path in ALLOWED_METADATA_KEYS:
            continue
        projected[str(key)] = runtime_projection(child, (*prefix, str(key)))
    return projected


path = sys.argv[1]
with open(path, "rb") as handle:
    data = tomllib.load(handle)
payload = json.dumps(runtime_projection(data), sort_keys=True, separators=(",", ":")).encode()
print(f"{hashlib.sha256(payload).hexdigest()}  {path}::runtime-toml")
PY
}

tb2_emit_runtime_validation_baseline() {
  local task_rel="$1"
  git ls-files -co --exclude-standard -- "$task_rel" |
    while IFS= read -r file_path; do
      if ! tb2_is_fast_validation_path "$file_path" && ! tb2_is_task_toml_path "$file_path"; then
        printf '%s\0' "$file_path"
      fi
    done |
    xargs -0 -r sha256sum
  if [ -f "$task_rel/task.toml" ]; then
    tb2_task_toml_runtime_fingerprint "$task_rel/task.toml"
  fi
}
