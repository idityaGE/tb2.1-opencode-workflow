---
name: tb2-instruction
description: Write concise, prompt-only Terminal-Bench instruction.md files with a clear objective, absolute contract paths, no hints, and humanizer cleanup.
---

# TB2 Instruction

Use when writing `instruction.md`.

Requirements:
- Keep the complete prompt at or below 250 words; prefer around 200. Use one sentence to at most three short prose paragraphs and remove anything not needed to understand the assignment, outcome, paths, or authoritative documents.
- Write a natural one-shot request a person would give a coding agent. Do not use role-setting introductions, formal specification language, or long-running task framing.
- Use plain prose, not a structured checklist or document. Do not use headings, bullets, numbered steps, tables, code fences, bold markers, hint sections, or emojis.
- Use absolute paths for files and commands the agent must interact with.
- Put only the human prompt in `instruction.md`: identify the concrete objective, expected user-visible outcome or deliverable, absolute work/output paths, and absolute paths to any authoritative environment documents. Do not duplicate their detailed schemas, rules, exhaustive edge cases, or invariants in the prompt.
- Give the agent the goal and necessary external contract, not the method. Do not reveal solution steps, repair order, bug locations, edge-case names, hidden expected values, suggested commands, libraries, internal APIs, or bug-signposting comments.
- Avoid ambiguity and hidden requirements.
- Never include a canary string, legacy benchmark/training-data banner, task name, or old-skeleton comment in `instruction.md`.
- Use domain-specific wording that matches the selected allowed category. The first sentence should make the truthful primary activity clear as `system-administration`, `build-and-dependency-management`, `games`, `machine-learning`, `security`, or `scientific-computing`.
- Avoid generic software-engineering/debugging phrasing such as "fix the bugs", "implement missing logic", "repair this app", or "make the tests pass". Avoid data-processing phrasing such as "parse files", "transform data", "aggregate records", "process datasets", "convert CSV/JSON/logs", or "generate derived output"; if those phrases describe the task accurately, redesign the primary activity before authoring. Describe the observable allowed-category outcome instead.
- When instruction-sufficiency feedback requires more detail, first make the prompt's objective, expected outcome, scope, paths, or authoritative-document references unambiguous. Do not answer sufficiency feedback by listing verifier cases or debugging clues in the prompt.
- Use only the approved documents from `tb2-hard-task-author`: a necessary `environment/README.md` for realistic system context/interfaces and, when needed, one `environment/spec.md` or `environment/rule.md` for detailed normative behavior. `instruction.md` must reference each by absolute in-container path but should not repeat it. Generic instruction-sufficiency feedback does not itself authorize a new document; concrete reviewer requests do. Supporting documents must not restate the task assignment or contain repair steps, diagnostics, bug locations, suggested fixes, implementation order, seeded-case answers, known issues, common pitfalls, or test-shaped edge-case lists.
- Check uniqueness with focused inspection of existing tasks; reject near-duplicates unless the initial state or expected output is materially different.
- Run a humanizer pass before finalizing.
- The prompt should be extremely hard because of multi-step engineering depth and hidden layered bugs, not because it is vague.
