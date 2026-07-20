# Local `instruction.md` Authoring Contract

This local contract supplements the copied TB2 prompt-styling guidance. Before drafting, read `.opencode/docs/tb2/task-taxonomy.md` and apply its current blocked-category notices and primary-activity rule. If the honest task is blocked, redesign the task rather than disguising it with metadata or wording.

## Prompt shape

Write no more than three concise prose paragraphs and approximately 150–300 words; 180–250 words is the practical target. Open with the domain-native actor, context, objective, and consequence. Then identify the dossier or deliverable, absolute work and output paths, major pass/fail behavior categories, principal invalidity categories when relevant, and any public README or specification that defines detailed rules. Do not open with a tool, implementation language, file transformation, or statement that the shipped code must be repaired.

Use simple, direct, task-specific English. Do not include the task name, a canary string, headings, lists, tables, code blocks, exhaustive edge-case inventories, plans, or stock assistant phrasing. State what must be true, not how to achieve it. Do not identify defects, bug locations, functions to edit, algorithms, libraries, repair steps, or verifier behavior. State decisive rules once in the same neutral voice as surrounding requirements rather than emphasizing or contrasting them with a naive approach.

## Public contract files

Agent-visible `README.md`, `spec.md`, or `rule.md` files are allowed when the contract needs detailed schemas, mathematical definitions, domain semantics, canonicalization, ordering, serialization, error precedence, certificate formats, or non-answer-revealing examples. Place them under `environment/` where the Docker build copies them to an agent-visible absolute path, and reference each one from `instruction.md` by that in-container path. The instruction must introduce the requirement categories governed by each document; a supporting file may expand those requirements but must not be the first place a graded behavior is mentioned.

Supporting documents must look like ordinary project artifacts, not overflow prompts or solution guides. They must not contain repair instructions, known-issue lists, debugging checklists, seeded-case answers, verifier-shaped edge-case catalogs, or hints about the implementation path. Keep every document independently necessary and use the same domain-native framing in its title and introduction.

## Fairness and category-surface review

Every pass/fail rule must be stated in `instruction.md` or in a public file it explicitly references. Exact messages, fields, values, ordering, tie-breaks, canonical forms, error precedence, failure propagation, exit behavior, tolerances, and path rules must be public whenever tests enforce them. Hidden inputs are allowed; hidden requirements are not. Every instruction requirement must have corresponding verifier coverage.

Before finalizing, perform both audits:

1. Enumerate every distinct behavior asserted by the verifier and map it to the exact public sentence that defines it. Repair anything unstated or merely implied by an example, using WHAT rather than HOW.
2. Build a private ambiguity ledger across `instruction.md` and every referenced README/specification. Check required files, commands, fields, types, status values, artifacts, ordering, canonicalization, tie-breaks, errors, certificates, precision, exit conventions, and path constraints against verifier and oracle behavior. Resolve omissions and conflicting interpretations before validation.

The prose itself must read as the declared allowed category. Lead with domain decisions, state, evidence, and consequences; keep CLI, runtime, schema, source-code, testing, and file-I/O mechanics subordinate. Avoid repair/fix/debug/patch/failing-test wording and parse/transform/aggregate/filter-dataset framing. Review both the complete prose and a domain-blind version with the task name, category label, language, and broad domain words removed. If either version reads primarily as a blocked category, redesign or re-voice the actual task before validation; never relabel metadata to force a pass.
