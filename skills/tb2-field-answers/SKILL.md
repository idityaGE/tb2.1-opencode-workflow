---
name: tb2-field-answers
description: Draft the three Snorkel platform explanation fields under ./field-answers/ and copy individual fields with wl-copy after task validation.
---

# TB2 Field Answers

Use after validation passes or when preparing platform submission fields. Run a humanizer pass on these field answers before finalizing or copying them.

Write `./field-answers/<task_name>.md` in the current working directory with exactly these headings:

```markdown
## Difficulty Explanation

## Solution Explanation

## Verification Explanation
```

Requirements:
- Follow the selected rating from `.opencode/docs/local/workflow-profile.md`. Explain its multi-step and layered nature without giving a solution walkthrough or hints.
- Solution explanation should summarize the oracle-level repair at a high level.
- Verification explanation should describe behavioral checks and why NOP fails/oracle passes.
- Copy a specific field with `.opencode/scripts/tb2_copy_field_answers.sh --file ./field-answers/<task_name>.md --section "Difficulty Explanation"` when clipboard is available. The helper does not pause for Enter.
