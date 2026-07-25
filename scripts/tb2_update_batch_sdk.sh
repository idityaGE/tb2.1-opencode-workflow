#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib_tb2.sh
. "$SCRIPT_DIR/lib_tb2.sh"

repo_root="$(tb2_repo_root)"
cd "$repo_root"

tb2_invoked_from_kilo() {
  local pid comm args
  pid="${PPID:-}"
  while [ -n "$pid" ] && [ "$pid" != "0" ]; do
    comm="$(cat "/proc/$pid/comm" 2>/dev/null || true)"
    args="$(tr '\0' ' ' <"/proc/$pid/cmdline" 2>/dev/null || true)"
    case "${comm} ${args}" in
      *kilo*|*Kilo*|*kilocode*|*KiloCode*) return 0 ;;
    esac
    pid="$(awk '/^PPid:/ {print $2}' "/proc/$pid/status" 2>/dev/null || true)"
  done
  return 1
}

source_workflow_dir=".open""code"
kilo_workflow_dir=".ki""lo"
if [ "$(basename "$(dirname "$SCRIPT_DIR")")" = "$source_workflow_dir" ] && tb2_invoked_from_kilo; then
  kilo_scheduler="$repo_root/$kilo_workflow_dir/scripts/tb2_update_batch_sdk.sh"
  if [ -x "$kilo_scheduler" ]; then
    printf 'Detected Kilo runtime invoking the source workflow scheduler; redirecting to %s.\n' "$kilo_scheduler" >&2
    exec "$kilo_scheduler" "$@"
  fi
  tb2_die "detected Kilo runtime invoking the source workflow scheduler, but $kilo_scheduler is missing; sync the Kilo workflow before running /update-task"
fi

exec bun "$SCRIPT_DIR/tb2_update_batch_sdk.mjs" --repo-root "$repo_root" "$@"
