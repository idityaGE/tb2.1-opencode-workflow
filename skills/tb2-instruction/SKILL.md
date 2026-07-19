---
name: tb2-instruction
description: Write concise, human-style Terminal-Bench instruction.md prompts with absolute paths, clear requirements, no hints, and humanizer cleanup.
---

# TB2 Instruction

Use when writing `instruction.md`.

Requirements:
- Keep the complete prompt at or below 250 words; prefer around 200. Use one sentence to at most three short prose paragraphs and remove anything the verifier does not need.
- Write a natural one-shot request a person would give a coding agent. Do not use role-setting introductions, formal specification language, or long-running task framing.
- Use plain prose, not a structured checklist or document. Do not use headings, bullets, numbered steps, tables, code fences, bold markers, hint sections, or emojis.
- Use absolute paths for files and commands the agent must interact with.
- State the complete task goal, required operation, entrypoints, absolute input/output paths, top-level success criteria, and observable invariants needed for the verifier. A generic request to “follow the spec” is not sufficient.
- Give the agent the goal and necessary external contract, not the method. Do not reveal solution steps, repair order, bug locations, edge-case names, hidden expected values, suggested commands, libraries, internal APIs, or bug-signposting comments.
- Avoid ambiguity and hidden requirements.
- Never include a canary string, legacy benchmark/training-data banner, task name, or old-skeleton comment in `instruction.md`.
- Use domain-specific wording that matches the selected allowed category. The first sentence should make the truthful primary activity clear as `system-administration`, `build-and-dependency-management`, `games`, `machine-learning`, `security`, or `scientific-computing`.
- Avoid generic software-engineering/debugging phrasing such as "fix the bugs", "implement missing logic", "repair this app", or "make the tests pass". Avoid data-processing phrasing such as "parse files", "transform data", "aggregate records", "process datasets", "convert CSV/JSON/logs", or "generate derived output"; if those phrases describe the task accurately, redesign the primary activity before authoring. Describe the observable allowed-category outcome instead.
- When instruction-sufficiency feedback requires more detail, add the smallest neutral behavior contract, invariant, schema, or valid input/output statement needed for fairness without naming the defect or telling the agent where/how to fix it.
- Default to no supporting docs/help files. The only exception is one necessary `environment/spec.md` or `environment/rule.md` allowed by `tb2-hard-task-author`, including when concrete reviewer feedback explicitly requests it. Keep every prompt, goal, path, and top-level observable success criterion in `instruction.md`, and name the approved contract by its absolute in-container path. The contract may supply detailed declarative protocol, schema, or rule clauses, but it must not become a second prompt or contain repair steps, bug locations, suggested commands, implementation order, libraries, internal APIs, seeded-case answers, or common-pitfall hints. Generic instruction-sufficiency feedback should be fixed in `instruction.md`; it does not by itself authorize a contract file.
- Check uniqueness with focused inspection of existing tasks; reject near-duplicates unless the initial state or expected output is materially different.
- Run a humanizer pass before finalizing.
- The prompt should be extremely hard because of multi-step engineering depth and hidden layered bugs, not because it is vague.
