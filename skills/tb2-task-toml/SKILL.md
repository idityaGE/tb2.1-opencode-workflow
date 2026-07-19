---
name: tb2-task-toml
description: Write correct Terminal-Bench 2 task.toml metadata, including category, subcategories, languages, tags, runtime limits, required zero milestones, and codebase_size based on environment file count.
---

# TB2 Task TOML

Use when writing or reviewing `task.toml`.

Requirements:
- Use Edition 2 metadata: `version = "2.0"`, `[metadata]`, `[environment]`, and for regular tasks `[agent]` plus `[verifier]`.
- `author_name` and `author_email` may be `anonymous`.
- Match category, subcategories, languages, tags, timeouts, and difficulty to the actual task.
- Set `difficulty` only to one of `easy`, `hard`, `medium`, or `unknown`. Use `hard` for this workflow's extremely hard task target; do not write `extremely hard` in `task.toml`.
- Follow the centralized category policy in `tb2-hard-task-author`, then use the exact current taxonomy slug for the selected primary activity. Local lint derives accepted and blocked slugs from the taxonomy document.
- Make `category` agree with the prompt, final artifact, environment, and dominant verifier behavior; never relabel a blocked primary activity.
- `subcategories` must contain only these exact values: `api_integration`, `db_interaction`, `long_context`, `tool_specific`, `ui_building`. Values such as `binary-analysis`, `program-analysis`, `cryptography`, `protocols`, `compiler`, or language names are invalid; put those details in `tags` instead.
- If none of the five allowed subcategories fits, leave the array empty with `subcategories = []`. Most system-administration and build tasks should leave it empty.
- Do not list Python as a primary implementation language. Non-Python implementation languages are allowed when they match the task; Python may appear only for verifier/test tooling when necessary.
- Set `allow_internet = false` unless the task type explicitly requires otherwise.
- Always include `number_of_milestones = 0` in `[metadata]`; local lint blocks missing values and nonzero milestone counts.
- Compute `codebase_size` from files under `environment/`: `minimal` for 0-20 files, `small` for more than 20, `large` for 200 or more.
- Use 3-6 truthful tags for domain details. For tool/API/database subcategories, include the concrete tool, API framework, or database in tags.
- Keep metadata truthful; do not overstate language, size, or domain.
