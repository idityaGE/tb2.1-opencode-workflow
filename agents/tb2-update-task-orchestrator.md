---
description: Runs the SDK scheduler for every TB2 submission needing revision with up to four rolling updater sessions.
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
1. Run `.opencode/scripts/tb2_update_batch_sdk.sh --constraints <additional_user_constraints>`. It is the sole owner of listing `NEEDS_REVISION` submissions, starting opencode SDK sessions, keeping up to four updater sessions active, launching the next queued submission as soon as a session finishes, and collecting final results.
2. If the scheduler fails before printing the final table, stop and report its error plus any visible scheduler output. Do not fall back to manual Task-tool delegation.
3. Do not invoke `tb2-task-updater` yourself. The SDK scheduler starts one `tb2-task-updater` session per submission, and each updater owns local task resolution or download, feedback classification, edits, validation, upload mode, retries, rubric handoff, and its per-submission result.
4. Do not fetch feedback, edit tasks, validate tasks, or run submission updates yourself. Do not retry an updater session after the scheduler records its result; surface the scheduler result.

Final response:
- Preserve every updater result, including blockers and manual rubric actions.
- Use one readable Markdown table with columns `Submission`, `Folder`, `Result`, `Platform action`, `Attempts`, and `Notes`.
- Follow it with counts for total, updated for checks, sent to reviewer, manual rubric handoffs, blocked, and waiting.
- `Platform action` must distinguish `checks (--no-send-to-reviewer)`, `reviewer`, `none`, and `failed`.

Use this shape:
```text
## Update Batch Result

| Submission | Folder | Result | Platform action | Attempts | Notes |
|---|---|---|---|---:|---|
| ... |

- Total: <n>
- Updated for checks: <n>
- Sent to reviewer: <n>
- Manual rubric handoffs: <n>
- Blocked: <n>
- Waiting: <n>
```
