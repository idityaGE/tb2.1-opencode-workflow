#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib_tb2.sh
. "$SCRIPT_DIR/lib_tb2.sh"

usage() {
  cat <<'EOF'
Usage: tb2_validate_task.sh --task TASK_DIR

Runs structural lint, ruff, NOP, and oracle checks. NOP must earn reward 0 and
oracle must earn reward 1. On success, records a small runtime validation
baseline used by update-task to avoid repeated full runs after instruction.md or
metadata-only task.toml edits.
EOF
}

run_harbor_eval() {
  local agent="$1"
  local out_file harbor_rc result_path metrics

  out_file="$(mktemp "${TMPDIR:-/tmp}/tb2-harbor-${agent}.XXXXXX")"
  set +e
  harbor run -a "$agent" -p "$task_path" 2>&1 | tee "$out_file"
  harbor_rc=${PIPESTATUS[0]}
  set -e

  result_path="$(python3 - "$out_file" <<'PY'
import re
import sys

path = sys.argv[1]
with open(path, encoding="utf-8", errors="replace") as handle:
    lines = handle.readlines()
for line in reversed(lines):
    match = re.search(r"Results written to\s+(\S+)", line)
    if match:
        print(match.group(1))
        break
PY
)"
  rm -f "$out_file"

  [ -n "$result_path" ] || tb2_die "could not locate harbor result JSON for $agent check"
  case "$result_path" in
    /*) ;;
    *) result_path="$repo_root/$result_path" ;;
  esac
  [ -f "$result_path" ] || tb2_die "harbor result JSON not found for $agent check: $result_path"

  metrics="$(python3 - "$result_path" "$agent" <<'PY'
import json
import sys

path, agent = sys.argv[1], sys.argv[2]
with open(path, encoding="utf-8") as handle:
    data = json.load(handle)
evals = data.get("stats", {}).get("evals", {})
matches = [value for key, value in evals.items() if key.startswith(f"{agent}__")]
if len(matches) != 1:
    raise SystemExit(f"expected one {agent} eval, found {len(matches)}")
entry = matches[0]
metric_list = entry.get("metrics") or []
if not metric_list or "mean" not in metric_list[0]:
    raise SystemExit(f"missing mean reward for {agent}")
print(f"{metric_list[0]['mean']} {entry.get('n_errors', 0)}")
PY
)" || tb2_die "could not read reward metrics from harbor result JSON for $agent check: $result_path"

  HARBOR_EVAL_RC="$harbor_rc"
  HARBOR_EVAL_RESULT="$result_path"
  HARBOR_EVAL_MEAN="${metrics%% *}"
  HARBOR_EVAL_ERRORS="${metrics##* }"
}

reward_is() {
  local actual="$1"
  local expected="$2"
  python3 - "$actual" "$expected" <<'PY'
import math
import sys

actual = float(sys.argv[1])
expected = float(sys.argv[2])
raise SystemExit(0 if math.isclose(actual, expected, rel_tol=0.0, abs_tol=1e-9) else 1)
PY
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

cd "$repo_root"

printf '== Upload preparation ==\n'
"$SCRIPT_DIR/tb2_prepare_upload.sh" --task "$task_path"

printf '== Structural lint ==\n'
python3 "$SCRIPT_DIR/tb2_task_lint.py" "$task_path"

printf '\n== Ruff verifier/helper check ==\n'
if command -v ruff >/dev/null 2>&1; then
  ruff_paths=("$SCRIPT_DIR")
  [ -d "$task_path/tests" ] && ruff_paths+=("$task_path/tests")
  [ -d "$task_path/steps" ] && ruff_paths+=("$task_path/steps")
  ruff check "${ruff_paths[@]}"
else
  printf 'ruff not installed; skipping ruff check\n'
fi

printf '\n== NOP agent check ==\n'
run_harbor_eval nop
if [ "$HARBOR_EVAL_ERRORS" -ne 0 ]; then
  tb2_die "NOP agent check errored; see $HARBOR_EVAL_RESULT"
fi
if ! reward_is "$HARBOR_EVAL_MEAN" 0; then
  tb2_die "NOP agent unexpectedly achieved reward $HARBOR_EVAL_MEAN; the baseline agent must earn 0"
fi
printf 'NOP failed as required.\n'

printf '\n== Oracle check ==\n'
run_harbor_eval oracle
if [ "$HARBOR_EVAL_RC" -ne 0 ]; then
  tb2_die "oracle check command failed; see $HARBOR_EVAL_RESULT"
fi
if [ "$HARBOR_EVAL_ERRORS" -ne 0 ]; then
  tb2_die "oracle check errored; see $HARBOR_EVAL_RESULT"
fi
if ! reward_is "$HARBOR_EVAL_MEAN" 1; then
  tb2_die "oracle achieved reward $HARBOR_EVAL_MEAN; expected 1"
fi

baseline_dir="$repo_root/.opencode/cache/tb2-validation"
mkdir -p "$baseline_dir"
task_rel="$(tb2_task_rel_path "$task_path")"
baseline_file="$baseline_dir/$(basename "$task_path").runtime.sha256"
tb2_emit_runtime_validation_baseline "$task_rel" > "$baseline_file"

printf '\nValidation completed for %s\n' "$task_path"
printf 'Validation baseline: %s\n' "$baseline_file"
