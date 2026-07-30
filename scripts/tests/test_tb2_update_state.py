from __future__ import annotations

import argparse
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "tb2_update_state.py"
SPEC = importlib.util.spec_from_file_location("tb2_update_state", SCRIPT)
assert SPEC and SPEC.loader
state = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(state)

SUBMISSION = "00000000-0000-0000-0000-000000000001"
AUTOEVAL = (
    "AutoEval Execution Summary: AutoEval execution failed. Build status: FAILED..."
)


def feedback_text(
    difficulty: str = "EASY",
    instruction: str = "PASS",
    other_quality: str = "PASS",
    revision: str = "",
    test_count: str = "2 / 3",
) -> str:
    return f"""Revision Notes
-----
{revision}
Summary (Difficulty Check)
Difficulty: {difficulty}
Solvability: SOLVABLE
test_recovery: {test_count}
Quality Check Summary
Task Instruction Sufficiency: {instruction}
Verifier Alignment: {other_quality}
"""


class FeedbackExtractionTests(unittest.TestCase):
    def extract(self, text: str) -> dict:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "notes.txt").write_text(text, encoding="utf-8")
            return state.extract_feedback(root)

    def test_autoeval_only_is_not_actionable_and_is_incomplete(self):
        facts = self.extract(f"Revision Notes\n{AUTOEVAL}\n")
        self.assertEqual(facts["revision_notes"], "")
        self.assertIsNone(facts["revision_notes_hash"])
        self.assertFalse(facts["feedback_complete"])

    def test_autoeval_plus_real_text_keeps_only_real_text(self):
        facts = self.extract(
            feedback_text(revision=f"{AUTOEVAL}\nFix replay ordering.")
        )
        self.assertEqual(facts["revision_notes"], "Fix replay ordering.")

    def test_easy_extracts(self):
        self.assertEqual(self.extract(feedback_text())["difficulty"], "EASY")

    def test_trivial_extracts(self):
        self.assertEqual(
            self.extract(feedback_text(difficulty="TRIVIAL"))["difficulty"], "TRIVIAL"
        )

    def test_named_zero_pass_test_extracts(self):
        self.assertEqual(
            self.extract(feedback_text(test_count="0 / 4"))["zero_pass_tests"],
            ["test_recovery"],
        )

    def test_incomplete_feedback_is_flagged(self):
        self.assertFalse(self.extract("Revision Notes\n-----\n")["feedback_complete"])

    def test_instruction_only_failure_is_reviewer_eligible(self):
        facts = self.extract(feedback_text(difficulty="HARD", instruction="FAIL"))
        self.assertEqual(facts["instruction_sufficiency"], "FAIL")
        self.assertEqual(facts["quality_failures"], [])
        self.assertTrue(facts["feedback_complete"])

    def test_other_quality_failure_requires_checks(self):
        facts = self.extract(feedback_text(difficulty="HARD", other_quality="FAIL"))
        self.assertEqual(facts["quality_failures"], ["Verifier Alignment"])


class HistoryTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.state_root = self.root / "state"
        self.task = self.root / "tasks/example"
        (self.task / "environment").mkdir(parents=True)
        (self.task / "environment/main.c").write_text(
            "int main(void){return 1;}\n", encoding="utf-8"
        )

    def tearDown(self):
        self.temp.cleanup()

    def record(self, text: str, cooldown: int = 0):
        feedback_dir = self.root / f"feedback-{len(list(self.root.glob('feedback-*')))}"
        feedback_dir.mkdir()
        (feedback_dir / "notes.txt").write_text(text, encoding="utf-8")
        args = argparse.Namespace(
            submission_id=SUBMISSION,
            state_root=self.state_root,
            feedback_dir=feedback_dir,
            task=self.task,
            source_batch="batch",
            session_id="ses_test",
            cooldown_seconds=cooldown,
        )
        self.assertEqual(state.record_feedback(args), 0)
        return state.load_state(
            state.state_path(SUBMISSION, self.state_root), SUBMISSION
        )

    def test_first_low_result_has_level_one(self):
        saved = self.record(feedback_text())
        self.assertEqual(saved["iterations"][-1]["hardening_level"], 1)

    def test_repeated_low_after_checks_increments_level(self):
        saved = self.record(feedback_text())
        saved["iterations"][-1]["platform_result"] = "CHECKS SUBMITTED"
        saved["iterations"][-1]["checks_submitted_at"] = state.now_iso()
        state.save_state(state.state_path(SUBMISSION, self.state_root), saved)
        saved = self.record(feedback_text(), cooldown=0)
        self.assertEqual(saved["iterations"][-1]["hardening_level"], 2)

    def test_identical_feedback_inside_cooldown_is_unrefreshed(self):
        saved = self.record(feedback_text())
        saved["iterations"][-1]["platform_result"] = "CHECKS SUBMITTED"
        saved["iterations"][-1]["checks_submitted_at"] = state.now_iso()
        state.save_state(state.state_path(SUBMISSION, self.state_root), saved)
        saved = self.record(feedback_text(), cooldown=900)
        self.assertFalse(saved["iterations"][-1]["feedback"]["feedback_complete"])
        self.assertEqual(
            saved["iterations"][-1]["feedback"]["feedback_details"], "unrefreshed"
        )

    def test_difficulty_improvement_is_recorded(self):
        self.record(feedback_text())
        saved = self.record(feedback_text(difficulty="HARD"))
        self.assertEqual(saved["iterations"][-1]["feedback"]["difficulty"], "HARD")
        self.assertEqual(saved["iterations"][-1]["hardening_level"], 0)

    def test_same_note_same_cycle_is_addressed(self):
        saved = state.new_state(SUBMISSION)
        digest = state.notes_hash("Fix replay ordering.")
        saved["addressed_revision_notes"].append({"hash": digest, "reviewer_cycle": 1})
        self.assertEqual(state.addressed_status(saved, digest), "addressed")

    def test_same_note_new_reviewer_cycle_is_actionable(self):
        saved = state.new_state(SUBMISSION)
        digest = state.notes_hash("Fix replay ordering.")
        saved["addressed_revision_notes"].append({"hash": digest, "reviewer_cycle": 1})
        saved["reviewer_cycle"] = 2
        self.assertEqual(state.addressed_status(saved, digest), "new")

    def test_version_one_state_migrates(self):
        path = state.state_path(SUBMISSION, self.state_root)
        path.write_text(
            json.dumps(
                {
                    "submission_id": SUBMISSION,
                    "addressed_revision_notes": [{"hash": "x"}],
                }
            ),
            encoding="utf-8",
        )
        saved = state.load_state(path, SUBMISSION)
        self.assertEqual(saved["version"], 2)
        self.assertEqual(saved["addressed_revision_notes"][0]["reviewer_cycle"], 1)

    def test_batch_migration_is_idempotent(self):
        batch_root = self.root / "batches"
        batch = batch_root / "old"
        batch.mkdir(parents=True)
        (batch / "sessions.json").write_text(
            json.dumps(
                {
                    "batch_id": "old",
                    "submissions": {
                        SUBMISSION: {
                            "session_id": "ses_old",
                            "result": "SUCCESS",
                            "platform_action": "checks (--no-send-to-reviewer)",
                            "attempts": 2,
                            "notes": "legacy",
                        }
                    },
                }
            ),
            encoding="utf-8",
        )
        args = argparse.Namespace(batch_root=batch_root, state_root=self.state_root)
        self.assertEqual(state.migrate_batches(args), 0)
        self.assertEqual(state.migrate_batches(args), 0)
        saved = state.load_state(
            state.state_path(SUBMISSION, self.state_root), SUBMISSION
        )
        self.assertEqual(len(saved["iterations"]), 1)
        self.assertEqual(saved["iterations"][0]["platform_result"], "CHECKS SUBMITTED")
        self.assertTrue(saved["iterations"][0]["legacy"])

    def test_attempts_are_cumulative_and_reviewer_advances_cycle(self):
        saved = self.record(feedback_text(difficulty="HARD"))
        validation = argparse.Namespace(
            submission_id=SUBMISSION,
            state_root=self.state_root,
            mode="fast-only",
            result="passed",
        )
        self.assertEqual(state.record_validation(validation), 0)
        begin = argparse.Namespace(
            submission_id=SUBMISSION,
            state_root=self.state_root,
            mode="reviewer",
            task=self.task,
        )
        self.assertEqual(state.begin_platform_attempt(begin), 0)
        saved = state.load_state(
            state.state_path(SUBMISSION, self.state_root), SUBMISSION
        )
        attempt = saved["iterations"][-1]["platform_attempts"][-1]["attempt_id"]
        finish = argparse.Namespace(
            submission_id=SUBMISSION,
            state_root=self.state_root,
            attempt_id=attempt,
            outcome="transient_failure",
        )
        self.assertEqual(state.finish_platform_attempt(finish), 0)
        self.assertEqual(state.begin_platform_attempt(begin), 0)
        saved = state.load_state(
            state.state_path(SUBMISSION, self.state_root), SUBMISSION
        )
        attempt = saved["iterations"][-1]["platform_attempts"][-1]["attempt_id"]
        finish.attempt_id = attempt
        finish.outcome = "reviewer_submitted"
        self.assertEqual(state.finish_platform_attempt(finish), 0)
        saved = state.load_state(
            state.state_path(SUBMISSION, self.state_root), SUBMISSION
        )
        self.assertEqual(len(saved["iterations"][-1]["platform_attempts"]), 2)
        self.assertEqual(saved["reviewer_cycle"], 2)
        self.assertEqual(saved["iterations"][-1]["platform_result"], "SENT TO REVIEWER")

    def test_hardening_gate_uses_actual_source_delta(self):
        self.record(feedback_text())
        (self.task / "environment/main.c").write_text(
            "int main(void){return 2;}\n", encoding="utf-8"
        )
        evidence_file = self.root / "hardening.json"
        evidence_file.write_text(
            json.dumps(
                {
                    "prior_difficulty": "EASY",
                    "prior_agent_performance": {},
                    "successful_trace_sources": [],
                    "common_success_strategy": "patched the local return value",
                    "prior_failed_hardening": [],
                    "starting_state_files_changed": ["environment/main.c"],
                    "defect_families": [
                        {
                            "name": "replay ordering",
                            "root_cause": "state is committed before validation",
                            "source_delta": ["environment/main.c"],
                            "interacts_with": ["recovery"],
                            "strategy_invalidated": "local return patch",
                            "oracle_signal": "oracle repairs commit ordering",
                            "verifier_signal": "restart test checks recovered state",
                        }
                    ],
                    "contract_changes": [],
                    "removed_or_replaced_shallow_complexity": [],
                }
            ),
            encoding="utf-8",
        )
        args = argparse.Namespace(
            submission_id=SUBMISSION,
            state_root=self.state_root,
            task=self.task,
            evidence_file=evidence_file,
        )
        self.assertEqual(state.record_hardening(args), 0)


class FingerprintTests(unittest.TestCase):
    def test_generated_files_are_excluded(self):
        with tempfile.TemporaryDirectory() as directory:
            task = Path(directory)
            (task / "environment").mkdir()
            (task / "environment/main.c").write_text("one", encoding="utf-8")
            first = state.task_fingerprint(task)
            (task / ".snorkel_config").write_text("changed", encoding="utf-8")
            (task / "archive.zip").write_bytes(b"changed")
            self.assertEqual(first, state.task_fingerprint(task))


if __name__ == "__main__":
    unittest.main()
