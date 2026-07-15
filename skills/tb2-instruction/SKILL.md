---
name: tb2-instruction
description: Write concise, human-style Terminal-Bench instruction.md prompts with absolute paths, clear requirements, no hints, and humanizer cleanup.
---

# TB2 Instruction

Use when writing `instruction.md`.

Requirements:
- Keep the complete prompt at or below 200 words; prefer around 150. Use one sentence to at most three short prose paragraphs and remove anything the verifier does not need.
- Write a natural one-shot request a person would give a coding agent. Do not use role-setting introductions, formal specification language, or long-running task framing.
- Use plain prose, not a structured checklist or document. Do not use headings, bullets, numbered steps, tables, code fences, bold markers, hint sections, or emojis.
- Use absolute paths for files and commands the agent must interact with.
- State all observable requirements needed for the verifier, including required output paths and exact schemas when tests check structured data.
- Give the agent the goal and necessary external contract, not the method. Do not reveal solution steps, repair order, bug locations, edge-case names, hidden expected values, suggested commands, libraries, internal APIs, or bug-signposting comments.
- Avoid ambiguity and hidden requirements.
- Never include a canary string, legacy benchmark/training-data banner, task name, or old-skeleton comment in `instruction.md`.
- Use domain-specific wording that matches the selected allowed category. The first sentence should make the truthful primary activity clear as `system-administration`, `build-and-dependency-management`, `games`, `machine-learning`, `security`, or `scientific-computing`.
- Avoid generic software-engineering/debugging phrasing such as "fix the bugs", "implement missing logic", "repair this app", or "make the tests pass". Avoid data-processing phrasing such as "parse files", "transform data", "aggregate records", "process datasets", "convert CSV/JSON/logs", or "generate derived output"; if those phrases describe the task accurately, redesign the primary activity before authoring. Describe the observable allowed-category outcome instead.
- When instruction-sufficiency feedback requires more detail, add the smallest neutral behavior contract, invariant, schema, or valid input/output statement needed for fairness without naming the defect or telling the agent where/how to fix it.
- Do not add supporting docs/help files inside the task. No `README*`, `docs/`, `doc/`, `documentation/`, guides, manuals, notes, walkthroughs, local specs, or reference excerpts. Never split the prompt or goals across environment files to evade the word limit. Environment files and comments must not contain procedural guidance or solution hints. If a rule is required for verification, state its minimal observable contract briefly in `instruction.md`.
- Check uniqueness with focused inspection of existing tasks; reject near-duplicates unless the initial state or expected output is materially different.
- Run a humanizer pass before finalizing.
- The prompt should be extremely hard because of multi-step engineering depth and hidden layered bugs, not because it is vague.
