---
name: tb2-workflow-maintainer
description: Maintain and evolve the TB2 opencode workflow; use when changing /create-task, /modify-workflow, TB2 agents, skills, plugins, hooks, or helper scripts.
---

# TB2 Workflow Maintainer

Use when modifying the TB2 task-creation workflow itself.

## Workflow Inventory

Primary opencode files:
- `.opencode/commands/create-task.md`: user-facing task creation command.
- `.opencode/commands/task-proposal.md`: user-facing proposal research, platform-check iteration, and approval-gated creation command.
- `.opencode/commands/update-task.md`: user-facing submission feedback/update command.
- `.opencode/commands/modify-workflow.md`: user-facing workflow modification command.
- `.opencode/agents/tb2-task-orchestrator.md`: follows the local workflow profile, researches options, asks the user, invokes builder, asks before submission.
- `.opencode/agents/tb2-task-proposer.md`: follows the local workflow profile, prints platform fields, iterates on four proposal checks, and invokes builder only after all pass and the user approves.
- `.opencode/agents/tb2-task-builder.md`: creates layered hidden-bug task files, uses component skills, validates structural/NOP/oracle behavior, writes humanized field answers.
- `.opencode/agents/tb2-task-reviewer.md`: statically applies the local Edition 2 review prompt and returns evidence-backed findings for builder repair.
- `.opencode/agents/tb2-task-updater.md`: fetches submission feedback, fixes concrete task issues, uses fast structural/alignment/metadata checks for instruction.md and/or task.toml-only edits or full NOP/oracle validation for runtime-affecting edits, and updates without sending to reviewer.
- `.opencode/agents/tb2-workflow-maintainer.md`: modifies workflow infrastructure.
- `.opencode/plugins/tb2-task-hooks.ts`: opencode plugin hook for fast post-edit structural TB2 checks.
- `.opencode/skills/tb2-*/SKILL.md`: component workflow guidance.
- `.opencode/scripts/*`: execution backend scripts for create, validate, hooks, submit, and update-only feedback handling.
- `.opencode/docs/policy-sources.toml`: copied/local source classification, precedence, upstream path, sync date, and documented overlays.
- `.opencode/docs/local/**`: local workflow profile and authoring notes.
- `.opencode/docs/tb2/**`: copied current-status, normative, advisory, and historical TB2 sources.
- `.opencode/templates/tests/test.sh`: sole positive regular-task verifier runner template.

Create-task backend scripts:
- `tb2_create_task.sh`: initializes `tasks/<task>` with `stb init` and installs the canonical verifier runner.
- `tb2_validate_task.sh`: runs structural lint, ruff, NOP, and oracle checks.
- `tb2_task_lint.py`: structural task lint.
- `tb2_metadata.py`: canonical task.toml schema/defaults, category status, platform labels, subcategories, size bands, and metadata summary.
- `tb2_task_state.sh`: prints and optionally caches compact deterministic task state so agents do not spend tokens manually classifying changed files, metadata, instruction length, or validation scope.
- `tb2_hook_task_check.sh`: fast post-edit structural hook wrapper for one task.
- `tb2_copy_field_answers.sh`: copies a full field-answer file or a single section without interactive pauses.
- `tb2_prepare_upload.sh`: validates that the target is a direct `tasks/<task>` folder, removes generated `__pycache__` directories, and deletes only the generated root-level `<task>.zip` archive before validation, submission, or update upload.
- `tb2_submit_task.sh`: submission helper.
- `tb2_update_task.sh`: update helper that prepares upload cleanup and runs `stb submissions update ... --no-send-to-reviewer` with a random 280-350 minute time.

Update-only feedback scripts:
- `tb2_status_iterate.sh`: feedback/update helper.
- `tb2_quality_report.py`: feedback summary helper.

## Flow

1. User runs `/create-task`.
2. `tb2-task-orchestrator` applies `.opencode/docs/local/workflow-profile.md`, uses compact skill context plus focused existing-task inspection, presents options through `question`, then invokes `tb2-task-builder`.
3. `tb2-task-builder` initializes and authors the layered hidden-bug task, uses component skills instead of bulk doc reads, validates, and writes humanized field answers.
4. The parent invokes `tb2-task-reviewer`, sends all static review findings to the builder, and repeats repair and review until clean or blocked.
5. Parent reports a compact result and asks before platform submission only after a clean review.
6. `tb2-task-hooks.ts` runs fast post-edit structural checks on task-file modifications; full ruff/NOP/oracle validation stays in `tb2_validate_task.sh`.
7. User runs `/update-task <submission_id>`.
8. `tb2-task-updater` fetches feedback, summarizes issues, fixes the matching local task, uses structural/alignment/metadata checks without NOP/oracle for instruction.md and/or task.toml-only changes, otherwise validates structural/NOP/oracle behavior, and runs the update helper only after the applicable validation passes; the helper chooses a random 280-350 minute update time and uses `--no-send-to-reviewer`.
9. `/task-proposal` applies the local profile, emits proposal fields in chat, revises them from platform feedback until all four checks pass, then runs builder/reviewer repair only after explicit user approval.

## Safe Modification Rules

- Modify only workflow infrastructure unless explicitly asked otherwise.
- Never modify `tasks/**` as part of workflow maintenance.
- Never submit or update platform submissions from `/modify-workflow`.
- `/update-task` is the only workflow command that may run `stb submissions update`, and it must include `--no-send-to-reviewer`.
- Read opencode docs and schema before changing command, agent, plugin, skill, permission, or config shapes.
- Keep edits small and targeted.
- Prefer deterministic script helpers over agent reasoning for mechanical repository facts such as changed-file lists, instruction word/paragraph counts, metadata summaries, duplicate scans, validation scope, and structural linting.
- Read `.opencode/docs/policy-sources.toml` before changing policy ownership or copied docs. Preserve its classifications, precedence, source paths, dates, and declared overlays.
- Keep local creation constraints only in `.opencode/docs/local/workflow-profile.md`. Component skills reference it; agents keep sequencing, interaction gates, and response shapes.
- Keep the four-way contract audit only in `tb2-tests`, feedback classification/repair only in `tb2-feedback-iterator`, task.toml mechanics only in `tb2_metadata.py`, and the positive verifier runner only in `.opencode/templates/tests/test.sh`.
- Preserve the separation of responsibilities between orchestrator, builder, updater, maintainer, skills, plugin hooks, and scripts.
- Preserve the profile and component-skill gates; platform field answers must remain humanized.

## Syntax Reminders

- Commands live at `.opencode/commands/<name>.md` and use frontmatter plus body template.
- Command frontmatter may include `description`, `agent`, `model`, `variant`, and `subtask`. Do not put `template:` in markdown frontmatter.
- Agents live at `.opencode/agents/<name>.md`; body is the prompt.
- Agent `mode` is `primary`, `subagent`, or `all`.
- Agent permissions use opencode permission keys such as `read`, `edit`, `bash`, `task`, `question`, `webfetch`, and `skill`.
- Skills live at `.opencode/skills/<name>/SKILL.md` and require `name` and `description` frontmatter.
- Plugins live at `.opencode/plugins/*.ts` or `.js` and export an opencode plugin function.

## Validation

- `opencode agent list` after opencode command, agent, skill, or plugin edits.
- `bun --check .opencode/plugins/<file>.ts` after TypeScript plugin edits.
- `bash -n .opencode/scripts/*.sh` after shell edits.
- `bash -n .opencode/templates/tests/test.sh` after verifier-template edits.
- `python3 -m py_compile .opencode/scripts/*.py` after Python edits.

## Workflow Git History

- `.opencode` is its own git repo for workflow history.
- After validation passes, inspect status, diff, and recent log with `git -C .opencode ...`.
- Stage only intended workflow files.
- Commit every completed workflow update with a multi-line message that includes `Issue:`, `Changed:`, and `Validation:`.
- Do not commit blocked or empty updates, and do not push.

## Final Response

Use the maintainer agent's final response shape and include a short `Details` list explaining what changed in each touched workflow file and why. Include the workflow git commit hash when a commit was created.
