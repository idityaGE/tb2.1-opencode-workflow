---
name: tb2-hard-task-author
description: Design and author Terminal-Bench 2 tasks under the local workflow profile with layered failures, deterministic oracle solutions, and pytest verifiers.
---

# TB2 Hard Task Author

Use when creating or revising a Terminal-Bench 2 task.

Workflow profile:
- Read `.opencode/docs/local/workflow-profile.md` before proposal, authoring, or revision. It owns creation difficulty, implementation-language, milestone, prompt-length, and validation policy; do not restate those values here.

Defaults:
- Destination: `tasks/<task-name>` from the repository root.
- Visible workflow command: `/create-task`.
- Category semantics source: `.opencode/docs/tb2/task-taxonomy.md`. Read its descriptions and `Choosing a Category` section. Get live open/blocked status from `python3 .opencode/scripts/tb2_metadata.py categories`; do not maintain another list.
- Bug shape: multi-step, multi-level, hidden bugs or layered failure modes. Hidden means not signposted in prompts, code comments, fixture names, tests, or specs; all required behavior must still be fairly specified.

Fast path:
- Treat this skill plus the component skills as the default policy cache for `/create-task`.
- Before proposal, authoring, or review, follow `.opencode/docs/policy-sources.toml` and use targeted Grep/Read on the implicated current-status or normative source. Use FAQ and Agent Review only as advisory context. Surface unresolved conflicts instead of inventing policy.
- Use other targeted docs only for UI tasks, rubric/platform exceptions, unclear Docker/verifier policy, obscure language behavior, or authoritative external specs. Web research is allowed during authoring. Prefer self-contained offline tasks, but permit runtime internet only when the task genuinely requires it, `allow_internet` matches that need, and solving and grading remain deterministic. Do not vendor solver guides into the task; use only the task-authored environment-document policy below.
- For duplicate checks, inspect task names, `task.toml` metadata, and only the first paragraph of likely-similar instructions.

Rotate across hard domains: numerical methods, crash-consistent storage, binary formats, concurrency, allocators, kernel-adjacent Linux behavior, protocol parsers, state-machine repair, build systems, VM/runtime behavior, and specification-heavy ecosystems.

Category selection gate:
- Apply the taxonomy's primary-activity rule to the honest prompt, final deliverable, and dominant verifier behavior. Language, libraries, domain vocabulary, and seeded defects do not determine category by themselves.
- If `tb2_metadata.py categories` marks that primary activity as blocked, reject or redesign the concept. Never rescue it with metadata-only relabeling, allowed-domain vocabulary, or euphemistic prompt wording.

Rules:
- Tasks must be multi-step, standalone, novel, deterministic, and solvable by an expert human.
- Avoid privileged operations, privileged containers, unsafe Docker capabilities, and runtime human input. Keep tasks offline by default; any live external dependency must be essential, declared by `allow_internet = true`, stable, and deterministically verifiable.
- Keep component details in the component skills; use this skill for overall task shape, difficulty, language, category, and anti-hint policy.
- Follow the component skills for `task.toml`, Dockerfile, instructions, solution, tests, and field answers.
- Do not include solution hints, bug locations, exact answer values, final outputs, or bug-signposting comments in user-visible files. Do not help the agent identify or solve the bugs in any way.
- Allow one agent-visible `README.md` and, when needed, one of `spec.md` or `rule.md` under `environment/` for realistic system context, interfaces, or detailed declarative protocol/schema/domain rules. `environment/task_file/README.md` is a normal source location when Docker copies that tree to `/app`. Each file must be independently necessary, copied to an agent-visible in-container path, and explicitly referenced from `instruction.md`; nearing the instruction word limit is not a reason to create one. Other docs directories, guides, manuals, notes, walkthroughs, and reference excerpts remain prohibited.
- Avoid single-obvious-patch tasks; require multiple investigative steps and edge-case reasoning.
- Keep category alignment true when the prompt, environment, tests, and expected deliverable are read together; follow the taxonomy source rather than keyword substitution.

Sufficiency and difficulty guidance:
- Make the task fully specified while making the implementation/debugging path genuinely deep. Publicly define outputs, schemas, invariants, ordering, errors, and edge semantics, but keep broken files, functions, defects, algorithms, and repair steps out of agent-visible text unless an identifier is itself part of the public contract.
- Hide inputs, not rules. Hidden tests may use larger, cyclic, reordered, malformed, or deterministically generated same-schema inputs, but every rule they enforce must already be stated in `instruction.md` or an explicitly referenced public contract.
- Keep `instruction.md` as the human prompt only and follow `tb2-instruction` plus `.opencode/docs/local/instruction-authoring.md`. Agent-visible README/spec/rule files may contain realistic context, interfaces, and detailed normative protocol, schema, format, or domain rules. None may contain task-specific repair steps, diagnostics, execution order, bug locations, suggested fixes, seeded-case answers, known-issue lists, common pitfalls, or verifier-shaped edge-case catalogs.
- Prefer non-local failure chains across parser/state/build/runtime layers so fixes require tracing interactions and no single local patch can solve the task.
- Build difficulty from one or more natural load-bearing interactions such as recovery/replay ordering, cyclic dependency or state graphs, transaction rollback and persistence, concurrency or scheduling invariants, numeric precision and stability, canonicalization with coupled tie-breaks, or cross-file/cross-artifact consistency. Do not add these mechanisms decoratively; each selected interaction must affect the required result and verifier.
- Use natural edge cases implied by the contract, such as boundaries, empty inputs, duplicates, interrupted checkpoints, ordering ties, malformed-but-recoverable records, restart/replay, or numeric stability cases.
- Make hardcoding difficult with deterministic generated cases, multiple fixtures, semantic invariants, and independent reference checkers.
- Require the agent to derive and preserve a system invariant such as prefix safety, conservation, ordering, idempotence, replay determinism, or representation validity.
- Let simple happy paths pass while hidden tests exercise realistic boundary/recovery/reordering behavior.
- Minimize approved documents to the declarative information an engineer would genuinely inherit. They must not repeat the assignment, mirror test names/assertions, enumerate hidden failure layers, or remove the need to investigate the code. If fair documentation makes a seeded defect obvious, deepen or redesign that defect instead of hiding required behavior.
- Add realistic codebase context and noise only when it is functional, not blank filler or obfuscation.
- Favor domains frontier models often miss: crash recovery, binary parsers, protocol replay, state machines, concurrency ordering, undefined behavior, ownership/lifetime plus logic bugs, numerical stability, checkpoint/restart, allocator metadata, generated artifacts, and dependency/build resolution.
- If Harbor/static validation emits `[category_classifier]` with a category the metadata helper marks blocked, reread the taxonomy and redesign the actual primary activity. Do not merely rename `task.toml` or disguise the task with misleading wording.

Red flags:
- Vague prompts, hidden requirements only in tests, arbitrary gotchas, misleading comments, one obviously broken function, prompt text that points to a file or bug, fixture/test names that reveal the edge case, procedural README/docs/spec walkthroughs, unnecessary contract files, helper notes, giant instruction dumps, dead-file noise, unjustified or nondeterministic runtime internet dependence, or static expected outputs that can be hardcoded.

First-go hardness gates:
- Before authoring, make a private difficulty blueprint: bug layers, why agents miss them, evidence trail, oracle repair path, duplicate-risk note, and a defect-to-verifier map showing that each hidden layer can independently affect score. For each approved environment document, record why it is necessary or the exact reviewer request, what realistic role it serves, and why it does not expose the debugging path.
- Reject or redesign ideas that are single-bug, grep-and-patch, prompt-following, instruction-volume hard, brittle-output-only, hardcode-friendly, or near-duplicate.
- Require at least 3 interacting hidden defects or failure modes, including one non-local bug and one stateful or non-happy-path failure. Reject the design if a single local patch can satisfy the complete contract.
- Before full validation, complete the private four-way contract alignment audit defined only in `tb2-tests`. Separately self-check that the prompt and approved contracts have no hints, Docker is compliant, the duplicate scan is clean, and the solution derives the complete repair.
- Do not choose submission time manually; `.opencode/scripts/tb2_submit_task.sh` selects a random multiple of 10 between 280 and 350 minutes.

Revision hardening gate:
- Apply this gate whenever current platform evidence rates an existing task `EASY` or `TRIVIAL`. Read the persistent update history and available successful or near-success frontier-agent summaries/traces before redesigning. Do not run a local frontier evaluation. Privately record the common successful strategy, behavior it handled, and why the current starter made it reliable.
- On the first `EASY`, change agent-visible runtime/source, invalidate that common strategy, and add or deepen an orthogonal non-local root-cause family. On the first `TRIVIAL`, structurally redesign the starting failure topology immediately; another field or edge case is insufficient.
- If a prior hardness checks upload is followed by another `EASY` or `TRIVIAL`, mark that strategy empirically failed and use the higher hardening level supplied by `tb2_update_state.py`. Explain why agents still succeeded, replace or restructure the starter topology, and add multiple interacting independent root-cause families. Do not repeat the same additive strategy or handle the repeat by adding another config/schema/policy/hash/checkpoint field, isolated validation rule, prompt clause, fixture, test, or oracle branch.
- Materially change core agent-visible implementation or runtime state under `environment/`. Instruction, contract, test, oracle, metadata, schema-field, or extra-fixture-only changes are not a hardness repair. Prefer a mostly working system with subtle interactions over an empty stub or specification-driven rewrite.
- Write `.tb2-cache/tb2-hardening/<submission_id>/<iteration>.json` with the evidence contract owned by `tb2-feedback-iterator`. Map each defect family to source delta, interaction, strategy invalidated, oracle signal, and independent verifier signal; include prior failed strategies and removed/replaced shallow complexity.
- Before validation, run `tb2_update_state.py record-hardening` and require its deterministic fingerprint/provenance gate to pass. Block rather than upload if the evidence is unsupported, the task fingerprint is unchanged from the last checks upload, source paths do not exist, or the redesign is superficial. There is no arbitrary platform retry cap; each new low result must earn its next upload through stronger evidence.
