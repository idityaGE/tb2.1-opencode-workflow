#!/usr/bin/env python3
"""Extract TB2 feedback facts and persist revision/upload history atomically."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import tempfile
import uuid
from datetime import datetime, timedelta, timezone
from pathlib import Path

STATE_VERSION = 2
DEFAULT_COOLDOWN_SECONDS = 900
DIVIDER_RE = re.compile(r"^-{5,}$")
AUTOEVAL_RE = re.compile(
    r"^AutoEval Execution Summary:\s*AutoEval execution failed\.\s*Build status:\s*FAILED(?:\.\.\.|.*)?$",
    re.IGNORECASE,
)
UUID_RE = re.compile(r"^[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$")
LOW_DIFFICULTIES = {"EASY", "TRIVIAL"}
QUALITY_OUTCOME_RE = re.compile(
    r"^\s*(?:[-*]\s*)?([^:\n]+?):\s*(PASS|FAIL|FAILED|NOT_APPLICABLE|NOT APPLICABLE|N/?A)\b",
    re.IGNORECASE,
)
TEST_COUNT_RE = re.compile(r"^\s*(?:[-*]\s*)?([^:\n]+?):\s*(\d+)\s*/\s*(\d+)\b")
EXCLUDED_NAMES = {".snorkel_config", ".DS_Store"}
EXCLUDED_PARTS = {"__pycache__", ".pytest_cache", ".ruff_cache", ".git"}
EXCLUDED_SUFFIXES = {".pyc", ".pyo", ".zip", ".tmp", ".temp", ".swp"}
NON_SOURCE_DOCS = {"readme.md", "spec.md", "rule.md", "instruction.md"}


def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def parse_time(value: str | None) -> datetime | None:
    if not value:
        return None
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
        return parsed if parsed.tzinfo else parsed.replace(tzinfo=timezone.utc)
    except ValueError:
        return None


def repo_root() -> Path:
    for candidate in [Path.cwd(), *Path(__file__).resolve().parents]:
        if (candidate / "tasks").is_dir() and (candidate / ".opencode").is_dir():
            return candidate
    raise SystemExit("error: could not locate repository root")


def state_path(submission_id: str, state_root: Path | None) -> Path:
    root = state_root or repo_root() / ".tb2-cache/tb2-updates"
    root.mkdir(parents=True, exist_ok=True)
    return root / f"{submission_id}.json"


def new_state(submission_id: str) -> dict:
    return {
        "version": STATE_VERSION,
        "submission_id": submission_id,
        "task": None,
        "reviewer_cycle": 1,
        "rubric_pending": False,
        "addressed_revision_notes": [],
        "iterations": [],
    }


def migrate_state(data: dict, submission_id: str) -> tuple[dict, bool]:
    changed = data.get("version") != STATE_VERSION
    data.setdefault("submission_id", submission_id)
    data.setdefault("task", None)
    data.setdefault("reviewer_cycle", 1)
    data.setdefault("rubric_pending", False)
    data.setdefault("addressed_revision_notes", [])
    data.setdefault("iterations", [])
    for record in data["addressed_revision_notes"]:
        if "reviewer_cycle" not in record:
            record["reviewer_cycle"] = data["reviewer_cycle"]
            changed = True
        record.setdefault("task_fingerprint", None)
        record.setdefault("checks_submitted_at", record.get("recorded_at"))
    data["version"] = STATE_VERSION
    return data, changed


def load_state(path: Path, submission_id: str) -> dict:
    if not path.exists():
        return new_state(submission_id)
    data = json.loads(path.read_text(encoding="utf-8"))
    state, changed = migrate_state(data, submission_id)
    if changed:
        save_state(path, state)
    return state


def save_state(path: Path, data: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(
        "w", encoding="utf-8", dir=path.parent, delete=False
    ) as handle:
        json.dump(data, handle, indent=2, sort_keys=True)
        handle.write("\n")
        handle.flush()
        os.fsync(handle.fileno())
        temp_path = Path(handle.name)
    temp_path.replace(path)


def is_autoeval_noise(line: str) -> bool:
    return bool(AUTOEVAL_RE.fullmatch(line.strip()))


def normalized_revision_notes(text_or_path: str | Path | None) -> str:
    if text_or_path is None:
        return ""
    if isinstance(text_or_path, Path):
        if not text_or_path.is_file():
            return ""
        text = text_or_path.read_text(encoding="utf-8", errors="replace")
    else:
        text = text_or_path
    collecting = False
    kept: list[str] = []
    for line in text.splitlines():
        stripped = line.strip()
        heading = stripped.casefold().strip("# :")
        if not collecting:
            if heading == "revision notes":
                collecting = True
            continue
        if (
            heading.startswith("summary (difficulty check)")
            or heading.startswith("difficulty check")
            or heading.startswith("quality check")
            or heading.startswith("task quality")
        ):
            break
        if (
            not stripped
            or DIVIDER_RE.fullmatch(stripped)
            or is_autoeval_noise(stripped)
        ):
            continue
        kept.append(stripped)
    return " ".join(" ".join(kept).split())


def notes_hash(notes: str) -> str | None:
    return hashlib.sha256(notes.encode()).hexdigest() if notes else None


def feedback_texts(feedback_dir: Path) -> dict[str, str]:
    candidates = [
        feedback_dir / "notes.txt",
        feedback_dir / "agent_review.txt",
        feedback_dir / "agent_logs/summary-of-runs-comment.md",
    ]
    texts: dict[str, str] = {}
    for candidate in candidates:
        if candidate.is_file():
            texts[str(candidate.relative_to(feedback_dir))] = candidate.read_text(
                encoding="utf-8", errors="replace"
            )
    return texts


def extract_difficulty(text: str) -> str | None:
    patterns = [
        r"\b(?:task\s+)?difficulty\s*(?:rating|result|status)?\s*[:=-]\s*(TRIVIAL|EASY|MEDIUM|HARD)\b",
        r"\b(?:rated|classified)\s+(?:as\s+)?(TRIVIAL|EASY|MEDIUM|HARD)\b",
    ]
    for pattern in patterns:
        match = re.search(pattern, text, re.IGNORECASE)
        if match:
            return match.group(1).upper()
    return None


def extract_solvability(text: str) -> str | None:
    match = re.search(
        r"\b(?:solvability|solvable\s+status|task\s+status)\s*[:=-]\s*(NOT[_ -]?SOLVABLE|UNSOLVABLE|SOLVABLE)\b",
        text,
        re.IGNORECASE,
    )
    if match:
        value = match.group(1).upper().replace(" ", "_").replace("-", "_")
        return "NOT_SOLVABLE" if value == "UNSOLVABLE" else value
    if re.search(r"\bnon-solvable\b|\bnot solvable\b", text, re.IGNORECASE):
        return "NOT_SOLVABLE"
    return None


def section_lines(text: str, heading_pattern: str) -> list[str]:
    lines = text.splitlines()
    collecting = False
    kept: list[str] = []
    for line in lines:
        stripped = line.strip()
        if not collecting:
            if re.search(heading_pattern, stripped, re.IGNORECASE):
                collecting = True
            continue
        if stripped.startswith("#") and kept:
            break
        if re.match(r"^[A-Z][A-Za-z ()/-]+:$", stripped) and kept:
            break
        kept.append(line)
    return kept


def extract_test_counts(text: str) -> tuple[dict[str, str], list[str]]:
    counts: dict[str, str] = {}
    zero: list[str] = []
    for line in text.splitlines():
        match = TEST_COUNT_RE.match(line)
        if not match:
            continue
        name = " ".join(match.group(1).split()).strip("-* ")
        if re.search(r"quality|instruction sufficiency|claude|gpt", name, re.I):
            continue
        passed, total = int(match.group(2)), int(match.group(3))
        if total <= 0:
            continue
        counts[name] = f"{passed}/{total}"
        if passed == 0:
            zero.append(name)
    return counts, sorted(set(zero))


def extract_quality(text: str) -> tuple[dict[str, str], list[str], str | None]:
    lines = section_lines(text, r"quality(?:\s+check)?(?:\s+summary|\s+results)?")
    outcomes: dict[str, str] = {}
    for line in lines:
        match = QUALITY_OUTCOME_RE.match(line)
        if not match:
            continue
        name = " ".join(match.group(1).split()).strip("-* ")
        value = match.group(2).upper().replace(" ", "_").replace("FAILED", "FAIL")
        value = "NOT_APPLICABLE" if value in {"N/A", "NA", "NOT_APPLICABLE"} else value
        outcomes[name] = value
    instruction_key = next(
        (
            name
            for name in outcomes
            if name.casefold() == "task instruction sufficiency"
        ),
        None,
    )
    instruction = outcomes.get(instruction_key) if instruction_key else None
    failures = sorted(
        name
        for name, value in outcomes.items()
        if value == "FAIL" and name.casefold() != "task instruction sufficiency"
    )
    return outcomes, failures, instruction


def extract_agent_performance(text: str) -> dict[str, str]:
    performance: dict[str, str] = {}
    for agent in ("claude", "gpt"):
        match = re.search(rf"\b{agent}\b[^\n:]*[:=-]\s*(\d+)\s*/\s*(\d+)", text, re.I)
        if match:
            performance[agent] = f"{match.group(1)}/{match.group(2)}"
    return performance


def extract_feedback(feedback_dir: Path) -> dict:
    texts = feedback_texts(feedback_dir)
    combined = "\n".join(texts.values())
    filtered = "\n".join(
        line for line in combined.splitlines() if not is_autoeval_noise(line)
    )
    notes_text = texts.get("notes.txt", "")
    normalized_notes = normalized_revision_notes(notes_text)
    difficulty = extract_difficulty(filtered)
    solvability = extract_solvability(filtered)
    test_counts, zero_pass_tests = extract_test_counts(filtered)
    quality_outcomes, quality_failures, instruction = extract_quality(filtered)
    facts = {
        "revision_notes": normalized_notes,
        "revision_notes_hash": notes_hash(normalized_notes),
        "difficulty": difficulty,
        "solvability": solvability,
        "frontier_test_pass_counts": test_counts,
        "zero_pass_tests": zero_pass_tests,
        "quality_outcomes": quality_outcomes,
        "quality_failures": quality_failures,
        "instruction_sufficiency": instruction,
        "agent_performance": extract_agent_performance(filtered),
        "source_files": sorted(texts),
    }
    complete_evaluation = bool(
        difficulty and solvability and test_counts and quality_outcomes
    )
    facts["feedback_complete"] = bool(normalized_notes or complete_evaluation)
    facts["feedback_details"] = (
        "complete" if facts["feedback_complete"] else "incomplete"
    )
    fingerprint_payload = {
        key: value
        for key, value in facts.items()
        if key not in {"feedback_complete", "feedback_details"}
    }
    facts["fingerprint"] = hashlib.sha256(
        json.dumps(fingerprint_payload, sort_keys=True, separators=(",", ":")).encode()
    ).hexdigest()
    return facts


def task_files(task: Path):
    for candidate in sorted(task.rglob("*"), key=lambda item: item.as_posix()):
        if not candidate.is_file():
            continue
        relative = candidate.relative_to(task)
        if candidate.name in EXCLUDED_NAMES or any(
            part in EXCLUDED_PARTS for part in relative.parts
        ):
            continue
        if candidate.suffix.casefold() in EXCLUDED_SUFFIXES or candidate.name.endswith(
            "~"
        ):
            continue
        yield candidate, relative


def task_fingerprint(task: Path) -> str:
    if not task.is_dir():
        raise ValueError(f"task directory not found: {task}")
    digest = hashlib.sha256()
    for candidate, relative in task_files(task):
        digest.update(relative.as_posix().encode())
        digest.update(b"\0")
        digest.update(candidate.read_bytes())
        digest.update(b"\0")
    return digest.hexdigest()


def task_manifest(task: Path) -> dict[str, str]:
    return {
        relative.as_posix(): hashlib.sha256(candidate.read_bytes()).hexdigest()
        for candidate, relative in task_files(task)
    }


def changed_manifest_files(before: dict[str, str], after: dict[str, str]) -> list[str]:
    return sorted(
        name for name in set(before) | set(after) if before.get(name) != after.get(name)
    )


def latest_iteration(state: dict) -> dict | None:
    return state["iterations"][-1] if state.get("iterations") else None


def latest_checks_iteration(state: dict) -> dict | None:
    return next(
        (
            item
            for item in reversed(state.get("iterations", []))
            if item.get("platform_result") == "CHECKS SUBMITTED"
        ),
        None,
    )


def addressed_status(state: dict, digest: str | None) -> str:
    if digest is None:
        return "none"
    cycle = state.get("reviewer_cycle", 1)
    return (
        "addressed"
        if any(
            item.get("hash") == digest and item.get("reviewer_cycle") == cycle
            for item in state.get("addressed_revision_notes", [])
        )
        else "new"
    )


def compact_inspect(state: dict, path: Path) -> dict:
    iteration = latest_iteration(state) or {}
    attempts = iteration.get("platform_attempts", [])
    all_attempts = [
        attempt
        for item in state.get("iterations", [])
        for attempt in item.get("platform_attempts", [])
    ]
    open_attempt = next(
        (item for item in reversed(all_attempts) if not item.get("finished_at")), None
    )
    unresolved_unknown = next(
        (
            item
            for item in reversed(all_attempts)
            if item.get("outcome") == "unknown" and not item.get("reconciled_at")
        ),
        None,
    )
    last_attempt = all_attempts[-1] if all_attempts else None
    last_result_iteration = next(
        (
            item
            for item in reversed(state.get("iterations", []))
            if item.get("platform_result")
        ),
        {},
    )
    return {
        "version": state.get("version"),
        "submission_id": state.get("submission_id"),
        "task": state.get("task"),
        "reviewer_cycle": state.get("reviewer_cycle", 1),
        "rubric_pending": bool(state.get("rubric_pending")),
        "rubric_file": state.get("rubric_file"),
        "iterations": len(state.get("iterations", [])),
        "current_iteration": iteration,
        "iteration_attempts": len(attempts),
        "open_platform_attempt": open_attempt,
        "unresolved_unknown_attempt": unresolved_unknown,
        "last_platform_attempt": last_attempt,
        "last_platform_result": last_result_iteration.get("platform_result"),
        "last_platform_action": last_result_iteration.get("platform_action"),
        "last_task_fingerprint": iteration.get("task_fingerprint_after")
        or iteration.get("prior_task_fingerprint"),
        "state_file": str(path),
    }


def validate_submission_id(value: str) -> str:
    if not UUID_RE.fullmatch(value):
        raise argparse.ArgumentTypeError("submission ID must be a UUID")
    return value.lower()


def inspect_command(args: argparse.Namespace) -> int:
    path = state_path(args.submission_id, args.state_root)
    state = load_state(path, args.submission_id)
    result = compact_inspect(state, path)
    if args.notes_file:
        digest = notes_hash(normalized_revision_notes(args.notes_file))
        result.update(
            {
                "revision_notes_status": addressed_status(state, digest),
                "revision_notes_hash": digest,
            }
        )
    print(json.dumps(result, sort_keys=True))
    return 0


def fingerprint_command(args: argparse.Namespace) -> int:
    print(task_fingerprint(args.task.resolve()))
    return 0


def record_feedback(args: argparse.Namespace) -> int:
    path = state_path(args.submission_id, args.state_root)
    state = load_state(path, args.submission_id)
    facts = extract_feedback(args.feedback_dir)
    prior_task_fingerprint = (
        task_fingerprint(args.task.resolve()) if args.task else None
    )
    last_checks = latest_checks_iteration(state)
    checks_time = (
        parse_time(last_checks.get("checks_submitted_at")) if last_checks else None
    )
    unrefreshed = bool(
        last_checks
        and last_checks.get("feedback", {}).get("fingerprint") == facts["fingerprint"]
        and checks_time
        and datetime.now(timezone.utc)
        < checks_time + timedelta(seconds=args.cooldown_seconds)
    )
    if unrefreshed:
        facts["feedback_complete"] = False
        facts["feedback_details"] = "unrefreshed"

    unresolved_attempts = [
        attempt
        for item in state.get("iterations", [])
        for attempt in item.get("platform_attempts", [])
        if (not attempt.get("finished_at"))
        or (attempt.get("outcome") == "unknown" and not attempt.get("reconciled_at"))
    ]
    platform_reconciled = False
    if facts["feedback_complete"] and unresolved_attempts:
        reconciled_at = now_iso()
        for attempt in unresolved_attempts:
            if not attempt.get("finished_at"):
                attempt["finished_at"] = reconciled_at
                attempt["outcome"] = "unknown"
            attempt["reconciled_at"] = reconciled_at
            attempt["reconciled_by_feedback_fingerprint"] = facts["fingerprint"]
        platform_reconciled = True

    prior_low_uploads = [
        item
        for item in state.get("iterations", [])
        if item.get("feedback", {}).get("difficulty") in LOW_DIFFICULTIES
        and item.get("platform_result") == "CHECKS SUBMITTED"
    ]
    hardening_level = (
        len(prior_low_uploads) + 1 if facts.get("difficulty") in LOW_DIFFICULTIES else 0
    )
    iteration = {
        "iteration": len(state.get("iterations", [])) + 1,
        "observed_at": now_iso(),
        "source_batch": args.source_batch or "",
        "session_id": args.session_id or "",
        "feedback": facts,
        "reviewer_cycle": state.get("reviewer_cycle", 1),
        "revision_notes_status": addressed_status(
            state, facts.get("revision_notes_hash")
        ),
        "prior_task_fingerprint": prior_task_fingerprint,
        "prior_task_manifest": task_manifest(args.task.resolve()) if args.task else {},
        "pre_existing_local_changes": bool(
            latest_checks_iteration(state)
            and prior_task_fingerprint
            != latest_checks_iteration(state).get("task_fingerprint_after")
        ),
        "hardening_level": hardening_level,
        "observed_success_strategy": "",
        "failed_prior_strategies": [
            item.get("observed_success_strategy")
            for item in prior_low_uploads
            if item.get("observed_success_strategy")
        ],
        "hardening_evidence_file": None,
        "task_fingerprint_after": prior_task_fingerprint,
        "changed_files": [],
        "validation": {"mode": None, "result": None},
        "platform_action": "none",
        "platform_result": "WAITING" if not facts["feedback_complete"] else None,
        "platform_reconciled": platform_reconciled,
        "platform_attempts": [],
        "next_expected_stage": (
            "platform feedback"
            if not facts["feedback_complete"]
            else "feedback classification"
        ),
    }
    state["iterations"].append(iteration)
    if args.task:
        state["task"] = str(args.task)
    save_state(path, state)
    output = compact_inspect(state, path)
    output.update(
        {
            "feedback": facts,
            "revision_notes_status": iteration["revision_notes_status"],
            "hardening_level": hardening_level,
            "required_escalation_level": (
                "structural-redesign"
                if facts.get("difficulty") == "TRIVIAL" or hardening_level > 1
                else "orthogonal-non-local-defect"
                if facts.get("difficulty") == "EASY"
                else "none"
            ),
            "unrefreshed_feedback": unrefreshed,
            "platform_reconciled": platform_reconciled,
        }
    )
    print(json.dumps(output, sort_keys=True))
    return 0


def record_hardening(args: argparse.Namespace) -> int:
    path = state_path(args.submission_id, args.state_root)
    state = load_state(path, args.submission_id)
    iteration = latest_iteration(state)
    if (
        not iteration
        or iteration.get("feedback", {}).get("difficulty") not in LOW_DIFFICULTIES
    ):
        raise SystemExit("error: no current platform low-difficulty result exists")
    evidence_path = args.evidence_file.resolve()
    evidence = json.loads(evidence_path.read_text(encoding="utf-8"))
    errors: list[str] = []
    required_fields = {
        "prior_difficulty",
        "prior_agent_performance",
        "successful_trace_sources",
        "common_success_strategy",
        "prior_failed_hardening",
        "starting_state_files_changed",
        "defect_families",
        "contract_changes",
        "removed_or_replaced_shallow_complexity",
    }
    for field in sorted(required_fields - evidence.keys()):
        errors.append(f"required hardening field is missing: {field}")
    task = args.task.resolve()
    current_fingerprint = task_fingerprint(task)
    current_manifest = task_manifest(task)
    actual_changes = changed_manifest_files(
        iteration.get("prior_task_manifest", {}), current_manifest
    )
    previous_upload = latest_checks_iteration(state)
    if previous_upload and current_fingerprint == previous_upload.get(
        "task_fingerprint_after"
    ):
        errors.append("task fingerprint equals the previous checks upload")
    if evidence.get("prior_difficulty") != iteration["feedback"]["difficulty"]:
        errors.append("prior_difficulty does not match current platform feedback")
    trace_evidence_available = any(
        name.startswith("agent_logs/")
        for name in iteration["feedback"].get("source_files", [])
    )
    if not evidence.get("successful_trace_sources") and trace_evidence_available:
        errors.append("available successful/near-success evidence was not identified")
    if not str(evidence.get("common_success_strategy", "")).strip():
        errors.append("common_success_strategy is missing")
    changed_sources = evidence.get("starting_state_files_changed") or []
    real_sources: list[str] = []
    for value in changed_sources:
        candidate = task / value
        if not candidate.exists():
            errors.append(f"claimed source path does not exist: {value}")
            continue
        normalized = Path(value).as_posix()
        if normalized not in actual_changes:
            errors.append(
                f"claimed source path was not changed in this iteration: {value}"
            )
            continue
        if (
            normalized.startswith("environment/")
            and Path(value).name.casefold() not in NON_SOURCE_DOCS
        ):
            real_sources.append(normalized)
    if not real_sources:
        errors.append("no real agent-visible environment source file is claimed")
    families = evidence.get("defect_families") or []
    if not families:
        errors.append("no defect family is documented")
    for index, family in enumerate(families, start=1):
        for field in (
            "name",
            "root_cause",
            "source_delta",
            "interacts_with",
            "strategy_invalidated",
            "oracle_signal",
            "verifier_signal",
        ):
            if not family.get(field):
                errors.append(f"defect family {index} lacks {field}")
        for value in family.get("source_delta") or []:
            if not (task / value).exists():
                errors.append(
                    f"defect family {index} source path does not exist: {value}"
                )
    repeated = iteration.get("hardening_level", 0) > 1
    expected_failed = set(iteration.get("failed_prior_strategies") or [])
    acknowledged_failed = set(evidence.get("prior_failed_hardening") or [])
    if repeated and (
        not acknowledged_failed or not expected_failed.issubset(acknowledged_failed)
    ):
        errors.append(
            "repeated low difficulty does not acknowledge every failed prior hardening strategy"
        )
    if (repeated or iteration["feedback"]["difficulty"] == "TRIVIAL") and len(
        families
    ) < 2:
        errors.append(
            "structural redesign requires multiple independent defect families"
        )
    if (
        repeated or iteration["feedback"]["difficulty"] == "TRIVIAL"
    ) and not evidence.get("removed_or_replaced_shallow_complexity"):
        errors.append(
            "structural redesign does not identify replaced shallow complexity"
        )
    if errors:
        iteration["hardening_gate"] = "failed"
        iteration["hardening_gate_errors"] = errors
        iteration["platform_result"] = "BLOCKED"
        save_state(path, state)
        print(
            json.dumps({"hardening_gate": "failed", "errors": errors}, sort_keys=True)
        )
        return 1
    iteration["observed_success_strategy"] = evidence["common_success_strategy"]
    iteration["failed_prior_strategies"] = evidence.get("prior_failed_hardening", [])
    iteration["hardening_evidence_file"] = str(evidence_path)
    iteration["task_fingerprint_after"] = current_fingerprint
    iteration["changed_files"] = actual_changes
    iteration["hardening_gate"] = "passed"
    iteration.pop("hardening_gate_errors", None)
    if iteration.get("platform_result") == "BLOCKED":
        iteration["platform_result"] = None
    save_state(path, state)
    print(
        json.dumps(
            {
                "hardening_gate": "passed",
                "hardening_level": iteration.get("hardening_level"),
                "task_fingerprint": current_fingerprint,
                "state_file": str(path),
            },
            sort_keys=True,
        )
    )
    return 0


def record_validation(args: argparse.Namespace) -> int:
    path = state_path(args.submission_id, args.state_root)
    state = load_state(path, args.submission_id)
    iteration = latest_iteration(state)
    if not iteration:
        raise SystemExit("error: record feedback before validation")
    iteration["validation"] = {
        "mode": args.mode,
        "result": args.result,
        "recorded_at": now_iso(),
    }
    if args.result == "failed":
        iteration["platform_result"] = "BLOCKED"
    elif iteration.get("platform_result") == "BLOCKED":
        iteration["platform_result"] = None
    save_state(path, state)
    print(
        json.dumps(
            {"validation": iteration["validation"], "state_file": str(path)},
            sort_keys=True,
        )
    )
    return 0


def begin_platform_attempt(args: argparse.Namespace) -> int:
    path = state_path(args.submission_id, args.state_root)
    state = load_state(path, args.submission_id)
    iteration = latest_iteration(state)
    if not iteration:
        raise SystemExit("error: record feedback before a platform attempt")
    if iteration.get("validation", {}).get("result") != "passed":
        raise SystemExit(
            "error: refusing platform attempt without recorded passing validation"
        )
    unresolved = [
        attempt
        for item in state.get("iterations", [])
        for attempt in item.get("platform_attempts", [])
        if (not attempt.get("finished_at"))
        or (attempt.get("outcome") == "unknown" and not attempt.get("reconciled_at"))
    ]
    if unresolved:
        raise SystemExit(
            "error: refusing platform attempt until prior unknown upload is reconciled"
        )
    task = args.task.resolve()
    fingerprint = task_fingerprint(task)
    if args.mode == "checks":
        prior = latest_checks_iteration(state)
        if (
            prior
            and prior is not iteration
            and fingerprint == prior.get("task_fingerprint_after")
        ):
            raise SystemExit("error: refusing unchanged checks upload")
        if iteration.get("feedback", {}).get("difficulty") in LOW_DIFFICULTIES:
            if iteration.get("hardening_gate") != "passed":
                raise SystemExit(
                    "error: refusing low-difficulty upload without a passed hardening gate"
                )
            if iteration.get("task_fingerprint_after") != fingerprint:
                raise SystemExit(
                    "error: task changed after hardening evidence was validated"
                )
    attempt_id = str(uuid.uuid4())
    attempts = iteration.setdefault("platform_attempts", [])
    attempts.append(
        {
            "attempt_id": attempt_id,
            "attempt": len(attempts) + 1,
            "mode": args.mode,
            "task_fingerprint": fingerprint,
            "started_at": now_iso(),
            "finished_at": None,
            "outcome": None,
        }
    )
    iteration["platform_action"] = args.mode
    iteration["task_fingerprint_after"] = fingerprint
    save_state(path, state)
    print(f"platform_attempt_id={attempt_id}")
    print(f"platform_attempts={len(attempts)}")
    print(f"task_fingerprint={fingerprint}")
    return 0


def find_attempt(iteration: dict, attempt_id: str | None) -> dict:
    attempts = iteration.get("platform_attempts", [])
    if attempt_id:
        attempt = next(
            (item for item in attempts if item.get("attempt_id") == attempt_id), None
        )
    else:
        attempt = next(
            (item for item in reversed(attempts) if not item.get("finished_at")), None
        )
    if not attempt:
        raise SystemExit("error: no matching open platform attempt")
    return attempt


def address_current_notes(state: dict, iteration: dict) -> None:
    digest = iteration.get("feedback", {}).get("revision_notes_hash")
    if not digest:
        return
    cycle = iteration.get("reviewer_cycle", state.get("reviewer_cycle", 1))
    records = state.setdefault("addressed_revision_notes", [])
    if any(
        item.get("hash") == digest and item.get("reviewer_cycle") == cycle
        for item in records
    ):
        return
    records.append(
        {
            "hash": digest,
            "reviewer_cycle": cycle,
            "task_fingerprint": iteration.get("task_fingerprint_after"),
            "checks_submitted_at": iteration.get("checks_submitted_at"),
            "recorded_at": now_iso(),
        }
    )


def finish_attempt(state: dict, iteration: dict, attempt: dict, outcome: str) -> None:
    if attempt.get("finished_at"):
        if attempt.get("outcome") == outcome:
            return
        raise SystemExit("error: platform attempt already has a different outcome")
    attempt["finished_at"] = now_iso()
    attempt["outcome"] = outcome
    if outcome == "checks_submitted":
        iteration["platform_action"] = "checks"
        iteration["platform_result"] = "CHECKS SUBMITTED"
        iteration["checks_submitted_at"] = attempt["finished_at"]
        iteration["submitted_at"] = attempt["finished_at"]
        iteration["next_expected_stage"] = "platform checks"
        address_current_notes(state, iteration)
    elif outcome == "reviewer_submitted":
        iteration["platform_action"] = "reviewer"
        iteration["platform_result"] = "SENT TO REVIEWER"
        iteration["submitted_at"] = attempt["finished_at"]
        iteration["next_expected_stage"] = "reviewer"
        state["reviewer_cycle"] = state.get("reviewer_cycle", 1) + 1
    elif outcome == "unknown":
        iteration["platform_result"] = "UNKNOWN"
        iteration["next_expected_stage"] = "platform reconciliation"
    elif outcome in {"static_checks_failed", "definitive_failure"}:
        iteration["platform_result"] = "BLOCKED"
    attempt["platform_result"] = iteration.get("platform_result")


def finish_platform_attempt(args: argparse.Namespace) -> int:
    path = state_path(args.submission_id, args.state_root)
    state = load_state(path, args.submission_id)
    iteration = latest_iteration(state)
    if not iteration:
        raise SystemExit("error: no current iteration")
    attempt = find_attempt(iteration, args.attempt_id)
    finish_attempt(state, iteration, attempt, args.outcome)
    save_state(path, state)
    print(f"platform_outcome={args.outcome}")
    print(f"platform_result={iteration.get('platform_result') or ''}")
    print(f"platform_attempts={len(iteration.get('platform_attempts', []))}")
    return 0


def finish_alias(args: argparse.Namespace) -> int:
    args.outcome = args.alias_outcome
    return finish_platform_attempt(args)


def record_notes(args: argparse.Namespace) -> int:
    path = state_path(args.submission_id, args.state_root)
    state = load_state(path, args.submission_id)
    digest = notes_hash(normalized_revision_notes(args.notes_file))
    if digest is None:
        print("revision_notes_status=none")
        return 0
    iteration = latest_iteration(state) or {
        "reviewer_cycle": state.get("reviewer_cycle", 1),
        "feedback": {"revision_notes_hash": digest},
        "task_fingerprint_after": task_fingerprint(Path(args.task).resolve())
        if args.task
        else None,
        "checks_submitted_at": now_iso(),
    }
    iteration.setdefault("feedback", {})["revision_notes_hash"] = digest
    address_current_notes(state, iteration)
    save_state(path, state)
    print(
        f"revision_notes_status=addressed\nrevision_notes_hash={digest}\nstate_file={path}"
    )
    return 0


def mark_rubric(args: argparse.Namespace) -> int:
    path = state_path(args.submission_id, args.state_root)
    state = load_state(path, args.submission_id)
    state["rubric_pending"] = True
    state["rubric_file"] = str(args.rubric_file)
    state["rubric_marked_at"] = now_iso()
    iteration = latest_iteration(state)
    if iteration:
        iteration["platform_result"] = "MANUAL ACTION"
        iteration["next_expected_stage"] = "manual rubric"
    save_state(path, state)
    print(f"rubric_pending=true\nrubric_file={args.rubric_file}\nstate_file={path}")
    return 0


def clear_rubric(args: argparse.Namespace) -> int:
    path = state_path(args.submission_id, args.state_root)
    state = load_state(path, args.submission_id)
    state["rubric_pending"] = False
    state["rubric_cleared_at"] = now_iso()
    save_state(path, state)
    print(f"rubric_pending=false\nstate_file={path}")
    return 0


def legacy_result(entry: dict) -> str:
    result = str(entry.get("result", "")).upper()
    action = str(entry.get("platform_action", "")).lower()
    if result == "SUCCESS" and "check" in action:
        return "CHECKS SUBMITTED"
    if result == "SUCCESS" and "review" in action:
        return "SENT TO REVIEWER"
    return result or "UNKNOWN"


def migrate_batches(args: argparse.Namespace) -> int:
    migrated = 0
    skipped = 0
    for sessions_file in sorted(args.batch_root.glob("*/sessions.json")):
        batch = json.loads(sessions_file.read_text(encoding="utf-8"))
        batch_id = batch.get("batch_id") or sessions_file.parent.name
        for submission_id, entry in (batch.get("submissions") or {}).items():
            try:
                normalized_id = validate_submission_id(submission_id)
            except argparse.ArgumentTypeError:
                skipped += 1
                continue
            path = state_path(normalized_id, args.state_root)
            state = load_state(path, normalized_id)
            migration_key = f"legacy-batch:{batch_id}:{entry.get('session_id', '')}"
            if any(
                item.get("migration_key") == migration_key
                for item in state["iterations"]
            ):
                skipped += 1
                continue
            result = legacy_result(entry)
            action = (
                "checks"
                if result == "CHECKS SUBMITTED"
                else "reviewer"
                if result == "SENT TO REVIEWER"
                else "none"
            )
            state["iterations"].append(
                {
                    "iteration": len(state["iterations"]) + 1,
                    "observed_at": entry.get("updated_at")
                    or batch.get("created_at")
                    or now_iso(),
                    "source_batch": batch_id,
                    "session_id": entry.get("session_id", ""),
                    "feedback": {"feedback_details": "unknown"},
                    "feedback_details": "unknown",
                    "legacy": True,
                    "migration_key": migration_key,
                    "platform_action": action,
                    "platform_result": result,
                    "platform_attempts": [
                        {
                            "attempt": number,
                            "mode": action,
                            "started_at": None,
                            "finished_at": entry.get("updated_at"),
                            "outcome": (
                                "checks_submitted"
                                if result == "CHECKS SUBMITTED"
                                else "reviewer_submitted"
                                if result == "SENT TO REVIEWER"
                                else "unknown"
                            ),
                        }
                        for number in range(1, int(entry.get("attempts") or 0) + 1)
                    ],
                    "notes": entry.get("notes", ""),
                }
            )
            state["task"] = entry.get("folder") or state.get("task")
            if result == "SENT TO REVIEWER":
                state["reviewer_cycle"] = state.get("reviewer_cycle", 1) + 1
            save_state(path, state)
            migrated += 1
    print(json.dumps({"migrated": migrated, "skipped": skipped}, sort_keys=True))
    return 0


def common_parser(subparser: argparse.ArgumentParser) -> None:
    subparser.add_argument(
        "--submission-id", required=True, type=validate_submission_id
    )
    subparser.add_argument("--state-root", type=Path)


def add_finish_parser(commands, name: str, outcome: str) -> None:
    parser = commands.add_parser(name)
    common_parser(parser)
    parser.add_argument("--attempt-id")
    parser.set_defaults(func=finish_alias, alias_outcome=outcome)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)

    inspect_parser = commands.add_parser("inspect")
    common_parser(inspect_parser)
    inspect_parser.add_argument("--notes-file", type=Path)
    inspect_parser.set_defaults(func=inspect_command)

    fingerprint_parser = commands.add_parser("fingerprint")
    fingerprint_parser.add_argument("--task", required=True, type=Path)
    fingerprint_parser.set_defaults(func=fingerprint_command)

    feedback_parser = commands.add_parser("record-feedback")
    common_parser(feedback_parser)
    feedback_parser.add_argument("--feedback-dir", required=True, type=Path)
    feedback_parser.add_argument("--task", type=Path)
    feedback_parser.add_argument("--source-batch")
    feedback_parser.add_argument("--session-id")
    feedback_parser.add_argument(
        "--cooldown-seconds", type=int, default=DEFAULT_COOLDOWN_SECONDS
    )
    feedback_parser.set_defaults(func=record_feedback)

    hardening_parser = commands.add_parser("record-hardening")
    common_parser(hardening_parser)
    hardening_parser.add_argument("--task", required=True, type=Path)
    hardening_parser.add_argument("--evidence-file", required=True, type=Path)
    hardening_parser.set_defaults(func=record_hardening)

    validation_parser = commands.add_parser("record-validation")
    common_parser(validation_parser)
    validation_parser.add_argument(
        "--mode", required=True, choices=("fast-only", "full")
    )
    validation_parser.add_argument(
        "--result", required=True, choices=("passed", "failed")
    )
    validation_parser.set_defaults(func=record_validation)

    begin_parser = commands.add_parser("begin-platform-attempt")
    common_parser(begin_parser)
    begin_parser.add_argument("--mode", required=True, choices=("checks", "reviewer"))
    begin_parser.add_argument("--task", required=True, type=Path)
    begin_parser.set_defaults(func=begin_platform_attempt)

    finish_parser = commands.add_parser("finish-platform-attempt")
    common_parser(finish_parser)
    finish_parser.add_argument("--attempt-id")
    finish_parser.add_argument(
        "--outcome",
        required=True,
        choices=(
            "checks_submitted",
            "reviewer_submitted",
            "static_checks_failed",
            "transient_failure",
            "definitive_failure",
            "unknown",
        ),
    )
    finish_parser.set_defaults(func=finish_platform_attempt)

    add_finish_parser(commands, "record-checks-submitted", "checks_submitted")
    add_finish_parser(commands, "record-reviewer-submitted", "reviewer_submitted")
    add_finish_parser(commands, "record-unknown", "unknown")

    record_parser = commands.add_parser("record-notes")
    common_parser(record_parser)
    record_parser.add_argument("--notes-file", required=True, type=Path)
    record_parser.add_argument(
        "--upload-mode", required=True, choices=("checks", "reviewer")
    )
    record_parser.add_argument("--task")
    record_parser.set_defaults(func=record_notes)

    mark_parser = commands.add_parser("mark-rubric")
    common_parser(mark_parser)
    mark_parser.add_argument("--rubric-file", required=True, type=Path)
    mark_parser.set_defaults(func=mark_rubric)

    clear_parser = commands.add_parser("clear-rubric")
    common_parser(clear_parser)
    clear_parser.set_defaults(func=clear_rubric)

    migration_parser = commands.add_parser("migrate-batches")
    migration_parser.add_argument("--batch-root", required=True, type=Path)
    migration_parser.add_argument("--state-root", type=Path)
    migration_parser.set_defaults(func=migrate_batches)
    return parser


def main() -> int:
    args = build_parser().parse_args()
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
