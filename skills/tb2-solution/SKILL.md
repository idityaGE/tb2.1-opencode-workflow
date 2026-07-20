---
name: tb2-solution
description: Write deterministic Terminal-Bench oracle solution/solve.sh scripts that derive the fix through commands and pass the verifier.
---

# TB2 Solution

Use when writing `solution/solve.sh`.

Requirements:
- Make the script executable, deterministic, and idempotent. Prefer `#!/bin/bash` with `set -euo pipefail` when practical.
- Before finalizing, enumerate every requirement in `instruction.md` and every normative clause in each explicitly referenced agent-visible README/spec/rule file. The oracle must satisfy the complete public contract, including requirements not yet covered by a test; repair either the oracle or the contract when an obligation is missing or contradictory.
- Derive the fix and all required outputs through real commands such as edits, builds, generators, or task-native tools. The oracle must implement the required behavior rather than merely manufacture an accepted artifact.
- Do not hardcode final verifier outputs, answer files, reward files, visible-fixture answers, or constants copied from test expectations.
- Match runtime network use to `allow_internet`: use none when false, and only the task's genuine need when true. Avoid wall-clock time, unseeded randomness, unstable external results, and host-specific state.
- Helper files under `solution/` are allowed when they make the command-derived repair clearer.
- Keep it understandable enough to audit.
- It must pass the same tests used for agents, but a passing score is not sufficient evidence of completeness: review the oracle against the full public contract clause by clause.
