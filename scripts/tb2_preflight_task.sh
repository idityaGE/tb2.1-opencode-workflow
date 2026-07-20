#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib_tb2.sh
. "$SCRIPT_DIR/lib_tb2.sh"

usage() {
  cat <<'EOF'
Usage: tb2_preflight_task.sh --task TASK_DIR [--context create|revision]

Runs fast local checks only: structural lint and ruff when installed.
Does not run NOP or oracle.
EOF
}

task=""
context="revision"
while [ "$#" -gt 0 ]; do
  case "$1" in
    --task) task="${2:-}"; shift 2 ;;
    --context) context="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) tb2_usage_error "unknown argument: $1" ;;
  esac
done

[ -n "$task" ] || tb2_usage_error "--task is required"
case "$context" in create|revision) ;; *) tb2_usage_error "--context must be create or revision" ;; esac
repo_root="$(tb2_repo_root)"
task_path="$(tb2_abs_path "$task")"
[ -d "$task_path" ] || tb2_die "task directory not found: $task_path"

cd "$repo_root"

printf '== Upload preparation ==\n'
"$SCRIPT_DIR/tb2_prepare_upload.sh" --task "$task_path"

printf '== Fast structural lint ==\n'
python3 "$SCRIPT_DIR/tb2_task_lint.py" --context "$context" "$task_path"

printf '\n== Fast ruff check ==\n'
if command -v ruff >/dev/null 2>&1; then
  ruff_paths=("$SCRIPT_DIR")
  [ -d "$task_path/tests" ] && ruff_paths+=("$task_path/tests")
  [ -d "$task_path/steps" ] && ruff_paths+=("$task_path/steps")
  ruff check "${ruff_paths[@]}"
else
  printf 'ruff not installed; skipping ruff check\n'
fi

printf '\nPreflight completed for %s\n' "$task_path"
