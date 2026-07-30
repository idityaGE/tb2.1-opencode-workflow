from __future__ import annotations

import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
KILO = ROOT / ".kilo"


class KiloSyncTests(unittest.TestCase):
    def test_cache_is_shared_not_mirrored(self):
        sync = (ROOT / ".opencode/scripts/tb2_sync_kilo_workflow.sh").read_text(
            encoding="utf-8"
        )
        self.assertIn('shared_cache_dir="$repo_root/.tb2-cache"', sync)
        self.assertFalse((KILO / "cache").exists())

    def test_results_and_state_policy_are_mirrored(self):
        updater = (KILO / "agents/tb2-task-updater.md").read_text(encoding="utf-8")
        feedback = (KILO / "skills/tb2-feedback-iterator/SKILL.md").read_text(
            encoding="utf-8"
        )
        scheduler = (KILO / "scripts/tb2_update_batch_sdk.mjs").read_text(
            encoding="utf-8"
        )
        for result in (
            "CHECKS SUBMITTED",
            "SENT TO REVIEWER",
            "MANUAL ACTION",
            "WAITING",
            "BLOCKED",
            "UNKNOWN",
        ):
            self.assertIn(result, updater)
            self.assertIn(result, scheduler)
        self.assertIn("reviewer_cycle", feedback)
        self.assertIn(".tb2-cache/tb2-updates", feedback)

    def test_kilo_scheduler_has_no_opencode_source_path(self):
        wrapper = (KILO / "scripts/tb2_update_batch_sdk.sh").read_text(encoding="utf-8")
        scheduler = (KILO / "scripts/tb2_update_batch_sdk.mjs").read_text(
            encoding="utf-8"
        )
        self.assertNotIn(".opencode/scripts/tb2_update_batch_sdk", wrapper)
        self.assertNotIn(".opencode/scripts/tb2_update_state.py", scheduler)
        self.assertIn("@kilocode/sdk", scheduler)
        self.assertIn("createKilo", scheduler)

    def test_task_validation_ruff_is_task_scoped(self):
        for workflow in (ROOT / ".opencode", KILO):
            validator = (workflow / "scripts/tb2_validate_task.sh").read_text(
                encoding="utf-8"
            )
            self.assertIn('tb2_run_platform_ruff "$task_path"', validator)
            self.assertNotIn('ruff check --extend-select I "$SCRIPT_DIR"', validator)


if __name__ == "__main__":
    unittest.main()
