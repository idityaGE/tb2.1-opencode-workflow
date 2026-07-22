---
name: tb2-feedback-iterator
description: Fetch Terminal-Bench 2 submission feedback, read the platform-created feedback directory, make targeted fixes, revalidate, and update without sending to reviewer.
---

# TB2 Feedback Iterator

Use after platform or CI feedback is available, especially from `/update-task <submission_id>`.

## Classification policy

- Fetch with `.opencode/scripts/tb2_status_iterate.sh --submission-id <submission_id>`. Inspect its full stdout/stderr as feedback evidence, especially any `Revision notes` section, then inspect the `Feedback directory:` if one is printed before classifying anything.
- Treat concrete reviewer notes, including stdout/stderr `Revision notes`, quality/CI/LLMaJ findings, downloaded artifacts, rubric findings, and NOP/oracle or agent-run evidence as actionable.
- Ignore a generic AutoEval execution-failed summary only after the feedback directory contains no concrete evidence behind it.
- Ignore category-change warnings unless the user explicitly asks to change category. The revision profile preserves valid grandfathered category, language, difficulty, and milestone metadata.
- Classify every actionable item before editing and summarize the evidence. Every concrete issue from reviewer `Revision notes` must appear in the pre-edit `Problem` table even if agent-log summaries or downloaded files do not repeat it. Do not hide an issue that cannot be repaired.

## Repair policy

- Fix only issues supported by feedback. Preserve the core concept and avoid broad redesign unless the evidence proves the task is unsalvageable.
- Preserve layered difficulty, fair public requirements, and freedom from hints. If feedback says the task is trivial, deepen behavioral interactions and verifier coverage rather than adding superficial complexity.
- For instruction sufficiency, state the missing observable requirement neutrally. If that clarification would expose the seeded repair, remove hint-like wording and deepen the implementation/verifier with another contract-grounded hidden interaction before validation.
- Do not weaken tests unless they are unfair, flaky, outside the public contract, or contradicted by platform feedback.
- Load `tb2-instruction` for prompt changes, `tb2-tests` for any public-contract/oracle/verifier change, `tb2-solution` for oracle changes, and `tb2-hard-task-author` for task-shape or environment-contract changes. The four-way audit is defined only in `tb2-tests`; invoke it rather than restating it here.
- If `tests/test.sh` changes on a regular task, restore it from `.opencode/templates/tests/test.sh`. Preserve the task-specific pytest path for grandfathered milestone revisions.

## Platform rubric policy

- Ask the user in normal chat to paste the current platform rubric exactly; do not use `question` for multiline rubric text.
- For a regular zero-milestone task, remove `# Rubric N` blocks and return one flat list. Preserve required negative criteria. Format each line as `Agent …, ±N`, where `N` is 1, 2, 3, or 5 and positive scores include `+`.
- Keep positive criteria between 10 and 40 points total. Merge or trim overlapping lower-value positives when needed, without dropping reviewer-visible coverage or adding solution hints.
- Show the revision and copy exactly it with `wl-copy`. If rubric text is the only concrete issue, do not update task files or run `stb submissions update`; tell the user to paste it manually.

## Execution and validation

- Locate the matching task, asking only when it cannot be inferred. Run `.opencode/scripts/tb2_task_state.sh --task tasks/<task_name> --write-cache` before and after edits.
- Follow `.opencode/docs/local/workflow-profile.md`. For `fast-only`, run `.opencode/scripts/tb2_preflight_task.sh --context revision --task tasks/<task_name>` and perform the semantic checks owned by the loaded component skills. For `full`, run `.opencode/scripts/tb2_validate_task.sh --context revision --task tasks/<task_name>` until it passes or a concrete blocker remains.
- Run `.opencode/scripts/tb2_update_task.sh --task tasks/<task_name> --submission-id <submission_id>` only after applicable validation passes. If upload prep changes files, validate again before retrying. Stop after success.
- Never update after failed validation, never omit `--no-send-to-reviewer`, and never run `stb submissions create` from this workflow.
