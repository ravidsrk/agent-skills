#!/usr/bin/env python3
"""Static contract checks for fleet-ops ledger templates + specialist ids.

Reverting a completion-contract section or drifting NEVER_GATE names should fail CI.
"""
from __future__ import annotations

import re
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
SKILLS = REPO / "skills"

# Headings (## ) that each skill's completion contract requires in its ledger template.
REQUIRED_HEADINGS = {
    "quorum": [
        "Ballot",
        "Fan-outs / denominator",
        "Votes / replies",
        "Reduction",
        "Outcome / route",
    ],
    "spec-decompose": [
        "Slice ↔ task-id",
        "DAG verification",
        "Loop declaration",
    ],
    "ephemeral-fleet": [
        "Lanes",
    ],
    "fleet-memory": [
        "Injected keys",
        "Worker echoes",
        "Specialist stats / gating",
        "REFLECT writes",
    ],
}

CANONICAL_SPECIALISTS = {
    "standards",
    "spec",
    "security-lite",
    "test-adequacy",
    "sql",
    "authz",
    "llm-trust",
    "side-effects",
}

NEVER_GATE = {"security-lite", "authz", "sql"}


def _headings(text: str) -> list[str]:
    return re.findall(r"^## (.+)$", text, flags=re.M)


class LedgerContractTest(unittest.TestCase):
    def test_ledger_templates_contain_required_sections(self):
        for skill, required in REQUIRED_HEADINGS.items():
            path = SKILLS / skill / "references" / "ledger-template.md"
            self.assertTrue(path.is_file(), f"missing {path}")
            text = path.read_text(encoding="utf-8")
            heads = _headings(text)
            for needle in required:
                self.assertTrue(
                    any(needle in h for h in heads),
                    f"{skill}: ledger missing section containing {needle!r}; have {heads}",
                )

    def test_fleet_memory_documents_canonical_specialists_and_never_gate(self):
        skill = (SKILLS / "fleet-memory" / "SKILL.md").read_text(encoding="utf-8")
        for sid in CANONICAL_SPECIALISTS:
            self.assertIn(f"`{sid}`", skill, f"fleet-memory missing specialist id {sid}")
        # Collect EVERY backtick id in the NEVER_GATE clause (not a fixed 3-group regex,
        # which would false-green if the list grows and only the constant is updated).
        m = re.search(r"\*\*NEVER_GATE\*\*.*?(?:\n-|\n\n)", skill, flags=re.S)
        self.assertIsNotNone(m, "NEVER_GATE clause not found in fleet-memory SKILL.md")
        found = set(re.findall(r"`([^`]+)`", m.group(0)))
        self.assertEqual(found, NEVER_GATE)

    def test_review_fleets_use_canonical_never_gate_ids(self):
        rm = (SKILLS / "review-matrix" / "SKILL.md").read_text(encoding="utf-8")
        rp = (SKILLS / "review-prod-fleet" / "SKILL.md").read_text(encoding="utf-8")
        self.assertIn("`security-lite`", rm)
        self.assertNotIn("security/authz", rm)
        self.assertNotIn("data-migration", rm)
        self.assertIn("`authz`", rp)
        self.assertIn("`sql`", rp)
        self.assertNotIn("security/authz", rp)
        self.assertNotIn("data-migration", rp)

    def test_fleet_memory_store_seeded(self):
        store = REPO / "docs" / "fleet-memory"
        self.assertTrue((store / "learnings.jsonl").is_file())
        self.assertTrue((store / "specialist-stats.jsonl").is_file())
        self.assertTrue((store / "README.md").is_file())


if __name__ == "__main__":
    unittest.main()
