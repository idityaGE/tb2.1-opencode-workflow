---
name: tb2-dockerfile
description: Write TB2 environment/Dockerfile files using canonical digest-pinned base images, language lockfiles, harness packages, and no solution/test leakage.
---

# TB2 Dockerfile

Use when writing or reviewing `environment/Dockerfile`.

Requirements:
- Prefer an exact canonical digest-pinned image from `.opencode/docs/tb2/dockerfile-best-practices.md` for the final stage. A non-canonical image is allowed only when every image is digest-pinned and the Dockerfile or task README contains a brief, credible, task-specific reason a canonical image does not fit; missing, vague, or inapplicable justifications are blocking.
- Prefer sanctioned registries or Docker Hub Official Image namespaces. For languages missing from the canonical set, first consider canonical Debian or Ubuntu with a pinned toolchain; use another image only under the justified exception above.
- Read `.opencode/docs/tb2/dockerfile-best-practices.md` when selecting the current exact canonical image reference.
- Install required harness packages including `tmux` and `asciinema`.
- Pin every non-apt package dependency exactly and use the ecosystem lockfile when available.
- Do not copy `tests/`, `solution/`, verifier files, reward files, or answer values into the image.
- Do not create or modify reserved `/tests`, `/solution`, or `/oracle` directories.
- Keep `environment/` at most 100 MiB total and no file over 50 MiB. Every task upload must include `environment/.dockerignore`; use `.opencode/scripts/tb2_prepare_upload.sh --task tasks/<task_name>` before validation/upload so it contains `**/__pycache__/`, `**/*.pyc`, `**/.pytest_cache/`, `solution/`, and `tests/`.
- Build everything needed into the environment when `allow_internet = false`; when it is `true`, keep runtime network use limited to the task's genuine, deterministically verifiable need.
- Keep the Dockerfile minimal and deterministic.
- Use clean apt transactions: `--no-install-recommends`, no `apt-get upgrade`, and remove `/var/lib/apt/lists/*` in the same layer.
- Avoid privileged containers and unsafe Docker capabilities.
- Install only the needed implementation-language compiler/toolchain, verifier dependencies, and debugging utilities; keep uncommon-language toolchains pinned and offline-capable.
