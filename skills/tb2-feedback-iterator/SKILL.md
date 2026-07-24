---
name: tb2-feedback-iterator
description: Classify Terminal-Bench 2 feedback, repair and recheck failures, send clean tasks to review, or prepare a manual rubric handoff.
---

# TB2 Feedback Iterator

Use for each submission delegated by the automated `/update-task` batch.

## Classification policy

- Fetch with `.opencode/scripts/tb2_status_iterate.sh --submission-id <submission_id>`. Inspect its full stdout/stderr as feedback evidence, especially any `Revision notes` section, then inspect the `Feedback directory:` if one is printed before classifying anything.
- In the feedback directory, read `notes.txt` first, then `agent_review.txt` when present, then focused evidence in `agent_logs/summary-of-runs-comment.md` and `agent_logs/jobs/**`. For an oracle failure, inspect the oracle job `result.json`, verifier outputs, and job logs instead of guessing from the summary.
- Treat concrete reviewer notes, including stdout/stderr `Revision notes`, quality/CI/LLMaJ findings, downloaded artifacts, rubric findings, and NOP/oracle or agent-run evidence as actionable.
- Ignore `AutoEval Execution Summary: AutoEval execution failed...` lines in `Revision Notes`; they are not reviewer instructions. Still investigate independent oracle, quality, build, or test failures elsewhere in the feedback.
- Ignore category-change warnings unless the user explicitly asks to change category. The revision profile preserves valid grandfathered category, language, difficulty, and milestone metadata.
- Treat the task's `easy` metadata, concrete easy/trivial platform feedback, or an explicit user request to harden an easy/trivial task as an actionable hardness finding. User-requested hardening does not require a matching reviewer note.
- Run `python3 .opencode/scripts/tb2_update_state.py inspect --submission-id <submission_id> --notes-file <feedback_dir>/notes.txt` before classifying revision notes. A `new` concrete note is actionable. An `addressed` note is persistent platform text from a prior successful checks upload and must not be repaired again unless current evidence shows the fix regressed. This cache-backed hash is how the workflow distinguishes stale reviewer text from new notes.
- Classify every actionable item before editing and summarize the evidence. Every new concrete issue from reviewer `Revision notes` must appear in the pre-edit `Problem` table even if agent-log summaries or downloaded files do not repeat it. Do not hide an issue that cannot be repaired.

## Platform action decision

Choose exactly one action after reading all evidence:

- `repair-and-check` when any of these is present: `TRIVIAL` or `EASY`; an explicit failed-difficulty message; no successful real-agent run; a non-solvable status; oracle failure; any failed quality check other than `not_applicable`; or a new actionable reviewer note. Repair all supported issues, validate, and upload with `--no-send-to-reviewer`.
- `send-to-reviewer` only when difficulty is `MEDIUM` or `HARD`, status says at least one agent run passed all tests, every quality check passes or is `not_applicable`, no new reviewer note remains, and no rubric handoff is pending. `Task Instruction Sufficiency: FAIL` alone does not block this action. A top-level `WARNING` in `agent_review.txt` also does not block it when the report contains no failing issue; warnings and suggestions alone do not require edits.
- `rubric-handoff` when rubric correction is the only remaining issue or the state helper reports `rubric_pending=true` after all non-rubric checks pass. Do not run the update helper; return the replacement-rubric path for manual platform paste and submission.
- `blocked` when evidence is incomplete or required repair/validation cannot pass. Never infer a green state from missing sections.

If rubric and non-rubric issues coexist, choose `repair-and-check`, prepare and mark the rubric replacement during that run, and upload the task for checks. On a later batch, persistent addressed notes are ignored, but `rubric_pending=true` forces `rubric-handoff` instead of automatic reviewer submission.

## Repair policy

- For ordinary feedback repair, fix only issues supported by feedback. A hardness finding explicitly authorizes major, core-preserving changes beyond the listed reviewer defects.
- For a hardness finding, make honest hard difficulty the primary repair goal. Apply the private blueprint and hardness gates in `tb2-hard-task-author`; do not stop after superficial complexity or after fixing only the reviewer-listed files. Add, replace, or deepen interacting hidden failure layers, runtime behavior, environment code, oracle logic, and behavioral verifier coverage as needed. Preserve the task's domain and objective where they remain viable, but do not preserve an easy implementation shape merely to minimize the diff.
- Treat instruction sufficiency as a co-equal blocking goal during hardening. Every added observable behavior must be stated neutrally in `instruction.md` or an explicitly referenced approved contract, while hidden defects, repair steps, and test-shaped hints remain undisclosed. Re-run the `tb2-tests` four-way audit after all contract, runtime, oracle, or verifier changes.
- For instruction sufficiency, state the missing observable requirement neutrally. If that clarification would expose the seeded repair, remove hint-like wording and deepen the implementation/verifier with another contract-grounded hidden interaction before validation.
- Do not weaken tests unless they are unfair, flaky, outside the public contract, or contradicted by platform feedback.
- Load `tb2-instruction` for prompt changes, `tb2-tests` for any public-contract/oracle/verifier change, `tb2-solution` for oracle changes, and `tb2-hard-task-author` for task-shape or environment-contract changes. The four-way audit is defined only in `tb2-tests`; invoke it rather than restating it here.
- If `tests/test.sh` changes on a regular task, restore it from `.opencode/templates/tests/test.sh`. Preserve the task-specific pytest path for grandfathered milestone revisions.

## Platform rubric policy

- Do not ask the user for the platform rubric. Read `.opencode/docs/tb2/rubrics.md`, the task contract, verifier, and relevant agent logs, create `.opencode/cache/tb2-rubrics/` if needed, then write a complete replacement to `.opencode/cache/tb2-rubrics/<submission_id>.txt`.
- For a regular zero-milestone task, write one flat list without `# Rubric N` blocks. Include at least three distinct negative criteria. Format each line as `Agent …, ±N`, where `N` is 1, 2, 3, or 5 and positive scores include `+`.
- Keep positive criteria between 10 and 40 points total. Merge or trim overlapping lower-value positives when needed, without dropping reviewer-visible coverage or adding solution hints.
- Criteria must assess trace-evidenced engineering behavior rather than ordinary pytest execution, final-test outcomes, or reading automatically supplied task files. Make them task-specific and consistent with the copied rubric guidance.
- Mark the handoff with `python3 .opencode/scripts/tb2_update_state.py mark-rubric --submission-id <submission_id> --rubric-file .opencode/cache/tb2-rubrics/<submission_id>.txt`. If rubric text is the only concrete issue, do not update task files or run `stb submissions update`; tell the user to paste the file, uncheck rubric generation, and send the task from the platform.

## Execution and validation

- Use the task path returned by `.opencode/scripts/tb2_resolve_submission_task.sh`; the updater runs this first so a missing local task is downloaded into `tasks/`. If the helper reports ambiguous local candidates, return them to the parent as `WAITING` rather than asking from the subagent. Run `.opencode/scripts/tb2_task_state.sh --task tasks/<task_name> --write-cache` before and after edits.
- Follow `.opencode/docs/local/workflow-profile.md`. For `fast-only`, run `.opencode/scripts/tb2_preflight_task.sh --context revision --task tasks/<task_name>` and perform the semantic checks owned by the loaded component skills. For `full`, run `.opencode/scripts/tb2_validate_task.sh --context revision --task tasks/<task_name>` until it passes or a concrete blocker remains.
- Never run local frontier/real-agent evaluations, including `stb harbor run -m ...`, during this workflow. NOP and oracle runs required by full validation remain allowed. Report hardening from task-shape and contract evidence without claiming an empirically measured pass rate.
- For `repair-and-check`, run `.opencode/scripts/tb2_update_task.sh --task tasks/<task_name> --submission-id <submission_id>` only after applicable validation passes. After success, record addressed notes with `python3 .opencode/scripts/tb2_update_state.py record-notes --submission-id <submission_id> --notes-file <feedback_dir>/notes.txt --upload-mode checks --task tasks/<task_name>`.
- For `send-to-reviewer`, make no feedback-driven edits, run fast preflight, then add `--send-to-reviewer` to the update helper. Never follow it with a checks upload.
- The update helper retries transient `stb submissions update` failures at most five times in one mode. It does not retry or count a platform static-check rejection. When it reports `update_static_checks=failed`, treat the full platform output as repair evidence, fix every reported task issue, rerun applicable validation, and invoke the helper again; never resubmit unchanged files. Continue until checks pass or a concrete blocker remains. If upload prep changes files, validate again before invoking the helper.
- Never update after failed validation, never run both platform modes for one fetched result, and never run `stb submissions create` from this workflow.
