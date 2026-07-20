---
name: tb2-task-toml
description: Write and review Terminal-Bench 2 task.toml metadata through the canonical schema/default helper and local workflow profile.
---

# TB2 Task TOML

Use when writing or reviewing `task.toml`.

Requirements:
- Read `.opencode/docs/local/workflow-profile.md` for create-versus-revision policy.
- Use `.opencode/scripts/tb2_metadata.py` as the only mechanical source for required fields, defaults, live category status, platform labels, allowed subcategories, and codebase-size calculation. Run `python3 .opencode/scripts/tb2_metadata.py defaults`, `categories`, `platform-label <slug>`, or `summary tasks/<task_name>` instead of maintaining another list here.
- Match category, subcategories, languages, tags, estimates, timeouts, resources, compose flags, internet access, difficulty, and milestone count to the actual task. Defaults are starting values, not permission to write false metadata.
- Follow the category-selection semantics in `tb2-hard-task-author`. Never rescue a blocked primary activity with wording or metadata-only relabeling.
- For create-time mechanical checks, use `.opencode/scripts/tb2_task_lint.py --context create tasks/<task_name>`. For a revision, use `--context revision` so valid grandfathered metadata is preserved while the schema remains checked.
