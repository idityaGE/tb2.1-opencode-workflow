#!/usr/bin/env python3
"""Track addressed reviewer notes and pending platform rubric handoffs."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import tempfile
from datetime import datetime, timezone
from pathlib import Path

DIVIDER_RE = re.compile(r"^-{5,}$")
AUTOEVAL_RE = re.compile(
    r"^AutoEval Execution Summary:\s*AutoEval execution failed\.", re.IGNORECASE
)
UUID_RE = re.compile(r"^[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$")


def repo_root() -> Path:
    for candidate in [Path.cwd(), *Path(__file__).resolve().parents]:
        if (candidate / "tasks").is_dir() and (candidate / ".opencode").is_dir():
            return candidate
    raise SystemExit("error: could not locate repository root")


def state_path(submission_id: str, state_root: Path | None) -> Path:
    root = state_root or repo_root() / ".tb2-cache/tb2-updates"
    root.mkdir(parents=True, exist_ok=True)
    return root / f"{submission_id}.json"


def load_state(path: Path, submission_id: str) -> dict:
    if not path.exists():
        return {"submission_id": submission_id, "addressed_revision_notes": []}
    data = json.loads(path.read_text())
    data.setdefault("submission_id", submission_id)
    data.setdefault("addressed_revision_notes", [])
    return data


def save_state(path: Path, data: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile("w", dir=path.parent, delete=False) as handle:
        json.dump(data, handle, indent=2, sort_keys=True)
        handle.write("\n")
        temp_path = Path(handle.name)
    temp_path.replace(path)


def revision_notes(notes_file: Path | None) -> str:
    if notes_file is None or not notes_file.is_file():
        return ""
    lines = notes_file.read_text(errors="replace").splitlines()
    collecting = False
    kept: list[str] = []
    for line in lines:
        stripped = line.strip()
        if not collecting:
            if stripped.casefold() == "revision notes":
                collecting = True
            continue
        if stripped.casefold() in {"summary (difficulty check)", "quality check summary"}:
            break
        if not stripped or DIVIDER_RE.fullmatch(stripped) or AUTOEVAL_RE.match(stripped):
            continue
        kept.append(stripped)
    return " ".join(" ".join(kept).split())


def notes_hash(notes: str) -> str | None:
    if not notes:
        return None
    return hashlib.sha256(notes.encode()).hexdigest()


def validate_submission_id(value: str) -> str:
    if not UUID_RE.fullmatch(value):
        raise argparse.ArgumentTypeError("submission ID must be a UUID")
    return value.lower()


def inspect(args: argparse.Namespace) -> int:
    path = state_path(args.submission_id, args.state_root)
    state = load_state(path, args.submission_id)
    notes = revision_notes(args.notes_file)
    digest = notes_hash(notes)
    addressed = {item.get("hash") for item in state["addressed_revision_notes"]}
    status = "none" if digest is None else "addressed" if digest in addressed else "new"
    print(
        json.dumps(
            {
                "revision_notes_status": status,
                "revision_notes_hash": digest,
                "rubric_pending": bool(state.get("rubric_pending")),
                "rubric_file": state.get("rubric_file"),
                "state_file": str(path),
            },
            sort_keys=True,
        )
    )
    return 0


def record_notes(args: argparse.Namespace) -> int:
    notes = revision_notes(args.notes_file)
    digest = notes_hash(notes)
    if digest is None:
        print("revision_notes_status=none")
        return 0
    path = state_path(args.submission_id, args.state_root)
    state = load_state(path, args.submission_id)
    records = state["addressed_revision_notes"]
    if not any(item.get("hash") == digest for item in records):
        records.append(
            {
                "hash": digest,
                "recorded_at": datetime.now(timezone.utc).isoformat(),
                "upload_mode": args.upload_mode,
                "task": args.task,
            }
        )
        save_state(path, state)
    print(f"revision_notes_status=addressed\nrevision_notes_hash={digest}\nstate_file={path}")
    return 0


def mark_rubric(args: argparse.Namespace) -> int:
    path = state_path(args.submission_id, args.state_root)
    state = load_state(path, args.submission_id)
    state["rubric_pending"] = True
    state["rubric_file"] = str(args.rubric_file)
    state["rubric_marked_at"] = datetime.now(timezone.utc).isoformat()
    save_state(path, state)
    print(f"rubric_pending=true\nrubric_file={args.rubric_file}\nstate_file={path}")
    return 0


def clear_rubric(args: argparse.Namespace) -> int:
    path = state_path(args.submission_id, args.state_root)
    state = load_state(path, args.submission_id)
    state["rubric_pending"] = False
    state["rubric_cleared_at"] = datetime.now(timezone.utc).isoformat()
    save_state(path, state)
    print(f"rubric_pending=false\nstate_file={path}")
    return 0


def common_parser(subparser: argparse.ArgumentParser) -> None:
    subparser.add_argument("--submission-id", required=True, type=validate_submission_id)
    subparser.add_argument("--state-root", type=Path)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)

    inspect_parser = commands.add_parser("inspect")
    common_parser(inspect_parser)
    inspect_parser.add_argument("--notes-file", type=Path)
    inspect_parser.set_defaults(func=inspect)

    record_parser = commands.add_parser("record-notes")
    common_parser(record_parser)
    record_parser.add_argument("--notes-file", required=True, type=Path)
    record_parser.add_argument("--upload-mode", required=True, choices=("checks", "reviewer"))
    record_parser.add_argument("--task")
    record_parser.set_defaults(func=record_notes)

    mark_parser = commands.add_parser("mark-rubric")
    common_parser(mark_parser)
    mark_parser.add_argument("--rubric-file", required=True, type=Path)
    mark_parser.set_defaults(func=mark_rubric)

    clear_parser = commands.add_parser("clear-rubric")
    common_parser(clear_parser)
    clear_parser.set_defaults(func=clear_rubric)
    return parser


def main() -> int:
    args = build_parser().parse_args()
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
