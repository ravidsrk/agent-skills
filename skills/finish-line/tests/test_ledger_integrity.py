"""Synthetic parser fixtures only: PASS/APPROVE strings are not product verification."""
import copy
import hashlib
import json
import os
import re
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

SKILL = Path(__file__).resolve().parents[1]
LEDGER = SKILL / "scripts/ledger.sh"


class LedgerIntegrity(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        for tool in ("git", "jq", "bash"):
            if not shutil.which(tool):
                raise RuntimeError(f"required regression tool unavailable: {tool}")

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="synthetic-ledger-parser-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.fd = self.root / ".finish"
        self.fd.mkdir()
        self.env = {**os.environ, "GIT_CONFIG_GLOBAL": os.devnull, "GIT_CONFIG_SYSTEM": os.devnull,
                    "FINISH_MAX_AMENDMENTS": "0"}
        self.git("init", "--quiet")
        self.git("config", "user.name", "Synthetic parser fixture")
        self.git("config", "user.email", "synthetic@example.invalid")
        self.write(".gitignore", ".finish/evidence/\n.finish/PRODUCT.md\n")
        self.write("intent.md", "Synthetic parser fixtures never certify product acceptance.\n")
        self.brief = {
            "product": "Synthetic parser fixture", "one_liner": "Synthetic parser fixture only",
            "one_liner_claims": ["B-001"], "docs": ["intent.md"], "unknowns": [],
            "claims": [{"id": "B-001", "basis": "doc", "claim": "Synthetic parser fixture only",
                        "source": "intent.md", "quote": "Synthetic parser fixtures never certify product acceptance."}],
        }
        self.item = {
            "id": "J-001", "type": "journey", "priority": "P0", "platforms": ["api"],
            "title": "Synthetic parser fixture only", "source": "B-001",
            "acceptance": ["Given a synthetic fixture, when the parser checks it, then identity is retained"],
            "verify": {"method": "api", "spec": "api/finish/selected.test.ts"},
            "status": "failing", "attempts": 0, "evidence": [], "notes": "",
        }
        self.ledger = {"product": self.brief["product"], "one_liner": self.brief["one_liner"],
                       "items": [copy.deepcopy(self.item)]}
        self.save()
        self.write("api/finish/selected.test.ts", "expect(syntheticValue).toBe(1);\n")
        self.git("add", ".")
        self.git("commit", "--quiet", "-m", "Synthetic parser fixture, not product acceptance")

    def write(self, path, content):
        p = self.root / path
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(content)
        return p

    def save(self):
        self.write(".finish/ledger.json", json.dumps(self.ledger, indent=2) + "\n")
        self.write(".finish/product.json", json.dumps(self.brief, indent=2) + "\n")

    def git(self, *args):
        return subprocess.check_output(["git", *args], cwd=self.root, env=self.env, text=True).strip()

    def run_ledger(self, *args, env=None):
        return subprocess.run(["bash", str(LEDGER), *args], cwd=self.root,
                              env=env or self.env, text=True, capture_output=True)

    def criterion(self, item=None):
        definition = {k: v for k, v in (item or self.ledger["items"][0]).items()
                      if k not in ("status", "attempts", "evidence", "notes")}
        payload = {"product": self.ledger["product"], "one_liner": self.ledger["one_liner"],
                   "brief": hashlib.sha256((self.fd / "product.json").read_bytes()).hexdigest(),
                   "item": definition}
        return hashlib.sha256((json.dumps(payload, separators=(",", ":"), sort_keys=True) + "\n").encode()).hexdigest()

    def report(self, criterion=None, extra=""):
        state = self.run_ledger("state")
        self.assertEqual(state.returncode, 0, state.stderr)
        self.write(".finish/evidence/J-001/synthetic.log", "Synthetic parser evidence, no product result.\n")
        self.write(".finish/evidence/J-001/verifier/report.md",
                   f"VERDICT: PASS\nSTATE: {state.stdout.strip()}\nCRITERION: {criterion or self.criterion()}\n{extra}")

    def simulated_frozen(self):
        self.write(".finish/FREEZE", self.git("rev-parse", "HEAD") + "\n")
        digest = self.run_ledger("hash")
        self.assertEqual(digest.returncode, 0, digest.stderr)
        self.write(".finish/LEDGER.lock", digest.stdout)

    def approve(self):
        # Explicitly synthetic review parser data; no independent product verdict.
        req = self.fd / "freeze-review/request.md"
        if not req.exists():
            req = self.fd / "freeze/request.md"
        self.assertTrue(req.is_file())
        self.write(str(req.parent.relative_to(self.root) / "review.md"),
                   "VERDICT: APPROVE\nREQUEST: " + hashlib.sha256(req.read_bytes()).hexdigest() + "\n")

    def copied_gate(self):
        for name in ("ledger.sh", "lib.sh", "tamper.sh"):
            p = self.root / ".finish/bin" / name
            p.parent.mkdir(exist_ok=True)
            shutil.copyfile(SKILL / "scripts" / name, p)
            p.chmod(0o755)
        gate = (SKILL / "templates/verify.sh").read_text()
        gate = re.sub(r'^(STAGE_[A-Z0-9_]+)="[^"\n]*"', r'\1="true"', gate, flags=re.M)
        gate = gate.replace('STAGE_API="true"', 'STAGE_API="touch synthetic-api-executed"')
        self.write(".finish/verify.sh", gate)
        return subprocess.run(["bash", ".finish/verify.sh"], cwd=self.root,
                              env=self.env, capture_output=True, text=True)

    def test_copied_gate_fails_on_selected_missing_spec(self):
        (self.root / self.item["verify"]["spec"]).unlink()
        result = self.copied_gate()
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn("GATE: FAIL at API", result.stdout)
        self.assertNotIn("GATE: PASS", result.stdout)
        self.assertFalse((self.root / "synthetic-api-executed").exists())

    def test_copied_gate_executes_existing_selected_spec(self):
        result = self.copied_gate()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertTrue((self.root / "synthetic-api-executed").exists())

    def test_request_directory_is_not_treated_as_a_pending_review(self):
        (self.fd / "freeze-review/request.md").mkdir(parents=True)
        result = self.run_ledger("lock")
        self.assertNotIn(result.returncode, (0, 3), result.stdout)
        self.assertFalse((self.fd / "FREEZE").exists())

    def test_failed_marker_install_rolls_back_own_lock(self):
        self.assertEqual(self.run_ledger("lock").returncode, 3)
        self.approve()
        bindir = self.root / "fail-marker-bin"
        bindir.mkdir()
        real_mv = shutil.which("mv")
        self.write("fail-marker-bin/mv", '#!/usr/bin/env bash\nfor a in "$@"; do\n'
                   'case "$a" in */.finish/FREEZE) exit 74 ;; esac\ndone\n'
                   f'exec "{real_mv}" "$@"\n').chmod(0o755)
        result = self.run_ledger("lock", env={**self.env, "PATH": str(bindir) + os.pathsep + self.env["PATH"]})
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertNotIn("frozen at", result.stdout)
        self.assertFalse((self.fd / "FREEZE").exists())
        self.assertFalse((self.fd / "LEDGER.lock").exists())

    def test_selected_missing_spec_refuses_without_partial_paths(self):
        other = copy.deepcopy(self.item)
        other["id"] = "J-002"
        other["verify"]["spec"] = "api/finish/missing.test.ts"
        self.ledger["items"].append(other)
        self.save()
        result = self.run_ledger("specs", "--method", "api")
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertEqual(result.stdout, "")
        self.assertIn("J-002", result.stderr)

    def test_selected_directory_spec_refuses(self):
        (self.root / self.item["verify"]["spec"]).unlink()
        (self.root / self.item["verify"]["spec"]).mkdir()
        self.assertNotEqual(self.run_ledger("specs", "--method", "api").returncode, 0)

    def test_unselected_missing_spec_does_not_refuse(self):
        other = copy.deepcopy(self.item)
        other.update(id="J-002", priority="P1")
        other["verify"]["spec"] = "api/finish/missing.test.ts"
        self.ledger["items"].append(other)
        self.save()
        result = self.run_ledger("specs", "--method", "api")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), self.item["verify"]["spec"])
        self.assertEqual(self.run_ledger("specs", "--passing").stdout, "")

    def test_new_report_identity_allows_pass_and_mutable_fields_do_not_change_it(self):
        digest = self.run_ledger("criteria", "J-001")
        self.assertEqual(digest.returncode, 0, digest.stderr)
        self.assertEqual(digest.stdout.strip(), self.criterion())
        self.report()
        result = self.run_ledger("pass", "J-001")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.run_ledger("criteria", "J-001").stdout, digest.stdout)

    def test_old_pass_refuses_after_strengthening_with_same_code_state(self):
        self.simulated_frozen()
        self.report()
        old_state = self.run_ledger("state").stdout
        proposed = copy.deepcopy(self.ledger)
        proposed["items"][0]["acceptance"].append(
            "Given a stronger synthetic fixture, when verified, then the extra criterion must be checked")
        self.write(".finish/ledger.proposed.json", json.dumps(proposed))
        amendment = self.run_ledger("amend", "Synthetic additive criterion parser test")
        self.assertEqual(amendment.returncode, 0, amendment.stdout + amendment.stderr)
        self.assertEqual(self.run_ledger("state").stdout, old_state)
        result = self.run_ledger("pass", "J-001")
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn("CRITERION", result.stderr)

    def test_missing_or_duplicate_identity_refuses(self):
        self.report(extra="CRITERION: " + self.criterion() + "\n")
        self.assertNotEqual(self.run_ledger("pass", "J-001").returncode, 0)
        p = self.fd / "evidence/J-001/verifier/report.md"
        p.write_text("\n".join(x for x in p.read_text().splitlines() if not x.startswith("CRITERION:")))
        self.assertNotEqual(self.run_ledger("pass", "J-001").returncode, 0)

    def test_public_refreeze_is_rejected_without_changing_markers(self):
        self.simulated_frozen()
        marker = (self.fd / "FREEZE").read_bytes()
        lock = (self.fd / "LEDGER.lock").read_bytes()
        self.ledger["items"][0]["title"] = "Unapproved synthetic change"
        self.save()
        self.git("add", ".finish/ledger.json")
        self.git("commit", "--quiet", "-m", "Synthetic unapproved definition mutation")
        result = self.run_ledger("lock", "--refreeze")
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertEqual((self.fd / "FREEZE").read_bytes(), marker)
        self.assertEqual((self.fd / "LEDGER.lock").read_bytes(), lock)

    def test_native_first_freeze_uses_unambiguous_review_directory(self):
        request = self.run_ledger("lock")
        self.assertEqual(request.returncode, 3, request.stdout + request.stderr)
        self.assertTrue((self.fd / "freeze-review/request.md").is_file())
        self.assertFalse((self.fd / "FREEZE").exists())
        self.approve()
        result = self.run_ledger("lock")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertTrue((self.fd / "FREEZE").is_file())
        self.assertEqual(self.run_ledger("freeze-check").returncode, 0)
        self.assertNotEqual(self.run_ledger("lock").returncode, 0)

    def test_occupied_marker_paths_fail_without_success_output(self):
        (self.fd / "FREEZE").mkdir()
        result = self.run_ledger("lock")
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertNotIn("frozen at", result.stdout)
        self.assertFalse((self.fd / "LEDGER.lock").exists())

    def test_failed_lock_install_does_not_report_frozen(self):
        self.assertEqual(self.run_ledger("lock").returncode, 3)
        self.approve()
        bindir = self.root / "fail-bin"
        bindir.mkdir()
        real_mv = shutil.which("mv")
        self.write("fail-bin/mv", '#!/usr/bin/env bash\nfor a in "$@"; do\n'
                   'case "$a" in */.finish/LEDGER.lock) exit 73 ;; esac\ndone\n'
                   f'exec "{real_mv}" "$@"\n').chmod(0o755)
        result = self.run_ledger("lock", env={**self.env, "PATH": str(bindir) + os.pathsep + self.env["PATH"]})
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertNotIn("frozen at", result.stdout)
        self.assertFalse((self.fd / "FREEZE").exists())


if __name__ == "__main__":
    unittest.main()
