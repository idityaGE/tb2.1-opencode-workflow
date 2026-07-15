---
description: Modify and commit the TB2 workflow from a requested problem, improvement, or new capability.
agent: tb2-workflow-maintainer
---

# /modify-workflow

Modify the Terminal-Bench 2 task-creation workflow itself. The user's requested change is:

`$ARGUMENTS`

Follow the `tb2-workflow-maintainer` agent instructions as the workflow source of truth. Treat the user arguments as the requested change, make the smallest safe workflow edits, validate touched files, commit the completed workflow update, and return the agent's final response shape.
