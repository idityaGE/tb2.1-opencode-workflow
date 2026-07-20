#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib_tb2.sh
. "$SCRIPT_DIR/lib_tb2.sh"

usage() {
  cat <<'EOF'
Usage: tb2_create_task.sh --task TASK_NAME [--template default|ui]

Creates a TB2 task skeleton under tasks/TASK_NAME with stb init.
Installs the workflow's canonical tests/test.sh template after initialization.
EOF
}

task_name=""
template="default"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --task) task_name="${2:-}"; shift 2 ;;
    --template) template="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) tb2_usage_error "unknown argument: $1" ;;
  esac
done

[ -n "$task_name" ] || tb2_usage_error "--task is required"
case "$task_name" in
  *[!a-z0-9-]*|""|-*) tb2_die "task name must be lower-case kebab-case" ;;
esac
case "$template" in
  default|regular) template="default" ;;
  ui) ;;
  milestone) tb2_die "milestone templates are disabled; task.toml must use number_of_milestones = 0" ;;
  *) tb2_die "template must be default or ui" ;;
esac

repo_root="$(tb2_repo_root)"
task_dir="$repo_root/tasks/$task_name"

if [ -e "$task_dir" ]; then
  tb2_die "$task_dir already exists; choose a new task name or edit the existing task intentionally"
fi

cd "$repo_root"
stb init "tasks/$task_name" -p "$TB2_PROJECT_ID" -t "$template"
mkdir -p "$task_dir/tests"
install -m 0755 "$SCRIPT_DIR/../templates/tests/test.sh" "$task_dir/tests/test.sh"

printf '\nCreated %s\n' "$task_dir"
printf 'Applied profile: .opencode/docs/local/workflow-profile.md\n'
printf 'Next: author the task, then run:\n'
printf '  .opencode/scripts/tb2_validate_task.sh --context create --task tasks/%s\n' "$task_name"
