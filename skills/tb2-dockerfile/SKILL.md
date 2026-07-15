---
name: tb2-dockerfile
description: Write TB2 environment/Dockerfile files using canonical digest-pinned base images, language lockfiles, harness packages, and no solution/test leakage.
---

# TB2 Dockerfile

Use when writing or reviewing `environment/Dockerfile`.

Requirements:
- Use an exact canonical digest-pinned image from `.opencode/docs/tb2/dockerfile-best-practices.md` for the final stage. Do not treat a Dockerfile justification as sufficient when the platform reports that a base is unsanctioned or outside the canonical set.
- Every `FROM` image must come from a sanctioned registry or Docker Hub Official Image namespace. Do not use community language images such as `crystallang/crystal`; for languages missing from the canonical set, start from the canonical Debian or Ubuntu image and install the pinned toolchain there. If that is genuinely impossible, stop and propose a canonical-image addition rather than authoring a Dockerfile that validation will reject.
- Read `.opencode/docs/tb2/dockerfile-best-practices.md` when selecting the current exact canonical image reference.
- Install required harness packages including `tmux` and `asciinema`.
- Use language/tool lockfiles where practical for dependencies outside the system package transaction.
- Do not copy `tests/`, `solution/`, verifier files, reward files, or answer values into the image.
- Do not create or modify reserved `/tests` or `/oracle` directories.
- Keep `environment/` at most 100 MiB total and no file over 50 MiB. Every task upload must include `environment/.dockerignore`; use `.opencode/scripts/tb2_prepare_upload.sh --task tasks/<task_name>` before validation/upload so it contains `**/__pycache__/`, `**/*.pyc`, `**/.pytest_cache/`, `solution/`, and `tests/`.
- Avoid runtime network dependency; build everything needed into the environment.
- Keep the Dockerfile minimal and deterministic.
- Use clean apt transactions: `--no-install-recommends`, no `apt-get upgrade`, and remove `/var/lib/apt/lists/*` in the same layer.
- Avoid privileged containers and unsafe Docker capabilities.
- Install only the needed implementation-language compiler/toolchain, verifier dependencies, and debugging utilities; keep uncommon-language toolchains pinned and offline-capable.
