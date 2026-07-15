#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib_tb2.sh
. "$SCRIPT_DIR/lib_tb2.sh"

usage() {
  cat <<'EOF'
Usage: tb2_prepare_upload.sh --task TASK_DIR

Prepares a task directory for platform upload by writing the canonical
environment/.dockerignore and removing generated cache/archive clutter.
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
task_path="$(tb2_abs_path "$task")"
[ -d "$task_path" ] || tb2_die "task directory not found: $task_path"

env_dir="$task_path/environment"
mkdir -p "$env_dir"
dockerignore="$env_dir/.dockerignore"
tmp_file="$(mktemp "${TMPDIR:-/tmp}/tb2-dockerignore.XXXXXX")"
cat > "$tmp_file" <<'EOF'
**/__pycache__/
**/*.pyc
**/.pytest_cache/
solution/
tests/
EOF

dockerignore_status="unchanged"
if ! cmp -s "$tmp_file" "$dockerignore" 2>/dev/null; then
  mv "$tmp_file" "$dockerignore"
  dockerignore_status="updated"
else
  rm -f "$tmp_file"
fi

pycache_removed=0
while IFS= read -r -d '' cache_dir; do
  rm -rf "$cache_dir"
  pycache_removed=$((pycache_removed + 1))
done < <(find "$task_path" -type d -name __pycache__ -prune -print0)

zip_removed=0
while IFS= read -r -d '' zip_file; do
  rm -f "$zip_file"
  zip_removed=$((zip_removed + 1))
done < <(find "$task_path" -type f -name '*.zip' -print0)

printf 'Upload preparation completed for %s\n' "$task_path"
printf 'environment/.dockerignore: %s\n' "$dockerignore_status"
printf 'removed __pycache__ directories: %s\n' "$pycache_removed"
printf 'removed .zip files: %s\n' "$zip_removed"
