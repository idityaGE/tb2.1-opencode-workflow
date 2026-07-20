# Local `instruction.md` Authoring Contract

This local contract supplements the copied TB2 prompt-styling guidance. Follow the prompt limits and source precedence in `.opencode/docs/local/workflow-profile.md`. Before drafting, read `.opencode/docs/tb2/task-taxonomy.md` for primary-activity semantics and use `python3 .opencode/scripts/tb2_metadata.py categories` for current status. If the honest task is blocked, redesign it rather than disguising it with metadata or wording.

## Prompt shape

Keep the prompt concise without dropping any contract-critical requirement, and make the assignment clear, well specified, interesting, and useful. Open with the domain-native actor, context, objective, and consequence. Then identify the required dossier or deliverable, absolute work and output paths, major pass/fail behavior categories, principal invalidity categories when relevant, and any public README or specification that defines detailed rules. Do not open with a tool, implementation language, file transformation, or statement that the shipped code must be repaired.

Use simple, direct, local, task-specific English, and write every mentioned file or directory path as an absolute path. Do not include the task name, a canary string, headings, lists, tables, code blocks, exhaustive edge-case inventories, inline plans, or step-by-step hints. State what must be true, not how to achieve it. Do not enumerate defects, describe how the shipped code misbehaves, or identify bug locations, functions to edit, algorithms, libraries, repair steps, or verifier behavior unless an identifier or behavior is itself part of the public contract. State decisive rules once in the same neutral voice as surrounding requirements rather than emphasizing them or contrasting them with a naive approach.

Avoid stock openers and closers such as “Your task is to,” “make sure to,” “carefully,” “simply,” “just,” and “ensure the solution is robust” unless genuinely necessary. Remove padded transitions, motivation, assistant reassurance, and repetitive sentence or bullet stems. Prefer a few high-information sentences over many thin requirements, tie behavior to actual files, commands, schemas, and consequences, and rewrite any sentence that could apply unchanged to dozens of unrelated tasks.

## Public contract files

Agent-visible `README.md`, `spec.md`, or `rule.md` files are allowed when the contract needs detailed schemas, mathematical definitions, complete domain semantics, canonicalization, ordering, serialization, error precedence, certificate formats, or non-answer-revealing examples. Place them under `environment/` where the Docker build copies them to an agent-visible absolute path, and reference and describe each one from `instruction.md` by that in-container path. The instruction must introduce the requirement categories governed by each document; a supporting file may expand those requirements but must not be the first place a core or graded behavior is mentioned. A README is not defective merely because it contains detailed rules; it is defective when the instruction does not point to it or does not identify the requirement categories it governs.

Supporting documents must look like ordinary project artifacts, not overflow prompts or solution guides. They must not contain repair instructions, known-issue lists, debugging checklists, seeded-case answers, verifier-shaped edge-case catalogs, or hints about the implementation path. Keep every document independently necessary and use the same domain-native framing in its title and introduction.

## Fairness and category-surface review

Every pass/fail rule must be stated in `instruction.md` or in a public file it explicitly references. Exact messages, fields, values, ordering, tie-breaks, canonical forms, error precedence, failure propagation, exit behavior, tolerances, and path rules must be public whenever tests enforce them. Hidden inputs are allowed; hidden requirements are not. Every instruction requirement must have corresponding verifier coverage.

Before finalizing, perform both audits:

1. Enumerate every distinct behavior asserted by the verifier and map it to the exact public sentence that defines it. Repair anything unstated or merely implied by an example, using WHAT rather than HOW.
2. Build a private ambiguity ledger across `instruction.md` and every referenced README/specification. Check required files, commands, fields, types, status values, artifacts, ordering, canonicalization, tie-breaks, errors, certificates, precision, exit conventions, and path constraints against verifier and oracle behavior. Resolve omissions and conflicting interpretations before validation.

The prose itself must read as the declared allowed category. Lead with domain decisions, state, evidence, and consequences; keep CLI, runtime, schema, source-code, testing, and file-I/O mechanics subordinate. Avoid repair/fix/debug/patch/failing-test wording and parse/transform/aggregate/filter-dataset framing. Review both the complete prose and a domain-blind version with the task name, category label, language, and broad domain words removed. If either version reads primarily as a blocked category, redesign or re-voice the actual task before validation; never relabel metadata to force a pass.
