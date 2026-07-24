---
description: Process all TB2 submissions needing revision with the rolling SDK updater scheduler.
agent: tb2-update-task-orchestrator
---

# /update-task

Process every Terminal-Bench 2 submission currently in `NEEDS_REVISION` through the rolling SDK updater scheduler, or reuse updater sessions from an explicitly named prior batch/session.

Additional user constraints: `$ARGUMENTS`

Follow the `tb2-update-task-orchestrator` agent instructions as the workflow source of truth. Pass constraints and any explicit batch/session reuse request through, then return the agent's final response shape.
