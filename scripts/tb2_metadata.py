#!/usr/bin/env python3
"""Canonical TB2 task.toml schema, defaults, category status, and labels."""

from __future__ import annotations

import argparse
import json
import re
from functools import lru_cache
from pathlib import Path
from typing import Any

import tomllib

OPENCODE_ROOT = Path(__file__).resolve().parents[1]
TAXONOMY_PATH = OPENCODE_ROOT / "docs" / "tb2" / "task-taxonomy.md"
CATEGORY_STATUS_PATH = OPENCODE_ROOT / "docs" / "tb2" / "category-status.md"

KNOWN_DIFFICULTIES = ("easy", "medium", "hard", "unknown")
CREATE_DIFFICULTIES = ("medium", "hard")
ALLOWED_SUBCATEGORIES = frozenset(
    {"api_integration", "db_interaction", "long_context", "tool_specific", "ui_building"}
)
PLATFORM_CATEGORY_LABELS = {
    "system-administration": "System / Environment Setup & Configuration",
    "build-and-dependency-management": "Build / Compilation / Dependency Management",
    "machine-learning": "Machine Learning / Model Training / Inference",
    "security": "Security / Cryptography / Vulnerability Demonstration",
    "scientific-computing": "Scientific Computing",
    "games": "Interactive / Simulation Tasks / Games",
}

# These values are the local skeleton defaults, not substitutes for truthful task-specific values.
DEFAULTS: dict[str, Any] = {
    "version": "2.0",
    "metadata.author_name": "anonymous",
    "metadata.author_email": "anonymous",
    "metadata.subcategories": [],
    "metadata.number_of_milestones": 0,
    "metadata.expert_time_estimate_min": 60,
    "metadata.junior_time_estimate_min": 120,
    "verifier.timeout_sec": 600.0,
    "agent.timeout_sec": 1800.0,
    "environment.build_timeout_sec": 900.0,
    "environment.cpus": 2,
    "environment.memory_mb": 4096,
    "environment.storage_mb": 10240,
    "environment.allow_internet": False,
}
REQUIRED_METADATA_FIELDS = (
    "author_name",
    "author_email",
    "category",
    "subcategories",
    "difficulty",
    "codebase_size",
    "number_of_milestones",
    "languages",
    "tags",
    "expert_time_estimate_min",
    "junior_time_estimate_min",
)
REQUIRED_ENVIRONMENT_FIELDS = (
    "build_timeout_sec",
    "cpus",
    "memory_mb",
    "storage_mb",
    "allow_internet",
)


@lru_cache(maxsize=1)
def category_policy() -> tuple[frozenset[str], frozenset[str]]:
    """Return all taxonomy slugs and currently blocked net-new slugs."""
    taxonomy = TAXONOMY_PATH.read_text(errors="replace")
    categories_match = re.search(
        r"(?ms)^## Categories\s*$\n(.*?)^## Distribution Guidelines\s*$", taxonomy
    )
    if categories_match is None:
        raise RuntimeError(f"could not parse category section from {TAXONOMY_PATH}")

    categories = {
        match.group(1).strip().lower()
        for match in re.finditer(r"(?m)^###\s+([^\n]+?)\s*$", categories_match.group(1))
    }
    invalid = sorted(slug for slug in categories if not re.fullmatch(r"[a-z][a-z0-9-]*", slug))
    if invalid or not categories:
        raise RuntimeError(f"invalid or empty category taxonomy in {TAXONOMY_PATH}: {invalid}")

    status = CATEGORY_STATUS_PATH.read_text(errors="replace")
    blocked = {
        match.group(1)
        for match in re.finditer(
            r"(?m)^\|\s*`([a-z][a-z0-9-]*)`\s*\|\s*[^|]*Blocked[^|]*\|", status
        )
    }
    status_categories = {
        match.group(1)
        for match in re.finditer(r"(?m)^\|\s*`([a-z][a-z0-9-]*)`\s*\|", status)
    }
    if status_categories != categories:
        missing = sorted(categories - status_categories)
        extra = sorted(status_categories - categories)
        raise RuntimeError(
            f"category status/taxonomy mismatch: missing={missing}, extra={extra}"
        )
    missing_labels = sorted((categories - blocked) - PLATFORM_CATEGORY_LABELS.keys())
    extra_labels = sorted(PLATFORM_CATEGORY_LABELS.keys() - categories)
    if missing_labels or extra_labels:
        raise RuntimeError(
            f"platform category-label mismatch: missing={missing_labels}, extra={extra_labels}"
        )
    return frozenset(categories), frozenset(blocked)


def environment_file_count(task: Path) -> int:
    env = task / "environment"
    if not env.exists():
        return 0
    excluded = {"Dockerfile", "docker-compose.yaml", "docker-compose.yml"}
    return sum(
        1
        for path in env.rglob("*")
        if path.is_file() and path.relative_to(env).as_posix() not in excluded
    )


def expected_codebase_size(file_count: int) -> str:
    if file_count >= 200:
        return "large"
    if file_count >= 20:
        return "small"
    return "minimal"


def _is_positive_number(value: object) -> bool:
    return isinstance(value, (int, float)) and not isinstance(value, bool) and value > 0


def metadata_issues(
    config: dict[str, Any], task: Path, *, context: str
) -> tuple[list[str], list[str]]:
    """Return mechanical task.toml errors and warnings for create or revision context."""
    if context not in {"create", "revision"}:
        raise ValueError(f"invalid metadata context: {context}")

    errors: list[str] = []
    warnings: list[str] = []
    if config.get("version") != DEFAULTS["version"]:
        errors.append('version must be "2.0"')

    metadata = config.get("metadata")
    environment = config.get("environment")
    if not isinstance(metadata, dict):
        errors.append("missing [metadata] section")
        metadata = {}
    if not isinstance(environment, dict):
        errors.append("missing [environment] section")
        environment = {}

    for field in REQUIRED_METADATA_FIELDS:
        if field not in metadata:
            errors.append(f"missing required field: metadata.{field}")
    for field in REQUIRED_ENVIRONMENT_FIELDS:
        if field not in environment:
            errors.append(f"missing required field: environment.{field}")

    for field in ("author_name", "author_email"):
        value = metadata.get(field)
        if value is not None and (not isinstance(value, str) or not value.strip()):
            errors.append(f"metadata.{field} must be a non-empty string")

    categories, blocked_categories = category_policy()
    category = metadata.get("category")
    if not isinstance(category, str) or category not in categories:
        errors.append(
            f"metadata.category must be an exact taxonomy slug: {', '.join(sorted(categories))}"
        )
    elif context == "create" and category in blocked_categories:
        errors.append(f"metadata.category {category!r} is blocked for net-new tasks")

    difficulty = metadata.get("difficulty")
    allowed_difficulties = CREATE_DIFFICULTIES if context == "create" else KNOWN_DIFFICULTIES
    if difficulty not in allowed_difficulties:
        errors.append(
            f"metadata.difficulty must be one of: {', '.join(allowed_difficulties)}"
        )

    subcategories = metadata.get("subcategories")
    if not isinstance(subcategories, list) or any(not isinstance(item, str) for item in subcategories):
        errors.append("metadata.subcategories must be a list of strings")
    else:
        invalid_subcategories = sorted(set(subcategories) - ALLOWED_SUBCATEGORIES)
        if invalid_subcategories:
            errors.append(
                "metadata.subcategories contains invalid values "
                f"{invalid_subcategories}; use only {', '.join(sorted(ALLOWED_SUBCATEGORIES))}"
            )

    milestones = metadata.get("number_of_milestones")
    if not isinstance(milestones, int) or isinstance(milestones, bool) or milestones < 0:
        errors.append("metadata.number_of_milestones must be a non-negative integer")
        milestones = 0
    elif context == "create" and milestones != 0:
        errors.append("metadata.number_of_milestones must be 0 for net-new tasks")

    languages = metadata.get("languages")
    if not isinstance(languages, list) or not languages or any(
        not isinstance(item, str) or not item.strip() for item in languages
    ):
        errors.append("metadata.languages must be a non-empty list of strings")
    elif context == "create" and any(item.lower() == "python" for item in languages):
        errors.append("Python must not be listed as a net-new task implementation language")

    tags = metadata.get("tags")
    if not isinstance(tags, list) or any(not isinstance(item, str) or not item.strip() for item in tags):
        errors.append("metadata.tags must be a list of non-empty strings")
    elif not 3 <= len(tags) <= 6:
        warnings.append("metadata.tags should contain 3-6 entries")

    for field in ("expert_time_estimate_min", "junior_time_estimate_min"):
        value = metadata.get(field)
        if value is not None and not _is_positive_number(value):
            errors.append(f"metadata.{field} must be a positive number")

    if milestones == 0:
        for section in ("agent", "verifier"):
            section_value = config.get(section)
            if not isinstance(section_value, dict):
                errors.append(f"missing [{section}] section for a regular task")
            elif not _is_positive_number(section_value.get("timeout_sec")):
                errors.append(f"{section}.timeout_sec must be a positive number")

    for field in ("build_timeout_sec", "cpus", "memory_mb", "storage_mb"):
        value = environment.get(field)
        if value is not None and not _is_positive_number(value):
            errors.append(f"environment.{field} must be a positive number")
    allow_internet = environment.get("allow_internet")
    if allow_internet is not None and not isinstance(allow_internet, bool):
        errors.append("environment.allow_internet must be a boolean")
    elif allow_internet:
        warnings.append("confirm runtime internet is genuinely required and deterministic")

    compose_paths = [task / "environment" / name for name in ("docker-compose.yaml", "docker-compose.yml")]
    if any(path.exists() for path in compose_paths) and metadata.get("custom_docker_compose") is not True:
        errors.append("docker-compose tasks must set metadata.custom_docker_compose = true")

    file_count = environment_file_count(task)
    expected_size = expected_codebase_size(file_count)
    if metadata.get("codebase_size") != expected_size:
        errors.append(
            f"metadata.codebase_size is {metadata.get('codebase_size')!r}, "
            f"expected {expected_size!r} for {file_count} environment files"
        )
    return errors, warnings


def metadata_summary(task: Path) -> list[str]:
    config_path = task / "task.toml"
    config = tomllib.loads(config_path.read_text())
    metadata = config.get("metadata", {})
    environment = config.get("environment", {})
    category = metadata.get("category", "")
    categories, blocked = category_policy()
    status = "blocked" if category in blocked else "open" if category in categories else "unknown"
    keys = (
        "author_name",
        "author_email",
        "category",
        "subcategories",
        "difficulty",
        "languages",
        "tags",
        "codebase_size",
        "number_of_milestones",
        "expert_time_estimate_min",
        "junior_time_estimate_min",
    )
    lines = [f"version={config.get('version')!r}"]
    lines.extend(f"metadata.{key}={metadata.get(key)!r}" for key in keys)
    lines.append(f"category_status={status}")
    lines.append(f"platform_label={PLATFORM_CATEGORY_LABELS.get(category, 'not-available')!r}")
    lines.append(f"environment.allow_internet={environment.get('allow_internet')!r}")
    lines.append(f"environment_file_count={environment_file_count(task)}")
    return lines


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    subparsers.add_parser("defaults", help="print canonical local defaults as JSON")
    subparsers.add_parser("categories", help="print category status and platform labels")
    label_parser = subparsers.add_parser("platform-label", help="print one platform category label")
    label_parser.add_argument("category")
    summary_parser = subparsers.add_parser("summary", help="print canonical task.toml summary")
    summary_parser.add_argument("task", type=Path)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if args.command == "defaults":
        print(json.dumps(DEFAULTS, indent=2, sort_keys=True))
        return 0
    if args.command == "categories":
        categories, blocked = category_policy()
        for category in sorted(categories):
            status = "blocked" if category in blocked else "open"
            print(f"{category}\t{status}\t{PLATFORM_CATEGORY_LABELS.get(category, 'not-available')}")
        return 0
    if args.command == "platform-label":
        label = PLATFORM_CATEGORY_LABELS.get(args.category)
        if label is None:
            raise SystemExit(f"no platform label configured for category: {args.category}")
        print(label)
        return 0
    if args.command == "summary":
        try:
            for line in metadata_summary(args.task.resolve()):
                print(line)
        except (OSError, RuntimeError, tomllib.TOMLDecodeError) as exc:
            print(f"metadata_error={exc}")
            return 1
        return 0
    raise AssertionError(args.command)


if __name__ == "__main__":
    raise SystemExit(main())
