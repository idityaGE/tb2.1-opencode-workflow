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

# Produce reward file (REQUIRED)
if [ "$rc" -eq 0 ]; then
  echo 1 > /logs/verifier/reward.txt
else
  echo 0 > /logs/verifier/reward.txt
fi
```
- `tests/test.sh` must run Python pytest, normally `python -m pytest --ctrf /logs/verifier/ctrf.json /tests/test_outputs.py -rA`, and always write `/logs/verifier/reward.txt`. Use Python pytest tests to drive Java, JavaScript, Go, browser, or other systems instead of replacing pytest with their native test runners.
- Use `set -uo pipefail` in `tests/test.sh`. Do not use `set +e` or enable `errexit` with `set -e`, because the structural gate rejects those forms.
- Every regular or milestone `tests/test.sh` must include the working-directory guard shown above so the verifier writes reward `0` instead of running from `/`.
- The pytest command whose result is being scored must be the last meaningful command before the reward block, or before the `<var>=$?` capture line. Do not add `|| true`, `exit`, logging commands, cleanup, or another command between pytest status and reward capture.
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
- Cover every explicit prompt requirement, reasonable implicit requirement, and important edge case.
- If tests check an output file, schema, or protocol detail, make sure `instruction.md` mentions it fairly.
- Preserve difficulty with behavioral depth rather than hidden requirements: use deterministic generated inputs, multiple fixtures, independent reference logic, invariant checks, replay/restart/order cases, and semantic validation when appropriate.
- Do not encode solution hints or inspect forbidden implementation details.
- Tests must be deterministic and must not fetch dependencies or data from the network.
- `tests/test.sh` must not install packages or download data from the network at runtime. Bake pytest, pytest-json-ctrf, plugins, browser drivers, wheels, npm packages, and other verifier dependencies into the Docker image. Local-only installs from preloaded wheels, such as `pip install --no-index -f /opt/wheels pytest==8.4.1`, are acceptable when needed.
- The same verifier must score oracle and agent runs.
- Do not use latency or performance thresholds as pass/fail criteria.
- Do not branch test behavior on oracle-vs-agent mode.
