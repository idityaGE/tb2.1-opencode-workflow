---
name: tb2-tests
description: Write Terminal-Bench pytest verifiers and tests/test.sh runners that fully cover the prompt and always emit reward.txt.
---

# TB2 Tests

Use when writing `tests/` for Terminal-Bench tasks.

Requirements:
- For new tasks, write `tests/test.sh` from this exact shape unless a real exception is needed:
```sh
#!/bin/bash
set -uo pipefail

# Check if we're in a valid working directory
if [ "$PWD" = "/" ]; then
    echo "Error: No working directory set. Please set a WORKDIR in your Dockerfile before running this script."
    mkdir -p /logs/verifier
    echo 0 > /logs/verifier/reward.txt
    exit 0
fi

mkdir -p /logs/verifier

# pytest and pytest-json-ctrf must be pre-installed in the Docker image.
python -m pytest --ctrf /logs/verifier/ctrf.json /tests/test_outputs.py -rA
rc=$?
if [ "$rc" -eq 0 ]; then
  echo 1 > /logs/verifier/reward.txt
else
  echo 0 > /logs/verifier/reward.txt
fi
```
- `tests/test.sh` must run Python pytest, normally `python -m pytest --ctrf /logs/verifier/ctrf.json /tests/test_outputs.py -rA`, and always write `/logs/verifier/reward.txt`. Use Python pytest tests to drive Java, JavaScript, Go, browser, or other systems instead of replacing pytest with their native test runners.
- Use `set -uo pipefail` in `tests/test.sh`. Do not use `set +e` or enable `errexit` with `set -e`, because the structural gate rejects those forms.
- Every `tests/test.sh` must include the working-directory guard shown above so the verifier writes reward `0` instead of running from `/`.
- The pytest command whose result is being scored must be immediately followed by `<var>=$?`, and that line must be immediately followed by the final reward `if` block.
- End `tests/test.sh` with one of these reward blocks as the literal physical end of the file. The final physical line must be exactly `fi` with no trailing spaces; do not add trailing comments, blank lines, logging, cleanup, or `exit` commands after it:
```sh
if [ $? -eq 0 ]; then
    echo 1 > /logs/verifier/reward.txt
else
    echo 0 > /logs/verifier/reward.txt
fi
```
```sh
rc=$?
if [ "$rc" -eq 0 ]; then
    echo 1 > /logs/verifier/reward.txt
else
    echo 0 > /logs/verifier/reward.txt
fi
```
- Prefer the `rc=$?` capture form shown in the canonical runner for new tasks.
- `tests/test_outputs.py` should use behavioral assertions, not implementation details.
- Every test function should have a docstring.
- Cover every explicit prompt requirement, every normative clause used from an approved agent-visible `README.md`, `spec.md`, or `rule.md` under `environment/`, fair unavoidable implicit behavior, and important edge case. If multiple reasonable outcomes exist, document the chosen observable behavior before testing it rather than treating it as implicit.
- If tests check an output file, schema, protocol, or rule detail, ground it fairly in the prompt or an explicitly referenced public document. Detailed contract text may live in that document only when `instruction.md` already introduces the governed requirement category.
- Before validation, run a private bidirectional requirement-to-test audit. Atomize independently violable obligations as `R1`, `R2`, and so on, and record each obligation's source, covering pytest functions, the assertion or independent-reference result that rejects a violation, input class, and one plausible violation probe. Execution alone, a broad end-to-end test, or file existence does not prove coverage unless the mapped assertion distinguishes compliant from non-compliant behavior.
- Reverse-audit every semantically distinct verifier assertion to an explicit instruction requirement, approved contract clause, or truly unavoidable implicit behavior. If no basis exists, add the smallest neutral observable contract or remove the unfair assertion. A test is not grounded merely because it catches a seeded bug.
- The audit passes only with zero uncovered requirements, zero ungrounded tested behaviors, coverage of every critical edge class, and verifier relevance for every intended hidden defect or failure layer. Re-run it after any instruction, approved contract, verifier, or oracle change. Keep the matrix private; do not upload it or leak requirement IDs through task files, test names, fixtures, or comments.
- Preserve difficulty with behavioral depth rather than hidden requirements: use deterministic generated inputs, multiple fixtures, independent reference logic, invariant checks, replay/restart/order cases, and semantic validation when appropriate.
- Do not encode solution hints or inspect forbidden implementation details.
- Tests must be deterministic. With `allow_internet = false`, they must not fetch dependencies or data; with `true`, network use must be limited to the task's genuine need and grading must remain stable.
- `tests/test.sh` must not install packages at runtime. Bake pytest, pytest-json-ctrf, plugins, browser drivers, wheels, npm packages, and other verifier dependencies into the Docker image. Local-only installs from preloaded wheels, such as `pip install --no-index -f /opt/wheels pytest==8.4.1`, are acceptable when needed.
- The same verifier must score oracle and agent runs.
- Do not use latency or performance thresholds as pass/fail criteria.
- Do not branch test behavior on oracle-vs-agent mode.
