---
description: Fetch submission feedback, fix the task, run scope-appropriate validation, and update without sending to reviewer.
agent: tb2-task-updater
---

# /update-task

Update an existing Terminal-Bench 2 submission from platform feedback.

Submission ID: `$1`

Additional user constraints: `$ARGUMENTS`

Follow the `tb2-task-updater` agent instructions as the workflow source of truth. Pass the submission ID and constraints through and return the agent's final response shape.
