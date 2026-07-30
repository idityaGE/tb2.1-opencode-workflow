---
name: tb2-feedback-iterator
description: Classify Terminal-Bench 2 feedback, persist update history, repair and recheck failures, send clean tasks to review, or prepare a manual rubric handoff.
---

# TB2 Feedback Iterator

Use for each submission delegated by `/update-task` or `/update-one-task`. This skill owns update classification and repair policy. The updater must perform the complete flow itself; do not invoke a separate reviewer or run local Claude/OpenAI/frontier difficulty evaluations.

## Authoritative state machine

### A. Fetch and record complete feedback

1. Run `.opencode/scripts/tb2_status_iterate.sh --submission-id <submission_id>` and preserve its stdout/stderr.
2. In the reported feedback directory read, in order: `notes.txt`; `agent_review.txt` when present; `agent_logs/summary-of-runs-comment.md`; focused `agent_logs/jobs/**` evidence when an oracle, verifier, build, or named-test result needs confirmation. Inspect iteration history with `python3 .opencode/scripts/tb2_update_state.py inspect --submission-id <submission_id>`.
3. Record the fetched facts before editing:
   ```text
   python3 .opencode/scripts/tb2_update_state.py record-feedback \
     --submission-id <submission_id> --feedback-dir <feedback_dir> --task tasks/<task_name>
   ```
   Pass scheduler batch/session provenance when available. Use its mechanical difficulty, solvability, pass-count, quality, normalized-note, fingerprint, completeness, hardening-level, and cycle-aware note-status output as facts, not as repair classification.

### B. Remove platform noise

The revision-note line `AutoEval Execution Summary: AutoEval execution failed. Build status: FAILED...` is platform noise. Every exact line with that AutoEval failure prefix is excluded from normalized notes and their hash. It must never appear in the Problem table, trigger a repair or Docker/build change, or influence routing. Independent oracle/verifier failures, static-check failures, and concrete build logs outside that line remain actionable.

Category-change warnings remain non-actionable unless the user asks for a category change. Preserve valid grandfathered category, language, difficulty, and milestone metadata during revision.

### C. Require current, complete evidence

- Return `WAITING` without edits or upload when feedback has only ignored AutoEval text, lacks either a complete current difficulty/solvability/named-test/quality evaluation or concrete reviewer revision notes, or is still inside the cooldown with the same evaluation fingerprint as the latest checks upload.
- Do not upload pre-existing local changes, mark notes addressed, mutate the task, or infer that evaluation finished when feedback is incomplete or unrefreshed. If local provenance is ambiguous, return `WAITING` before editing or `BLOCKED` if safe attribution cannot be recovered.
- If the ledger contains an open/`UNKNOWN` platform attempt, fetch current platform state and reconcile it before any new upload. Never blindly retry an interrupted mutation.

### D. Choose exactly one action

#### `repair-and-check`

Choose this action when any applies:
- `EASY` or `TRIVIAL`, or an explicit difficulty failure;
- non-solvable status;
- any named test at `0 / N` (zero complete agent runs alone is not equivalent if every named test passed at least once);
- oracle failure;
- any quality failure other than `Task Instruction Sufficiency` or `not_applicable`;
- a new or reopened reviewer note in the current reviewer cycle;
- a concrete rubric defect combined with another actionable issue.

Repair every supported issue, run applicable local validation, record that validation, and upload in checks mode. The final result is `CHECKS SUBMITTED`, meaning only that platform reevaluation is pending. Never call the task fixed.

#### `send-to-reviewer`

Choose only when the latest complete platform evidence says all of the following:
- difficulty is `MEDIUM` or `HARD`;
- status is solvable;
- every named test passed in at least one run;
- every quality check passes or is `not_applicable`, except `Task Instruction Sufficiency: FAIL` may be the sole quality exception;
- no actionable reviewer note remains in the current cycle;
- no rubric handoff is pending.

Make no feedback-driven task edit, run unchanged-task fast preflight, record validation, and upload in reviewer mode. The final result is `SENT TO REVIEWER`. Sending increments `reviewer_cycle`; identical reviewer text returned in that new cycle is actionable again.

#### `rubric-handoff`

Choose only when every non-rubric platform check is green and rubric work is the sole remaining action. Write the complete replacement to `.tb2-cache/tb2-rubrics/<submission_id>.txt`, run `mark-rubric`, do not upload, and return `MANUAL ACTION`.

#### Waiting, blocked, or unknown

- `WAITING`: feedback is incomplete or unrefreshed.
- `BLOCKED`: a supported repair cannot be completed, hardening evidence fails, applicable validation fails, or upload definitively fails.
- `UNKNOWN`: a mutating platform call was interrupted and may have reached the platform.

## Reviewer-note cycles and history

- A normalized reviewer-note hash is stale only when it was addressed in the current `reviewer_cycle`. Difficulty, solvability, named-test, oracle, and quality evidence are never suppressed by a note hash.
- A checks upload records the current note hash with its cycle, task fingerprint, and submission time. A reviewer upload starts a new cycle. The same note in that later cycle is a reopened defect.
- The ledger at `.tb2-cache/tb2-updates/<submission_id>.json` is authoritative for observations, fingerprints, hardening escalation, validation, attempts, and outcomes. All helper writes are atomic.
- `migrate-batches --batch-root .tb2-cache/tb2-update-batches` imports legacy scheduler results without rewriting historical logs; it is safe to rerun.

## Repair and hardening

- Ordinary repairs stay tied to concrete feedback. A hardness finding authorizes major core-preserving redesign.
- For `EASY` or `TRIVIAL`, load `tb2-hard-task-author`, inspect available successful/near-success evidence, and follow its history-aware hardening rules. Write private evidence to `.tb2-cache/tb2-hardening/<submission_id>/<iteration>.json`, then run `record-hardening --submission-id ... --task ... --evidence-file ...`. Do not validate or upload until that mechanical gate passes.
- First `EASY`: invalidate the common successful strategy through an agent-visible runtime/source change and an orthogonal non-local defect family. First `TRIVIAL`: structurally redesign the starter failure topology.
- Repeated low difficulty marks the prior strategy empirically failed. Do not repeat additive fields, hashes, checkpoints, isolated validation rules, or instruction/test/oracle-only expansion. Restructure core agent-visible implementation and use multiple interacting root-cause families. There is no arbitrary platform-iteration cap, but block any iteration that cannot provide supported hardening evidence.
- Load `tb2-instruction` for prompt edits, `tb2-tests` for any contract/oracle/verifier change, `tb2-solution` for oracle edits, and `tb2-hard-task-author` for task-shape/runtime changes. The four-way audit remains defined only in `tb2-tests`.
- If `tests/test.sh` changes on a regular task, restore it from `.opencode/templates/tests/test.sh`. Do not weaken fair tests merely to improve agent scores.

## Hardening evidence contract

The private JSON must include: `prior_difficulty`, `prior_agent_performance`, `successful_trace_sources`, `common_success_strategy`, `prior_failed_hardening`, `starting_state_files_changed`, `defect_families`, `contract_changes`, and `removed_or_replaced_shallow_complexity`. Each defect family records `name`, `root_cause`, `source_delta`, `interacts_with`, `strategy_invalidated`, `oracle_signal`, and `verifier_signal`.

The state helper gate verifies current low feedback, available trace inspection, a real changed agent-visible source path, increasing escalation on repeated lows, a fingerprint different from the last checks upload, no instruction/test/oracle-only self-certification, existing claimed paths, oracle/verifier signals, and acknowledgement of failed prior strategies. It prevents unsupported claims but does not claim semantic difficulty.

## Rubric policy

- Do not ask the user for existing platform rubric text. Use `.opencode/docs/tb2/rubrics.md`, the task contract/verifier, and relevant traces to create a complete replacement.
- Regular zero-milestone tasks use one flat list with at least three distinct negative `Agent …, -N` criteria. Positive criteria total 10–40 points. Assess task-specific trace behavior, not ordinary pytest execution or supplied-file reading.
- If rubric and non-rubric issues coexist, prepare and mark the rubric during `repair-and-check`; only return `rubric-handoff` after fresh non-rubric evidence is green.

## Validation and upload

- Run `tb2_task_state.sh --write-cache` before and after edits. Use `tb2_preflight_task.sh --context revision` only for genuine `fast-only` changes; runtime-affecting work uses `tb2_validate_task.sh --context revision` with structural, mandatory Ruff, NOP, and oracle checks.
- Broad Ruff selectors remain advisory and separate from mandatory Ruff status. Local validation may claim structural validity, contract alignment, mandatory Ruff status, NOP result, and oracle result only. Say: `Local validation passed; platform difficulty and quality reevaluation pending.` Never claim local difficulty, empirical frontier-strategy invalidation, platform quality, or that the task is fixed.
- A repairable task-owned validation finding is another repair input, not a final blocker. Fix it and rerun the same applicable validation in the current session. Return `BLOCKED` only when the task-owned failure remains after a supported repair attempt or the failure is concretely outside updater ownership. Task validation must never fail because of Ruff findings in `.opencode`, `.kilo`, or another task.
- Record validation with `record-validation` before either upload mode. Run `.opencode/scripts/tb2_update_task.sh --task ... --submission-id ...` for checks or add `--send-to-reviewer` for reviewer mode. The helper owns fingerprints, an atomic begin/finish ledger entry for every invocation, cumulative iteration attempts, five transient retries per invocation, static/definitive failure records, and interruption-to-`UNKNOWN` handling.
- When the platform helper reports repairable static-check findings, treat its complete output as new repair evidence, repair the task, rerun validation, and invoke the same selected mode again. Do not return `BLOCKED` merely because the first validation or static-check attempt failed.
- Never run both upload modes for one fetched result, upload after failed validation, run `stb submissions create`, or invoke another reviewer agent.
