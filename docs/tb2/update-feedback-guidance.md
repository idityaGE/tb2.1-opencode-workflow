# Update Feedback Guidance

Use this file during `/update-task` after reading platform feedback and before editing the task.

## Ignore

- Ignore generic AutoEval build-summary lines by themselves, including:
  `AutoEval Execution Summary: AutoEval execution failed. Build status: FAILED. Build ID: CodeExecutionEnvironment:<uuid>.`
- Ignore category-change warnings, including requests to change `task.toml` category such as `data-processing` vs `debugging`, unless the user explicitly asks to change category.

## Focus

- If feedback says the task is trivial or agents solve it too easily, make the task harder while preserving the same core concept. Add layered, hidden failure modes and behavioral verifier coverage rather than hints or superficial complexity.
- If feedback identifies an `instruction.md` issue, fix the prompt so required behavior is specified fairly without revealing bug locations, solution steps, or names that signpost the seeded bugs.
- When only regular or milestone `instruction.md` and/or root `task.toml` files are dirty or changed and no other local fix is required, run structural lint plus prompt/test/oracle alignment for instruction edits and metadata consistency checks for task.toml edits. Do not execute NOP or oracle for this fast-only case. Any runtime-affecting dirty or changed task file requires full validation.
- Prioritize concrete reviewer notes, quality-check findings, CI/LLMaJ evidence, NOP/oracle logs, and downloaded artifacts over generic platform wrapper messages.
- Keep fixes targeted. Do not redesign the task unless feedback proves it is unsalvageable.

## Common feedback patterns

Append reusable update lessons here only after the user approves at the end of `/update-task`.
Use concise bullets in this shape: `- Problem: ... Fix: ...`
