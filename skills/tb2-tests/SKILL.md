---
name: tb2-tests
description: Write Terminal-Bench pytest verifiers and tests/test.sh runners that fully cover the prompt and always emit reward.txt.
---

# TB2 Tests

Use when writing `tests/` for Terminal-Bench tasks.

Requirements:
- For new tasks, write `tests/test.sh` from this exact shape unless a real exception is needed:
```sh
set -uo pipefail

if [ "$PWD" = "/" ]; then
    echo "Error: No working directory set."
    exit 1
fi

python -m pytest --ctrf /logs/verifier/ctrf.json /tests/test_outputs.py -rA
if [ $? -eq 0 ]; then
    echo 1 > /logs/verifier/reward.txt
else
    echo 0 > /logs/verifier/reward.txt
fi
```
- `tests/test.sh` must run Python pytest, normally `python -m pytest --ctrf /logs/verifier/ctrf.json /tests/test_outputs.py -rA`, and always write `/logs/verifier/reward.txt`.
- Use `set -uo pipefail` in `tests/test.sh`. Do not use `set +e` or enable `errexit` with `set -e`, because the structural gate rejects those forms.
- Immediately after `set -uo pipefail`, every regular or milestone `tests/test.sh` must include the exact working-directory guard shown above so the verifier fails clearly instead of running from `/`.
- The pytest command whose result is being scored must be the last meaningful command before the reward block, or before the `<var>=$?` capture line. Do not add `|| true`, `exit`, logging commands, cleanup, comments, or any other command between pytest status and reward capture.
- End `tests/test.sh` with one of these reward blocks and no trailing lines:
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
- Prefer the first inline `$?` block for new tasks unless a variable capture is needed for readability. If using a variable, the condition must use the `$rc` form shown above.
- `tests/test_outputs.py` should use behavioral assertions, not implementation details.
- Every test function should have a docstring.
- Cover every explicit prompt requirement, reasonable implicit requirement, and important edge case.
- If tests check an output file, schema, or protocol detail, make sure `instruction.md` mentions it fairly.
- Preserve difficulty with behavioral depth rather than hidden requirements: use deterministic generated inputs, multiple fixtures, independent reference logic, invariant checks, replay/restart/order cases, and semantic validation when appropriate.
- Do not encode solution hints or inspect forbidden implementation details.
- Tests must be deterministic and must not fetch dependencies or data from the network.
- `tests/test.sh` must not install packages or download data at runtime. Bake verifier dependencies into the Docker image.
- The same verifier must score oracle and agent runs.
- Do not use latency or performance thresholds as pass/fail criteria.
- Do not branch test behavior on oracle-vs-agent mode.
