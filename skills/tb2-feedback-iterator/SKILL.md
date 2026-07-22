---
name: tb2-feedback-iterator
description: Fetch Terminal-Bench 2 submission feedback, repair concrete issues or harden easy/trivial tasks, revalidate, and update without sending to reviewer.
---

# TB2 Feedback Iterator

Use after platform or CI feedback is available, especially from `/update-task <submission_id>`.

## Classification policy

- Fetch with `.opencode/scripts/tb2_status_iterate.sh --submission-id <submission_id>`. Inspect its full stdout/stderr as feedback evidence, especially any `Revision notes` section, then inspect the `Feedback directory:` if one is printed before classifying anything.
- Treat concrete reviewer notes, including stdout/stderr `Revision notes`, quality/CI/LLMaJ findings, downloaded artifacts, rubric findings, and NOP/oracle or agent-run evidence as actionable.
- Ignore a generic AutoEval execution-failed summary only after the feedback directory contains no concrete evidence behind it.
- Ignore category-change warnings unless the user explicitly asks to change category. The revision profile preserves valid grandfathered category, language, difficulty, and milestone metadata.
- Treat the task's `easy` metadata, concrete easy/trivial platform feedback, or an explicit user request to harden an easy/trivial task as an actionable hardness finding. User-requested hardening does not require a matching reviewer note.
- Classify every actionable item before editing and summarize the evidence. Every concrete issue from reviewer `Revision notes` must appear in the pre-edit `Problem` table even if agent-log summaries or downloaded files do not repeat it. Do not hide an issue that cannot be repaired.

## Repair policy

- For ordinary feedback repair, fix only issues supported by feedback. A hardness finding explicitly authorizes major, core-preserving changes beyond the listed reviewer defects.
- For a hardness finding, make honest hard difficulty the primary repair goal. Apply the private blueprint and hardness gates in `tb2-hard-task-author`; do not stop after superficial complexity or after fixing only the reviewer-listed files. Add, replace, or deepen interacting hidden failure layers, runtime behavior, environment code, oracle logic, and behavioral verifier coverage as needed. Preserve the task's domain and objective where they remain viable, but do not preserve an easy implementation shape merely to minimize the diff.
- Treat instruction sufficiency as a co-equal blocking goal during hardening. Every added observable behavior must be stated neutrally in `instruction.md` or an explicitly referenced approved contract, while hidden defects, repair steps, and test-shaped hints remain undisclosed. Re-run the `tb2-tests` four-way audit after all contract, runtime, oracle, or verifier changes.
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
- Never run local frontier/real-agent evaluations, including `stb harbor run -m ...`, during this workflow. NOP and oracle runs required by full validation remain allowed. Report hardening from task-shape and contract evidence without claiming an empirically measured pass rate.
- Run `.opencode/scripts/tb2_update_task.sh --task tasks/<task_name> --submission-id <submission_id>` only after applicable validation passes. If upload prep changes files, validate again before retrying. Stop after success.
- Never update after failed validation, never omit `--no-send-to-reviewer`, and never run `stb submissions create` from this workflow.
