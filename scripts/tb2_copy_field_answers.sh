#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: tb2_copy_field_answers.sh --file FIELD_ANSWERS.md [--section HEADING]

Copies a field answer to the Wayland clipboard with wl-copy.
With --section, copies only that heading body.
Without --section, copies the full markdown file.
EOF
}

file=""
section=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --file) file="${2:-}"; shift 2 ;;
    --section) section="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) printf 'error: unknown argument: %s\n' "$1" >&2; exit 2 ;;
  esac
done

[ -n "$file" ] || { usage >&2; exit 2; }
[ -f "$file" ] || { printf 'error: file not found: %s\n' "$file" >&2; exit 1; }

if ! command -v wl-copy >/dev/null 2>&1; then
  printf 'error: wl-copy is not installed or not on PATH\n' >&2
  exit 1
fi

extract_section() {
  local heading="$1"
  awk -v raw="$heading" -v prefixed="## $heading" '
    $0 == raw || $0 == prefixed {capture=1; next}
    /^## / && capture {exit}
    capture {print}
  ' "$file"
}

copy_text() {
  local label="$1"
  local body="$2"
  if [ -z "$body" ]; then
    printf 'error: nothing to copy for: %s\n' "$label" >&2
    exit 1
  fi
  printf '%s' "$body" | wl-copy
  printf 'Copied "%s" to clipboard.\n' "$label"
}

if [ -n "$section" ]; then
  copy_text "$section" "$(extract_section "$section")"
else
  copy_text "$file" "$(cat "$file")"
fi
