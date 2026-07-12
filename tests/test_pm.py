#!/usr/bin/env python3
"""Behavioral tests for scripts/orca-coord/pm.py (tolerant mailbox parsing, E3).

Proves: a malformed segment mid-stream does not hide later messages; heartbeat
envelopes are skipped structurally (a mixed heartbeat+messages object keeps its
messages); missing message fields print placeholders instead of raising.
"""
from __future__ import annotations

import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
PM = REPO / "scripts" / "orca-coord" / "pm.py"


def run_pm(content: str) -> subprocess.CompletedProcess:
    with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as f:
        f.write(content)
        path = f.name
    return subprocess.run([sys.executable, str(PM), path], capture_output=True, text=True)


def msg(**kw) -> str:
    import json
    return json.dumps({"result": {"messages": [kw]}})


class PmTest(unittest.TestCase):
    def test_plain_stream(self):
        r = run_pm(msg(from_handle="w1", type="worker_done", subject="done", body="b", payload={}) + "\n"
                   + msg(from_handle="w2", type="status", subject="s", body="", payload=None))
        self.assertEqual(r.returncode, 0)
        self.assertIn("MESSAGES: 2", r.stdout)
        self.assertNotIn("WARN", r.stderr)

    def test_malformed_segment_does_not_hide_later_messages(self):
        content = (msg(from_handle="w1", type="status", subject="first", body="", payload=None) + "\n"
                   + '{"result": {"messages": [BROKEN\n'
                   + msg(from_handle="w2", type="status", subject="second", body="", payload=None) + "\n")
        r = run_pm(content)
        self.assertEqual(r.returncode, 0)
        self.assertIn("MESSAGES: 2", r.stdout)
        self.assertIn("second", r.stdout)
        self.assertIn("skipped 1 malformed segment", r.stderr)

    def test_heartbeat_only_envelope_skipped(self):
        content = ('{"_heartbeat": "2026-07-12T00:00:00Z"}\n'
                   + msg(from_handle="w1", type="status", subject="real", body="", payload=None))
        r = run_pm(content)
        self.assertIn("MESSAGES: 1", r.stdout)
        self.assertIn("real", r.stdout)

    def test_mixed_heartbeat_with_messages_keeps_messages(self):
        content = ('{"_heartbeat": "x", "result": {"messages": [{"from_handle": "w9", '
                   '"type": "status", "subject": "kept", "body": "", "payload": null}]}}')
        r = run_pm(content)
        self.assertIn("MESSAGES: 1", r.stdout)
        self.assertIn("kept", r.stdout)

    def test_missing_fields_print_placeholders(self):
        content = '{"result": {"messages": [{"subject": "only-subject"}]}}'
        r = run_pm(content)
        self.assertEqual(r.returncode, 0)
        self.assertIn("FROM: ? | TYPE: ?", r.stdout)
        self.assertIn("only-subject", r.stdout)


if __name__ == "__main__":
    unittest.main()
