---
name: tb2-instruction
description: Write concise, domain-framed Terminal-Bench instruction.md prompts with public contract references, absolute paths, no hints, and humanizer cleanup.
---

# TB2 Instruction

Use when writing `instruction.md`.

Requirements:
- Read and follow `.opencode/docs/tb2/instruction-authoring.md` as the detailed local contract. Keep the complete prompt at or below 300 words in no more than three concise prose paragraphs; target 180-250 words.
- Write a natural one-shot request a person would give a coding agent. Open with the domain-native actor, context, objective, and consequence, not a tool, implementation language, file transformation, or repaired behavior. Avoid synthetic role assignment, formal specification language, and long-running task framing.
- Use plain prose, not a structured checklist or document. Do not use headings, bullets, numbered steps, tables, code fences, bold markers, hint sections, or emojis.
- Use absolute paths for files and commands the agent must interact with.
- Put only the human prompt in `instruction.md`: identify the dossier or deliverable, concrete objective and consequence, absolute work/output paths, major behavior and invalidity categories, and absolute paths to authoritative public documents. Do not duplicate their detailed schemas, exhaustive edge cases, or invariants in the prompt.
- Give the agent the goal and necessary external contract, not the method. Do not reveal solution steps, repair order, bug locations, edge-case names, hidden expected values, suggested commands, libraries, internal APIs, or bug-signposting comments.
- Every verifier-enforced behavior must be public in `instruction.md` or an explicitly referenced agent-visible document. A README/specification may expand only requirement categories already introduced by the prompt; hidden inputs are allowed, hidden requirements are not.
- Never include a canary string, legacy benchmark/training-data banner, task name, or old-skeleton comment in `instruction.md`.
- Before drafting, read `.opencode/docs/tb2/task-taxonomy.md`, the category source of truth, and follow its current blocked notices and `Choosing a Category` rule. Make the first sentence, objective, consequence, and deliverable naturally match the selected primary activity without announcing a taxonomy label.
- If the taxonomy classifies the honest prompt as currently blocked, stop and redesign it. Do not use unnatural wording or metadata changes to make a blocked task look allowed.
- Keep repair/fix/debug/patch/failing-test and parse/transform/aggregate/filter-dataset framing out of the prose. Keep implementation, CLI, schema, verifier, and file-I/O mechanics subordinate to domain decisions, state, evidence, and consequences. Apply this check to public README/specification titles and introductions too.
- When instruction-sufficiency feedback requires more detail, first make the prompt's objective, expected outcome, scope, paths, or authoritative-document references unambiguous. Do not answer sufficiency feedback by listing verifier cases or debugging clues in the prompt.
- Use approved agent-visible `README.md`, `spec.md`, or `rule.md` files under `environment/` when detailed public rules are needed. Ensure Docker copies them into the runtime and `instruction.md` references each by absolute in-container path. Supporting documents must not become overflow prompts or contain repair steps, diagnostics, bug locations, suggested fixes, implementation order, seeded-case answers, known issues, common pitfalls, or test-shaped edge-case lists.
- Before validation, complete the private verifier-to-public-contract sufficiency audit and line-by-line ambiguity ledger defined in `instruction-authoring.md`, then review both the complete prose and a domain-blind version for blocked-category surface framing.
- Check uniqueness with focused inspection of existing tasks; reject near-duplicates unless the initial state or expected output is materially different.
- Run a humanizer pass before finalizing.
- The prompt should meet its selected medium or hard rating through multi-step engineering depth and hidden layered bugs, not vagueness.
