#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib_tb2.sh
. "$SCRIPT_DIR/lib_tb2.sh"

usage() {
  cat <<'USAGE'
Usage: tb2_sync_kilo_workflow.sh [--no-validate]

Rebuild .kilo from the current .opencode workflow mirror.

What it does:
  - copies .opencode to .kilo, including cache and node_modules
  - excludes .opencode/.git and this sync helper from the .kilo copy
  - rewrites copied workflow text from opencode/.opencode to kilo/.kilo
  - switches SDK imports from @opencode-ai/sdk/createOpencode to @kilocode/sdk/createKilo
  - normalizes .kilo package metadata to Kilo package names/versions
  - validates the generated Kilo workflow unless --no-validate is supplied
USAGE
}

validate=1
while [ "$#" -gt 0 ]; do
  case "$1" in
    --no-validate) validate=0 ;;
    -h|--help) usage; exit 0 ;;
    *) tb2_usage_error "unknown argument: $1" ;;
  esac
  shift
done

repo_root="$(tb2_repo_root)"
source_dir="$repo_root/.opencode"
target_dir="$repo_root/.kilo"

[ -d "$source_dir" ] || tb2_die "missing source workflow directory: $source_dir"
command -v python3 >/dev/null 2>&1 || tb2_die "python3 is required"
command -v cp >/dev/null 2>&1 || tb2_die "cp is required"
command -v mktemp >/dev/null 2>&1 || tb2_die "mktemp is required"

tmp_parent="$(mktemp -d "$repo_root/.kilo-sync.XXXXXX")"
staging="$tmp_parent/.kilo"
backup=""

cleanup() {
  rm -rf "$tmp_parent"
  if [ -n "$backup" ] && [ -d "$backup" ] && [ ! -d "$target_dir" ]; then
    mv "$backup" "$target_dir"
  fi
}
trap cleanup EXIT

cp -a "$source_dir" "$staging"
rm -rf "$staging/.git"
rm -f "$staging/scripts/tb2_sync_kilo_workflow.sh"

python3 - "$staging" "$source_dir" <<'PY'
from __future__ import annotations

import json
import sys
from pathlib import Path

target = Path(sys.argv[1])
source = Path(sys.argv[2])


def package_version(package_name: str, fallback: str) -> str:
    package_path = source / "node_modules" / package_name / "package.json"
    if package_path.exists():
        try:
            return json.loads(package_path.read_text(encoding="utf-8"))["version"]
        except Exception:
            pass
    source_package = source / "package.json"
    if source_package.exists():
        try:
            deps = json.loads(source_package.read_text(encoding="utf-8")).get("dependencies", {})
            return deps.get(package_name, fallback)
        except Exception:
            pass
    return fallback


replacements = [
    ("@opencode-ai/sdk", "@kilocode/sdk"),
    ("@opencode-ai/plugin", "@kilocode/plugin"),
    ("createOpencodeClient", "createKiloClient"),
    ("createOpencodeServer", "createKiloServer"),
    ("createOpencode", "createKilo"),
    ("OpenCode", "Kilo Code"),
    ("opencode", "kilo"),
    ("OPENCODE", "KILO"),
]

for path in target.rglob("*"):
    if not path.is_file() or "node_modules" in path.parts:
        continue
    try:
        text = path.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        continue
    rewritten = text
    for old, new in replacements:
        rewritten = rewritten.replace(old, new)
    if rewritten != text:
        path.write_text(rewritten, encoding="utf-8")

package_json = target / "package.json"
if package_json.exists():
    package = json.loads(package_json.read_text(encoding="utf-8"))
    deps = package.setdefault("dependencies", {})
    deps.pop("@opencode-ai/sdk", None)
    deps.pop("@opencode-ai/plugin", None)
    deps["@kilocode/plugin"] = package_version("@kilocode/plugin", "7.3.40")
    deps["@kilocode/sdk"] = package_version("@kilocode/sdk", deps["@kilocode/plugin"])
    package_json.write_text(json.dumps(package, indent=2) + "\n", encoding="utf-8")
PY

if command -v npm >/dev/null 2>&1 && [ -f "$staging/package.json" ]; then
  (cd "$staging" && npm install --package-lock-only --ignore-scripts --silent)
fi

if [ -e "$target_dir" ]; then
  backup="$repo_root/.kilo.backup.$$"
  mv "$target_dir" "$backup"
fi
mv "$staging" "$target_dir"
rm -rf "$backup"
backup=""

if [ "$validate" -eq 1 ]; then
  node --check "$target_dir/scripts/tb2_update_batch_sdk.mjs"
  bash -n "$target_dir"/scripts/*.sh
  python3 -m py_compile "$target_dir"/scripts/*.py
  if compgen -G "$target_dir/plugins/*.ts" >/dev/null && command -v bun >/dev/null 2>&1; then
    bun --check "$target_dir"/plugins/*.ts
  fi
  if command -v kilo >/dev/null 2>&1; then
    (cd "$repo_root" && kilo agent list >/dev/null)
  else
    printf 'warning: kilo CLI not found; skipped kilo agent list\n' >&2
  fi
fi

printf 'Synced .opencode -> .kilo with Kilo SDK/workflow rewrites.\n'
