#!/usr/bin/env python3
"""Summarize fetched stb feedback/log files."""

from __future__ import annotations

import re
import sys
from pathlib import Path


PATTERNS = {
    "blocking_failure": re.compile(r"\b(FAIL|FAILED|ERROR|NEEDS_REVISION|REJECTED)\b", re.I),
    "oracle": re.compile(r"\boracle\b", re.I),
    "nop": re.compile(r"\bnop\b|no operation", re.I),
    "llmaj": re.compile(r"\bLLMaJ\b|behavior_in_|anti_cheating|hardcoded_solution", re.I),
    "ci": re.compile(r"check_|ruff|pinned|dockerfile|reward\.txt", re.I),
    "agent": re.compile(r"gpt|claude|agent|terminus", re.I),
}


def iter_text_files(root: Path):
    for path in sorted(root.rglob("*")):
        if path.is_file() and path.stat().st_size <= 2_000_000:
            try:
                yield path, path.read_text(errors="replace")
            except OSError:
                continue


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print("Usage: tb2_quality_report.py FEEDBACK_DIR", file=sys.stderr)
        return 2

    root = Path(argv[1])
    print(f"# Feedback Summary: {root}")
    if not root.exists():
        print("Feedback directory does not exist.")
        return 1

    hits: dict[str, list[str]] = {name: [] for name in PATTERNS}
    for path, text in iter_text_files(root):
        rel = path.relative_to(root)
        for name, pattern in PATTERNS.items():
            if pattern.search(text):
                hits[name].append(str(rel))

    for name, files in hits.items():
        print(f"\n## {name}")
        if not files:
            print("No obvious matches.")
            continue
        for item in files[:20]:
            print(f"- {item}")
        if len(files) > 20:
            print(f"- ... {len(files) - 20} more")

    print("\n## Next Actions")
    print("- Read only feedback files that exist; otherwise use tb2_status_iterate.sh stdout/stderr.")
    print("- Fix only concrete issues tied to feedback.")
    print("- Use tb2_task_state.sh and the local workflow profile to run the applicable revision validation.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
