---
description: Process all TB2 submissions needing revision with the rolling SDK updater scheduler.
agent: tb2-update-task-orchestrator
---

# /update-task

Process every Terminal-Bench 2 submission currently in `NEEDS_REVISION` through the rolling SDK updater scheduler, or reuse updater sessions from an explicitly named prior batch/session. The default pool is 4 active updater sessions; pass `--pool <n>` to override it for this invocation.

Additional user constraints: `$ARGUMENTS`

Runtime routing guard: if this command is executed in Kilo Code, the scheduler path is `.kilo/scripts/tb2_update_batch_sdk.sh` even if older context mentions another workflow root.

Follow the `tb2-update-task-orchestrator` agent instructions as the workflow source of truth. Pass constraints and any explicit batch/session reuse request through, then return the agent's final response shape.
