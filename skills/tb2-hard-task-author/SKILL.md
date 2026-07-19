---
name: tb2-hard-task-author
description: Design and author hard Terminal-Bench 2 tasks in any non-Python implementation language with concise instructions, deterministic oracle solutions, and pytest verifiers.
---

# TB2 Hard Task Author

Use when creating or revising a Terminal-Bench 2 task.

Defaults:
- Destination: `tasks/<task-name>` from the repository root.
- Visible workflow command: `/create-task`.
- Skeleton: regular/default unless UI is explicitly required; this workflow keeps `number_of_milestones = 0`.
- Implementation languages: any non-Python language. Python is only for pytest verifiers. Prefer Rust, C, C++, Go, Zig, Nim, Haskell, OCaml, Elixir/Erlang, Java/Kotlin/Scala, Ruby, Lua, Crystal, D, Racket, Fortran, Ada, or other non-Python languages when they fit the task.
- Allowed categories for this repo: `system-administration`, `build-and-dependency-management`, `games`, `machine-learning`, `security`, or `scientific-computing`. Do not use `software-engineering`, `debugging`, or `data-processing`; local lint blocks them for this workflow.
- Static validation may classify the task from `instruction.md` and other visible files. Make the primary activity genuinely match an allowed category; do not rely on `task.toml` alone to avoid blocked `software-engineering`, `debugging`, or `data-processing` predictions.
- Target difficulty: extremely hard. Hard means accuracy <= 20% on the best model or worst model. Tasks where the worst model scores above 80% are unacceptable.
- Bug shape: multi-step, multi-level, hidden bugs or layered failure modes. Hidden means not signposted in prompts, code comments, fixture names, tests, or specs; all required behavior must still be fairly specified.

Fast path:
- Treat this skill plus the component skills as the default policy cache for `/create-task`.
- Do not read broad TB2 docs unless a special case is not covered here or in a component skill.
- Use targeted docs only for UI tasks, rubric/platform exceptions, unclear Docker/verifier policy, obscure language behavior, or authoritative external specs. Web research is allowed during authoring, but runtime solving and verification must remain offline. Do not vendor source material or solver guides into the task; the narrow environment-contract exception below is only for a task-authored declarative contract.
- For duplicate checks, inspect task names, `task.toml` metadata, and only the first paragraph of likely-similar instructions.

Rotate across hard domains: numerical methods, crash-consistent storage, binary formats, concurrency, allocators, kernel-adjacent Linux behavior, protocol parsers, state-machine repair, build systems, VM/runtime behavior, and specification-heavy ecosystems.

Rules:
- Tasks must be multi-step, standalone, novel, deterministic, and solvable by an expert human.
- Avoid privileged operations, privileged containers, unsafe Docker capabilities, runtime human input, and live external dependencies.
- Keep component details in the component skills; use this skill for overall task shape, difficulty, language, category, and anti-hint policy.
- Follow the component skills for `task.toml`, Dockerfile, instructions, solution, tests, and field answers.
- Do not include solution hints, bug locations, exact answer values, final outputs, or bug-signposting comments in user-visible files. Do not help the agent identify or solve the bugs in any way.
- Default to no task-level or environment documentation. At most one contract file may be created, at exactly `environment/spec.md` or `environment/rule.md`, only when the task genuinely needs a declarative protocol, schema, or rule system that would otherwise be ambiguous, or when concrete reviewer feedback explicitly requests that file. Never create both. Nearing the instruction word limit is not a reason to create one, and reviewer feedback waives only the necessity test, not the realism, sufficiency, or no-hint rules. All other `README*`, docs directories, guides, manuals, notes, walkthroughs, specs, and reference excerpts remain prohibited.
- Avoid single-obvious-patch tasks; require multiple investigative steps and edge-case reasoning.
- Avoid generic repair framing such as "fix bugs", "implement missing logic", "repair the app", or "make tests pass". Also avoid data-processing framing such as "parse files", "transform data", "aggregate records", "process datasets", or "convert logs". Use truthful allowed-category framing instead, such as enforcing security policy, resolving dependency graphs, restoring service/config behavior, simulating game state, running ML inference/training, or producing scientific-computing outputs.

Sufficiency and difficulty guidance:
- Make the task fully specified while making the implementation/debugging path genuinely deep.
- Specify behavior, invariants, schemas, formats, and outputs; do not specify repair steps, bug files, or solution approach.
- Keep every prompt, goal, entrypoint, path, top-level success criterion, and invariant in `instruction.md`. An approved environment contract may define detailed declarative protocol, schema, or rule clauses, and `instruction.md` must name its absolute in-container path. It must read like a realistic engineering artifact and must not contain repair steps, execution order, bug locations, suggested commands, libraries, internal implementation guidance, seeded-case answers, or common-pitfall hints.
- Prefer non-local failure chains across parser/state/build/runtime layers so fixes require tracing interactions.
- Use natural edge cases implied by the contract, such as boundaries, empty inputs, duplicates, interrupted checkpoints, ordering ties, malformed-but-recoverable records, restart/replay, or numeric stability cases.
- Make hardcoding difficult with deterministic generated cases, multiple fixtures, semantic invariants, and independent reference checkers.
- Require the agent to derive and preserve a system invariant such as prefix safety, conservation, ordering, idempotence, replay determinism, or representation validity.
- Let simple happy paths pass while hidden tests exercise realistic boundary/recovery/reordering behavior.
- Avoid README/spec over-explaining; concise prompts plus realistic code are required, and any approved contract file must be necessary rather than a second prompt.
- Add realistic codebase context and noise only when it is functional, not blank filler or obfuscation.
- Favor domains frontier models often miss: crash recovery, binary parsers, protocol replay, state machines, concurrency ordering, undefined behavior, ownership/lifetime plus logic bugs, numerical stability, checkpoint/restart, allocator metadata, generated artifacts, and dependency/build resolution.
- If Harbor/static validation emits `[category_classifier]` with blocked `software-engineering`, `debugging`, or `data-processing`, redesign the visible task concept and prompt around a genuinely allowed category. Do not merely rename the category in `task.toml` or use misleading instruction wording to disguise a blocked task.

Red flags:
- Vague prompts, hidden requirements only in tests, arbitrary gotchas, misleading comments, one obviously broken function, prompt text that points to a file or bug, fixture/test names that reveal the edge case, procedural README/docs/spec walkthroughs, unnecessary contract files, helper notes, giant instruction dumps, dead-file noise, runtime internet dependence, or static expected outputs that can be hardcoded.

First-go hardness gates:
- Before authoring, make a private difficulty blueprint: bug layers, why agents miss them, evidence trail, oracle repair path, duplicate-risk note, and a defect-to-verifier map showing that each hidden layer can independently affect score. If using an environment contract, record why it is necessary or the exact reviewer request, why it is declarative, and why `instruction.md` remains sufficient.
- Reject or redesign ideas that are single-bug, grep-and-patch, prompt-following, instruction-volume hard, brittle-output-only, hardcode-friendly, or near-duplicate.
- Require at least 3 interacting hidden defects or failure modes, including one non-local bug and one non-happy-path edge case.
- Before full validation, complete the private bidirectional coverage audit from `tb2-tests` with zero uncovered requirements and zero ungrounded tested behaviors. Also self-check that NOP should fail, oracle should pass, every hidden layer is verifier-relevant, the prompt and any approved contract have no hints, Docker is compliant, duplicate scan is clean, and the solution derives the repair.
- Do not choose submission time manually; `.opencode/scripts/tb2_submit_task.sh` selects a random multiple of 10 between 280 and 350 minutes.
