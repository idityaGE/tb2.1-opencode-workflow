---
description: Process all TB2 submissions needing revision with up to four parallel updater agents.
agent: tb2-update-task-orchestrator
---

# /update-task

Process every Terminal-Bench 2 submission currently in `NEEDS_REVISION`.

Additional user constraints: `$ARGUMENTS`

Follow the `tb2-update-task-orchestrator` agent instructions as the workflow source of truth. Pass the constraints through and return the agent's final response shape.
