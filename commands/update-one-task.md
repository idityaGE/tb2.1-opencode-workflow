---
description: Process one TB2 submission by its submission ID.
agent: tb2-task-updater
---

# /update-one-task

Process exactly one Terminal-Bench 2 submission from its platform feedback.

Submission ID: `$1`

Additional user constraints: `$ARGUMENTS`

Follow the `tb2-task-updater` agent instructions as the workflow source of truth. Process only the supplied submission ID and return the agent's final response shape.
