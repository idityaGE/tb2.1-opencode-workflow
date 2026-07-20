---
name: tb2-feedback-iterator
description: Fetch Terminal-Bench 2 submission feedback, read the platform-created feedback directory, make targeted fixes, revalidate, and update without sending to reviewer.
---

# TB2 Feedback Iterator

Use after platform or CI feedback is available, especially from `/update-task <submission_id>`.

Workflow:
- Fetch feedback with `.opencode/scripts/tb2_status_iterate.sh --submission-id <submission_id>`. This helper runs `stb submissions feedback <submission_id>` and prints the feedback output.
- If the helper prints a `Feedback directory:` path, inspect that directory before classifying feedback or ignoring generic AutoEval wrapper text.
- Use `.opencode/docs/tb2/update-feedback-guidance.md` as the source of truth for ignore/focus rules before classifying feedback.
- Load `tb2-hard-task-author` and apply its targeted four-document policy check to each concrete feedback topic before classifying or editing.
- Summarize concrete failures before editing.
- If feedback is about the platform rubric, ask the user to paste the current platform rubric before rewriting it. For single-step tasks with zero milestones, convert `# Rubric 1` / `# Rubric 2` blocks into one flat list. Preserve the reviewer-required negative criteria; every criterion line must use `Agent …, ±N`, with `N` limited to 1, 2, 3, or 5 and an explicit `+` on positive scores. Keep positive points between 10 and 40 total; when merged positives exceed 40, trim or merge overlapping lower-value positives until the total is at most 40.
- After rewriting a platform rubric, copy the revised rubric to the clipboard with `wl-copy`. If this is the only concrete issue, do not run `stb submissions update`; tell the user to paste the copied rubric into the platform.
- Locate the matching local task under `tasks/`; ask only if it cannot be inferred.
- Fix only issues supported by feedback.
- Preserve the task's honest medium or hard difficulty, layered hidden bugs, non-Python implementation, and no-hint/no-bug-signposting constraints.
- Before editing any `instruction.md`, or whenever feedback notes include `Task Instruction Sufficiency: ❌ FAIL`, load the `tb2-instruction` skill and follow it while applying the fix.
- Load `tb2-tests` when feedback concerns coverage or tested-but-undescribed behavior, or when `instruction.md`, an approved agent-visible README/spec/rule file under `environment/`, or any verifier file may change. Use its canonical runner guidance for `tests/test.sh` and complete its private bidirectional coverage audit before validation.
- For instruction-sufficiency feedback, follow the updater agent's triviality-rescue path rather than adding hints.
- Follow `tb2-hard-task-author` for allowed agent-visible README/spec/rule files under `environment/`, including `environment/task_file/` sources copied to `/app`. Reference every public document by its absolute in-container path from `instruction.md`; keep the prompt domain-framed and keep supporting documents necessary, realistic, and free of repair guidance or hidden-failure clues.
- Use `.opencode/scripts/tb2_task_state.sh --task tasks/<task_name> --write-cache` before and after edits to get changed files and validation mode.
- If mode is `fast-only`, run `.opencode/scripts/tb2_preflight_task.sh --task tasks/<task_name>` and check prompt/metadata alignment. If runtime files changed, use `full`.
- If mode is `full`, run `.opencode/scripts/tb2_validate_task.sh --task tasks/<task_name>` until structural lint passes, NOP fails as required, and oracle passes.
- Run `.opencode/scripts/tb2_update_task.sh --task tasks/<task_name> --submission-id <submission_id>` only after validation passes. The helper runs upload prep. If prep changes files, validate again and rerun it. If it succeeds, stop and report.
- Do not make broad redesigns unless feedback proves the current task is unsalvageable.
- Never update if the applicable fast-only or full validation fails.
