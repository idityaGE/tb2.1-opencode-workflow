#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib_tb2.sh
. "$SCRIPT_DIR/lib_tb2.sh"

usage() {
  cat <<'EOF'
Usage: tb2_duplicate_scan.sh --query TEXT [--limit N]

Prints a compact near-duplicate scan from task folder names, task.toml metadata,
and the first paragraph of instruction.md. This is a speed helper, not a final
novelty guarantee.
EOF
}

query=""
limit="25"
while [ "$#" -gt 0 ]; do
  case "$1" in
    --query) query="${2:-}"; shift 2 ;;
    --limit) limit="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) tb2_usage_error "unknown argument: $1" ;;
  esac
done

[ -n "$query" ] || tb2_usage_error "--query is required"
case "$limit" in *[!0-9]*|"") tb2_usage_error "--limit must be a positive integer" ;; esac
[ "$limit" -gt 0 ] || tb2_usage_error "--limit must be a positive integer"

repo_root="$(tb2_repo_root)"
cd "$repo_root"

query_lc="$(printf '%s\n' "$query" | tr '[:upper:]' '[:lower:]')"
printed=0
matches_file="$(mktemp)"
trap 'rm -f "$matches_file"' EXIT

printf 'Duplicate scan query: %s\n\n' "$query"
for task_dir in tasks/*; do
  [ -d "$task_dir" ] || continue
  task_name="${task_dir#tasks/}"
  task_lc="$(printf '%s\n' "$task_name" | tr '[:upper:]' '[:lower:]')"
  meta=""
  [ -f "$task_dir/task.toml" ] && meta="$(grep -E '^(category|subcategories|languages|tags|difficulty)\b' "$task_dir/task.toml" 2>/dev/null || true)"
  first_para=""
  if [ -f "$task_dir/instruction.md" ]; then
    first_para="$(awk 'NF {print; seen=1; next} seen {exit}' "$task_dir/instruction.md")"
  fi
  haystack="$(printf '%s\n%s\n%s\n' "$task_lc" "$meta" "$first_para" | tr '[:upper:]' '[:lower:]')"
  score=0
  for word in $query_lc; do
    clean="$(printf '%s' "$word" | tr -cd 'a-z0-9-')"
    [ "${#clean}" -ge 3 ] || continue
    case "$haystack" in *"$clean"*) score=$((score + 1)) ;; esac
  done
  [ "$score" -gt 0 ] || continue
  printf '%s %s\n' "$score" "$task_dir" >> "$matches_file"
done

while IFS=' ' read -r score task_dir; do
  [ -n "${score:-}" ] || continue
  printed=$((printed + 1))
  task_name="${task_dir#tasks/}"
  meta=""
  [ -f "$task_dir/task.toml" ] && meta="$(grep -E '^(category|subcategories|languages|tags|difficulty)\b' "$task_dir/task.toml" 2>/dev/null || true)"
  first_para=""
  if [ -f "$task_dir/instruction.md" ]; then
    first_para="$(awk 'NF {print; seen=1; next} seen {exit}' "$task_dir/instruction.md")"
  fi
  printf '== %s (score %s) ==\n' "$task_name" "$score"
  [ -n "$meta" ] && printf '%s\n' "$meta"
  [ -n "$first_para" ] && printf 'instruction: %s\n' "$first_para"
  printf '\n'
  [ "$printed" -ge "$limit" ] && break
done < <(sort -k1,1nr -k2,2 "$matches_file")

if [ "$printed" -eq 0 ]; then
  printf 'No obvious local matches from folder names, task.toml metadata, or first instruction paragraph.\n'
fi
