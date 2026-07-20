#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib_tb2.sh
. "$SCRIPT_DIR/lib_tb2.sh"

usage() {
  cat <<'EOF'
Usage: tb2_task_state.sh --task TASK_DIR [--write-cache]

Prints a compact deterministic task state report for agents. The report covers
git-changed task files, validation scope, runtime baseline presence, key
task.toml metadata, and instruction word/paragraph counts. With --write-cache,
also saves the same report under .opencode/cache/tb2-state/.
EOF
}

task=""
write_cache=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --task) task="${2:-}"; shift 2 ;;
    --write-cache) write_cache=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) tb2_usage_error "unknown argument: $1" ;;
  esac
done

[ -n "$task" ] || tb2_usage_error "--task is required"
repo_root="$(tb2_repo_root)"
task_path="$(tb2_abs_path "$task")"
[ -d "$task_path" ] || tb2_die "task directory not found: $task_path"
task_rel="$(tb2_task_rel_path "$task_path")"
task_name="$(basename "$task_path")"
baseline_file="$repo_root/.opencode/cache/tb2-validation/$task_name.runtime.sha256"
state_cache_file="$repo_root/.opencode/cache/tb2-state/$task_name.txt"

cd "$repo_root"

emit_state() {
  printf 'task=%s\n' "$task_rel"
  printf 'baseline=%s\n' "$baseline_file"
  if [ -f "$baseline_file" ]; then
    printf 'baseline_status=present\n'
  else
    printf 'baseline_status=missing\n'
  fi

  printf '\n== validation scope ==\n'
  "$SCRIPT_DIR/tb2_validation_scope.sh" --task "$task_path"

  printf '\n== changed task files ==\n'
  status_output="$(git status --short -- "$task_rel")"
  if [ -z "$status_output" ]; then
    printf 'clean\n'
  else
    printf '%s\n' "$status_output" | while IFS= read -r line; do
      [ -n "$line" ] || continue
      file_path="${line#???}"
      if tb2_is_instruction_path "$file_path"; then
        kind="instruction"
      elif tb2_is_fast_validation_path "$file_path"; then
        kind="metadata"
      else
        kind="runtime"
      fi
      printf '%s [%s]\n' "$line" "$kind"
    done
  fi

  printf '\n== task metadata ==\n'
  if [ -f "$task_path/task.toml" ]; then
    if ! python3 "$SCRIPT_DIR/tb2_metadata.py" summary "$task_path"; then
      printf 'metadata_summary_status=failed\n'
    fi
  else
    printf 'missing task.toml\n'
  fi

  printf '\n== instruction stats ==\n'
  instruction_found=""
  if [ -f "$task_path/instruction.md" ]; then
    instruction_found=1
    python3 - "$repo_root" "$task_path/instruction.md" <<'PY'
from pathlib import Path
import re
import sys

root = Path(sys.argv[1])
path = Path(sys.argv[2])
text = path.read_text(errors="replace")
paragraphs = [part for part in re.split(r"\n\s*\n", text.strip()) if part.strip()]
print(f"{path.relative_to(root)}: words={len(text.split())} paragraphs={len(paragraphs)}")
PY
  fi
  for instruction_file in "$task_path"/steps/milestone_*/instruction.md; do
    [ -f "$instruction_file" ] || continue
    instruction_found=1
    python3 - "$repo_root" "$instruction_file" <<'PY'
from pathlib import Path
import re
import sys

root = Path(sys.argv[1])
path = Path(sys.argv[2])
text = path.read_text(errors="replace")
paragraphs = [part for part in re.split(r"\n\s*\n", text.strip()) if part.strip()]
print(f"{path.relative_to(root)}: words={len(text.split())} paragraphs={len(paragraphs)}")
PY
  done
  if [ -z "$instruction_found" ]; then
    printf 'no instruction.md found\n'
  fi
}

if [ -n "$write_cache" ]; then
  mkdir -p "$(dirname "$state_cache_file")"
  emit_state | tee "$state_cache_file"
  printf '\nstate_cache=%s\n' "$state_cache_file"
else
  emit_state
fi
