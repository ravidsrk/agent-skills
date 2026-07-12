#!/usr/bin/env python3
"""Behavioral tests for scripts/orca-coord/preflight.py.

Covers the D1 remediation: ref aliases of the default branch (origin/main,
refs/remotes/origin/main) must be rejected by the M-5 guardrail, not just the
literal branch name. Runs against real temp git repos; `gh` is faked with a
PATH shim so no network or auth is involved.
"""
from __future__ import annotations

import importlib.util
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
PREFLIGHT = REPO / "scripts" / "orca-coord" / "preflight.py"

FAKE_GH = """#!/usr/bin/env bash
# fake gh for preflight tests
args="$*"
case "$args" in
  *nameWithOwner*) echo "fake/repo" ;;
  *defaultBranchRef*) echo "main" ;;
  *) echo "{}" ;;
esac
exit 0
"""


def _git(cwd: Path, *args: str) -> None:
    subprocess.run(
        ["git", "-c", "user.name=Test", "-c", "user.email=test@example.com", *args],
        cwd=cwd, check=True, capture_output=True,
    )


class PreflightTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory()
        root = Path(cls.tmp.name)

        upstream = root / "upstream"
        upstream.mkdir()
        _git(upstream, "init", "-b", "main")
        (upstream / "README.md").write_text("hello\n")
        _git(upstream, "add", ".")
        _git(upstream, "commit", "-m", "init")

        cls.clone = root / "clone"
        _git(root, "clone", str(upstream), str(cls.clone))
        _git(cls.clone, "branch", "integration")  # fresh integration branch off main tip
        _git(cls.clone, "tag", "v1")  # tag at main tip — must NOT be accepted as BASE

        bindir = root / "bin"
        bindir.mkdir()
        gh = bindir / "gh"
        gh.write_text(FAKE_GH)
        gh.chmod(0o755)
        cls.env = dict(os.environ, PATH=f"{bindir}:{os.environ['PATH']}")

        spec = importlib.util.spec_from_file_location("preflight", PREFLIGHT)
        cls.mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(cls.mod)

    @classmethod
    def tearDownClass(cls):
        cls.tmp.cleanup()

    def run_cli(self, *args: str) -> subprocess.CompletedProcess:
        return subprocess.run(
            [sys.executable, str(PREFLIGHT), *args],
            cwd=self.clone, env=self.env, capture_output=True, text=True,
        )

    # --- unit: _canon_branch -------------------------------------------------
    def test_canon_branch_reduces_aliases(self):
        old = os.getcwd()
        os.chdir(self.clone)
        try:
            for alias in ("main", "origin/main", "refs/heads/main", "refs/remotes/origin/main"):
                self.assertEqual(self.mod._canon_branch(alias), "main", alias)
            self.assertEqual(self.mod._canon_branch("integration"), "integration")
        finally:
            os.chdir(old)

    # --- CLI: the M-5 guardrail against aliases (the D1 bypass) ---------------
    def test_rejects_literal_default(self):
        r = self.run_cli("--base", "main", "--default", "main")
        self.assertEqual(r.returncode, 2, r.stderr)

    def test_rejects_origin_alias(self):
        r = self.run_cli("--base", "origin/main", "--default", "main")
        self.assertEqual(r.returncode, 2, r.stderr)
        self.assertIn("'main'", r.stderr)

    def test_rejects_full_remote_ref_alias(self):
        r = self.run_cli("--base", "refs/remotes/origin/main", "--default", "main")
        self.assertEqual(r.returncode, 2, r.stderr)

    def test_accepts_real_integration_branch(self):
        r = self.run_cli("--base", "integration", "--default", "main")
        self.assertEqual(r.returncode, 0, r.stderr)
        # fresh branch shares the default tip: advisory warning, not a failure
        self.assertIn("BASE tip == default tip", r.stderr)

    def test_readonly_mode_skips_base_checks(self):
        r = self.run_cli("--mode", "readonly")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("mode=readonly", r.stdout)

    def test_write_mode_requires_base(self):
        r = self.run_cli("--default", "main")
        self.assertEqual(r.returncode, 1, r.stderr)  # usage → exit 1, not invariant 2
        self.assertIn("--base is required", r.stderr)

    def test_rejects_tag_as_base(self):
        r = self.run_cli("--base", "v1", "--default", "main")
        self.assertEqual(r.returncode, 2, r.stderr)
        self.assertIn("not accepted", r.stderr)

    def test_rejects_raw_sha_as_base(self):
        sha = subprocess.run(
            ["git", "rev-parse", "HEAD"], cwd=self.clone, capture_output=True, text=True
        ).stdout.strip()
        r = self.run_cli("--base", sha, "--default", "main")
        self.assertEqual(r.returncode, 2, r.stderr)


if __name__ == "__main__":
    unittest.main()
