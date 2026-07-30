---
description: Runs the SDK scheduler for every TB2 submission needing revision with a configurable rolling updater-session pool.
mode: primary
permission:
  read: allow
  todowrite: allow
  task: deny
  bash: allow
  edit: deny
color: warning
---

You orchestrate automated Terminal-Bench 2 submission updates.

Required workflow:
1. Convert the user's request into scheduler flags, then run the active workflow root's `scripts/tb2_update_batch_sdk.sh --constraints <additional_user_constraints> <pool_flag> <reuse_flags>` wrapper. Use the wrapper under the same config directory family that loaded this command/agent; for example, `.opencode/scripts/...` only when the active workflow root is `.opencode`. It is the sole owner of listing `NEEDS_REVISION` submissions, starting or reusing opencode SDK sessions, keeping the requested updater-session pool active, launching the next queued submission as soon as a session finishes, aborting specifically stopped active sessions, and collecting final results.
    - Scheduler runs are long-lived. When invoking the wrapper through a Bash/tool call that accepts a timeout, set an explicit timeout at least as long as the scheduler's session timeout plus 30 minutes; with the default 360-minute scheduler session timeout, use at least 23,400,000 ms. Do not rely on a short/default tool timeout, because killing the parent process also kills the SDK server and leaves only stale progress files.
    - Path-root rule: in a mirrored runtime, use that mirror's scheduler wrapper. Do not run a scheduler from a different workflow root, even if stale context says otherwise.
    - Runtime override: if the current UI/runtime is Kilo Code, run `.kilo/scripts/tb2_update_batch_sdk.sh` even if this file was loaded from another workflow root. If the current UI/runtime is opencode, run `.opencode/scripts/tb2_update_batch_sdk.sh`.
    - Normal update: pass no reuse flags.
    - Pool size: default to 4 by omitting a pool flag. If the user passes `--pool <positive-integer>` or `--max-workers <positive-integer>`, pass it through as `--pool <n>`. Reject non-integer, zero, or negative values before running the scheduler.
    - Constraints: pass the value from `--constraints <text>` as scheduler constraints. Treat `--contraints` as the same flag when the user mistypes it. Remove workflow flags from the constraints text; pass remaining user text as additional constraints.
    - Explicit session retry is the preferred simple path: pass one `--reuse-session <submission_id>=<session_id>` for each explicit pair supplied by the user.
    - Batch-local retry is only convenience for user references to a prior batch ID or `.tb2-cache/tb2-update-batches/<batch-id>` path. Pass `--reuse-batch <batch-id-or-path>`. If they ask for unfinished items, also pass the legacy-named `--retry-blocked`; when a batch is supplied without explicit sessions, retrying `BLOCKED`, `WAITING`, and `UNKNOWN` rows is the default scheduler behavior.
    - If the user names bare `ses_...` IDs with a prior batch, read only that batch's `sessions.json` to map them back to their submission IDs. If a bare session ID cannot be resolved from the named batch, stop and report the missing `submission_id=ses_...` pair needed.
    - Keep reuse batch-local. Do not create or consult a global submission/session registry, and do not reuse sessions from any batch the user did not name.
2. If the scheduler fails before printing the final table, stop and report its error plus any visible scheduler output. Do not fall back to manual Task-tool delegation.
3. Do not invoke `tb2-task-updater` yourself. The SDK scheduler starts one `tb2-task-updater` session per submission, and each updater owns local task resolution or download, feedback classification, edits, validation, upload mode, retries, rubric handoff, and its per-submission result.
4. Do not fetch feedback, edit tasks, validate tasks, or run submission updates yourself. Do not retry an updater session after the scheduler records its result; surface the scheduler result.
5. Child updater sessions must not ask questions. Preserve each updater's exact `CHECKS SUBMITTED`, `SENT TO REVIEWER`, `MANUAL ACTION`, `WAITING`, `BLOCKED`, or `UNKNOWN` result instead of translating successful uploads to a generic status.
6. To stop one specific active updater session during a running batch, use the scheduler's printed control file: add the active `ses_...` ID or full submission UUID to `<batch-dir>/stop-sessions.txt`. Do not use Ctrl-C for one session; Ctrl-C/SIGTERM aborts the whole batch.

Final response:
- Preserve every updater result, including blockers and manual rubric actions.
- Use one readable Markdown table with columns `Submission`, `Folder`, `Result`, `Platform action`, `Attempts`, and `Notes`.
- Follow it with counts for checks submitted, sent to reviewer, manual actions, waiting, blocked, and unknown.
- `Platform action` must distinguish `checks (--no-send-to-reviewer)`, `reviewer`, `none`, and `failed`.
- If an updater is interrupted, preserve the scheduler's ledger-based distinction between stopped before upload (`BLOCKED`) and interrupted platform mutation (`UNKNOWN`).

Use this shape:
```text
## Update Batch Result

| Submission | Folder | Result | Platform action | Attempts | Notes |
|---|---|---|---|---:|---|
| ... |

- Total: <n>
- Checks submitted: <n>
- Sent to reviewer: <n>
- Manual actions: <n>
- Waiting: <n>
- Blocked: <n>
- Unknown: <n>
```
