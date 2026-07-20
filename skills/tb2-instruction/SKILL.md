---
name: tb2-instruction
description: Write concise, domain-framed Terminal-Bench instruction.md prompts with public contract references, absolute paths, no hints, and humanizer cleanup.
---

# TB2 Instruction

Use when writing `instruction.md`.

Requirements:
- Read `.opencode/docs/local/workflow-profile.md` for prompt limits and `.opencode/docs/local/instruction-authoring.md` for the detailed authoring contract. Be concise without dropping contract-critical requirements, and keep the assignment clear, well specified, interesting, and useful.
- Write a natural one-shot request a person would give a coding agent. Open with the domain-native actor, context, objective, and consequence, not a tool, implementation language, file transformation, or repaired behavior. Avoid synthetic role assignment, formal specification language, and long-running task framing.
- Use plain prose, not a structured checklist or document. Do not use headings, bullets, numbered steps, tables, code fences, bold markers, hint sections, or emojis.
- Use only absolute paths when naming files or directories the agent must interact with.
- Put only the human prompt in `instruction.md`: identify the dossier or deliverable, concrete objective and consequence, absolute work/output paths, major behavior and invalidity categories, and absolute paths to authoritative public documents. Do not duplicate their detailed schemas, exhaustive edge cases, or invariants in the prompt.
- Give the agent the goal and necessary external contract, not the method. Do not enumerate defects, describe shipped misbehavior, or reveal solution steps, repair order, bug locations, edge-case names, hidden expected values, suggested commands, libraries, internal APIs, or bug-signposting comments. Mention functions, algorithms, or defect behavior only when they are themselves part of the public contract.
- Every verifier-enforced behavior must be public in `instruction.md` or an explicitly referenced agent-visible document. A README/specification may expand only requirement categories already introduced by the prompt; hidden inputs are allowed, hidden requirements are not.
- Never include a canary string, legacy benchmark/training-data banner, task name, or old-skeleton comment in `instruction.md`.
- Before drafting, read `.opencode/docs/tb2/task-taxonomy.md` for category semantics and use `python3 .opencode/scripts/tb2_metadata.py categories` for current status. Make the first sentence, objective, consequence, and deliverable naturally match the selected primary activity without announcing a taxonomy label.
- If the metadata helper marks the honest primary category as blocked, stop and redesign it. Do not use unnatural wording or metadata changes to make a blocked task look allowed.
- Keep repair/fix/debug/patch/failing-test and parse/transform/aggregate/filter-dataset framing out of the prose. Keep implementation, CLI, schema, verifier, and file-I/O mechanics subordinate to domain decisions, state, evidence, and consequences. Apply this check to public README/specification titles and introductions too.
- Avoid stock phrases such as “Your task is to,” “make sure to,” “carefully,” “simply,” “just,” and “ensure the solution is robust” unless necessary. Remove padded transitions, motivation, reassurance, repetitive stems, and generic sentences; prefer a few high-information sentences tied to actual files, commands, schemas, and consequences.
- When instruction-sufficiency feedback requires more detail, first make the prompt's objective, expected outcome, scope, paths, or authoritative-document references unambiguous. Do not answer sufficiency feedback by listing verifier cases or debugging clues in the prompt.
- Use approved agent-visible `README.md`, `spec.md`, or `rule.md` files under `environment/` when detailed public rules are needed. Ensure Docker copies them into the runtime and `instruction.md` references each by absolute in-container path and identifies the requirement categories it governs. Detailed rules are valid there; supporting documents fail only when they hide core requirements, become overflow prompts, or contain repair steps, diagnostics, bug locations, suggested fixes, implementation order, seeded-case answers, known issues, common pitfalls, or test-shaped edge-case lists.
- Before validation, complete the private verifier-to-public-contract sufficiency audit and line-by-line ambiguity ledger defined in the local instruction-authoring contract, then review both the complete prose and a domain-blind version for blocked-category surface framing.
- Check uniqueness with focused inspection of existing tasks; reject near-duplicates unless the initial state or expected output is materially different.
- Run a humanizer pass before finalizing.
- The prompt should meet its selected profile rating through engineering depth and hidden layered bugs, not vagueness.
