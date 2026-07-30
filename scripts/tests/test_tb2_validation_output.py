from __future__ import annotations

import os
import shlex
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
LIB = ROOT / ".opencode/scripts/lib_tb2.sh"


class AdvisoryRuffOutputTests(unittest.TestCase):
    def test_advisory_findings_are_summarized_and_saved(self):
        with tempfile.TemporaryDirectory() as directory:
            repo = Path(directory)
            fake_bin = repo / "bin"
            task = repo / "tasks/example"
            fake_bin.mkdir()
            task.mkdir(parents=True)
            ruff = fake_bin / "ruff"
            ruff.write_text(
                "#!/usr/bin/env bash\n"
                "printf '%s\\n' 'E501 Line too long' ' --> test.py:1:89' "
                "'F401 imported but unused' ' --> test.py:2:1' 'Found 2 errors.'\n"
                "exit 1\n",
                encoding="utf-8",
            )
            ruff.chmod(0o755)
            command = (
                f"source {shlex.quote(str(LIB))}; "
                f"tb2_repo_root() {{ printf '%s\\n' {shlex.quote(str(repo))}; }}; "
                f"tb2_run_advisory_ruff {shlex.quote(str(task))}"
            )
            env = {**os.environ, "PATH": f"{fake_bin}:{os.environ['PATH']}"}
            result = subprocess.run(
                ["bash", "-c", command],
                check=True,
                capture_output=True,
                env=env,
                text=True,
            )
            self.assertIn("Advisory Ruff: 2 findings (E501=1, F401=1)", result.stdout)
            self.assertNotIn("--> test.py", result.stdout)
            report = repo / ".tb2-cache/tb2-validation/advisory-ruff/example.log"
            self.assertIn("--> test.py", report.read_text(encoding="utf-8"))


if __name__ == "__main__":
    unittest.main()
