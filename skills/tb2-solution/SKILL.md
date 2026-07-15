---
name: tb2-solution
description: Write deterministic Terminal-Bench oracle solution/solve.sh scripts that derive the fix through commands and pass the verifier.
---

# TB2 Solution

Use when writing `solution/solve.sh`.

Requirements:
- Make the script executable, deterministic, and idempotent. Prefer `#!/bin/bash` with `set -euo pipefail` when practical.
- Derive the fix through commands such as edits, builds, generators, or repair tools.
- Do not hardcode final verifier outputs, answer files, or reward files.
- Do not depend on network access at runtime. Avoid wall-clock time, unseeded randomness, and host-specific state.
- Helper files under `solution/` are allowed when they make the command-derived repair clearer.
- Keep it understandable enough to audit.
- It must pass the same tests used for agents.
