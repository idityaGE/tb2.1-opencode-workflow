# Local TB2 Workflow Profile

This file owns repository-specific task-creation policy. Resolve source conflicts through `.opencode/docs/policy-sources.toml`; component skills may summarize this profile but must not redefine it.

## Net-new task profile

- Create only honestly rated `medium` or `hard` tasks.
- The implementation and oracle language must be non-Python. Python is reserved for pytest verifier tooling.
- Use regular or UI tasks with `number_of_milestones = 0`; net-new milestone tasks are blocked.
- Build difficulty from multi-step, interacting hidden failure layers rather than prompt volume, obscurity, or hints. The task-quality details live in `tb2-hard-task-author`.
- Keep `instruction.md` to at most three prose paragraphs and 300 words. Prefer 180-250 words when the full public contract still fits.

These are net-new creation constraints. During `/update-task`, preserve valid grandfathered difficulty, language, category, and milestone metadata unless concrete feedback or the user requires a change.

## Validation profile

- New tasks use create context: run preflight and then full structural, ruff, NOP, and oracle validation.
- After full validation, new tasks must pass the static review in `terminal-bench-e2-review-prompt.md`. A clean review requires `VERDICT: ACCEPT` with zero high, medium, and low failures; `NEEDS-DATA` items do not block creation. Send every failure to the builder and repeat full validation and static review until clean or concretely blocked.
- Revisions use revision context. Ask `tb2_task_state.sh` for the validation mode. `fast-only` is limited to root `instruction.md` and/or `task.toml` changes against unchanged runtime files; all runtime-affecting changes use full validation.
- NOP must earn 0 because required behavior is absent, not because infrastructure failed. Oracle must earn 1 against the same verifier.
- `.opencode/scripts/tb2_task_lint.py` and `.opencode/scripts/tb2_metadata.py` enforce mechanical policy. Skills own semantic review; agents only sequence those checks and report their outcomes.

## Mechanical sources

- `.opencode/scripts/tb2_metadata.py` owns the task.toml schema/defaults used here, live category status, repository-to-platform category labels, allowed subcategories, and exact codebase-size bands.
- `.opencode/templates/tests/test.sh` is the only local positive verifier-runner template. Copied documentation may explain verifier semantics or show bad examples, but its runner bodies are not generation sources.
- `tb2-tests` owns the four-way public-contract/oracle/verifier/NOP audit.
- `tb2-feedback-iterator` owns feedback classification and repair policy.
