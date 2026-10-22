"""Synthetic configured-gate fixtures, never product acceptance.

verify-legacy.sh is the exact shipped template from 032e2aad. Only STAGE_*
assignments and an extra comment are configured below; no gate implementation
is substituted. The real new ledger/bin run before and after migration.
"""
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import unittest

SKILL = Path(__file__).resolve().parents[1]
OLD = '      specs="$(specs_for "$s")"\n'
NEW = '''      if ! specs="$(specs_for "$s")"; then
        line "$s" FAIL 0 "could not select valid ledger specs"
        echo "GATE: FAIL at $s" | tee -a "$summary"; exit 1
      fi
'''


class GateUpgrade(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="synthetic-gate-upgrade-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.fd = self.root / ".finish"
        (self.fd / "bin").mkdir(parents=True)
        self.env = {**os.environ, "GIT_CONFIG_GLOBAL": os.devnull,
                    "GIT_CONFIG_SYSTEM": os.devnull, "FINISH_AGENT": "true",
                    "FINISH_COMPANIONS": "off", "MAX_SESSIONS": "0"}
        self.run_command("git", "init", "-q", check=True)
        self.run_command("git", "config", "user.name", "Synthetic gate fixture", check=True)
        self.run_command("git", "config", "user.email", "synthetic@example.invalid", check=True)
        self.write(".gitignore", ".finish/evidence/\n.finish/logs/\n.finish/companions.json\n.claude/settings.local.json\n")
        self.write(".finish/RUN", "Synthetic configured-gate parser test only\n")
        self.write(".finish/STATUS", "AUDITING\n")
        self.write(".finish/SCOPE", "P0\n")
        self.copy_bin()
        self.existing = "api/finish/existing selected.test.ts"
        self.write(self.existing, "expect(syntheticValue).toBe(1);\n")
        self.items = [self.item("J-001", self.existing), self.item("J-002", "api/finish/missing.test.ts")]
        self.save_items()
        legacy = (SKILL / "tests/fixtures/verify-legacy.sh").read_text()
        self.assertEqual(hashlib.sha256(legacy.encode()).hexdigest(),
                         "aa5ac4da2d6305450e4eac6abe901b01a10b92fbd71bdb735aee3654410636d6")
        self.assertIn(OLD, legacy)
        self.assertNotIn(NEW, legacy)
        self.gate = re.sub(r'^(STAGE_[A-Z0-9_]+)="[^"\n]*"', r'\1="true"', legacy, flags=re.M)
        self.gate = self.gate.replace('STAGE_API="true"',
                                      "STAGE_API=\"printf '%s\\n' > synthetic-executed {}\"")
        self.gate += "\n# Synthetic configured suffix remains byte-for-byte.\n"
        self.write(".finish/verify.sh", self.gate).chmod(0o751)
        self.commit()

    def item(self, id, spec):
        return {"id": id, "priority": "P0", "status": "passing", "verify": {"method": "api", "spec": spec}}

    def write(self, path, text):
        p = self.root / path
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(text)
        return p

    def save_items(self):
        self.write(".finish/ledger.json", json.dumps({"items": self.items}) + "\n")

    def copy_bin(self):
        for name in ("ledger.sh", "lib.sh", "tamper.sh"):
            dest = self.fd / "bin" / name
            shutil.copyfile(SKILL / "scripts" / name, dest)
            dest.chmod(0o755)

    def run_command(self, *args, check=False):
        return subprocess.run(args, cwd=self.root, env=self.env, text=True,
                              capture_output=True, check=check)

    def upgrade(self, mode):
        return self.run_command("bash", str(SKILL / "scripts/upgrade-gate.sh"), mode)

    def commit(self):
        self.run_command("git", "add", ".", check=True)
        self.run_command("git", "commit", "-qm", "Synthetic configured-gate fixture, not product acceptance", check=True)

    def fingerprint(self):
        return {str(p.relative_to(self.root)): (hashlib.sha256(p.read_bytes()).hexdigest(), p.stat().st_mode)
                for p in self.fd.rglob("*") if p.is_file()}

    def frozen(self):
        self.write(".finish/FREEZE", self.run_command("git", "rev-parse", "HEAD").stdout)
        self.write(".finish/LEDGER.lock", "synthetic-marker-not-product-approval\n")
        self.commit()

    def test_legacy_gate_with_new_bin_demonstrates_false_pass(self):
        selector = self.run_command("bash", ".finish/bin/ledger.sh", "specs", "--method", "api")
        self.assertNotEqual(selector.returncode, 0)
        self.assertEqual(selector.stdout, "")
        result = self.run_command("bash", ".finish/verify.sh")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("GATE: PASS", result.stdout)
        self.assertIn("no specs yet", result.stdout)
        self.assertFalse((self.root / "synthetic-executed").exists())

    def test_migrated_gate_missing_selection_fails_instead_of_skipping_existing(self):
        migration = self.upgrade("--apply")
        self.assertEqual(migration.returncode, 0, migration.stderr)
        result = self.run_command("bash", ".finish/verify.sh")
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("GATE: FAIL at API", result.stdout)
        self.assertNotIn("GATE: PASS", result.stdout)
        self.assertFalse((self.root / "synthetic-executed").exists())

    def test_migration_preserves_all_other_bytes_commands_and_mode(self):
        before = (self.fd / "verify.sh").stat().st_mode
        result = self.upgrade("--apply")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.fd / "verify.sh").read_text(), self.gate.replace(OLD, NEW))
        self.assertEqual((self.fd / "verify.sh").stat().st_mode, before)
        self.assertEqual(self.upgrade("--apply").returncode, 0)
        self.assertEqual((self.fd / "verify.sh").read_text(), self.gate.replace(OLD, NEW))

    def test_migrated_existing_specs_execute_full_and_quick_with_exact_paths(self):
        self.items = self.items[:1]
        self.save_items()
        self.assertEqual(self.upgrade("--apply").returncode, 0)
        # {} interpolation in the shipped gate is intentionally not a quoting contract;
        # use its path-appending mode for a path containing spaces.
        gate = (self.fd / "verify.sh").read_text().replace(
            "STAGE_API=\"printf '%s\\n' > synthetic-executed {}\"",
            "STAGE_API=\"printf '%s\\n' > synthetic-executed\"")
        self.write(".finish/verify.sh", gate)
        for args in ((), ("--quick",)):
            result = self.run_command("bash", ".finish/verify.sh", *args)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertEqual((self.root / "synthetic-executed").read_text(), self.existing + "\n")

    def test_check_and_propose_are_read_only(self):
        before = self.fingerprint()
        check = self.upgrade("--check")
        self.assertNotEqual(check.returncode, 0)
        proposal = self.upgrade("--propose")
        self.assertEqual(proposal.returncode, 0, proposal.stderr)
        self.assertEqual(proposal.stdout, self.gate.replace(OLD, NEW))
        self.assertEqual(self.fingerprint(), before)

    def test_frozen_apply_refuses_without_touching_gate_bin_or_markers(self):
        self.frozen()
        before = self.fingerprint()
        result = self.upgrade("--apply")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("frozen", result.stderr.lower())
        self.assertEqual(self.fingerprint(), before)

    def test_frozen_proposal_is_read_only_for_reviewed_gate_amendment(self):
        self.frozen()
        before = self.fingerprint()
        proposal = self.upgrade("--propose")
        self.assertEqual(proposal.returncode, 0, proposal.stderr)
        self.assertEqual(proposal.stdout, self.gate.replace(OLD, NEW))
        self.assertEqual(self.fingerprint(), before)

    def test_unknown_custom_selector_is_not_overwritten(self):
        self.write(".finish/verify.sh", self.gate.replace(OLD, OLD + "      true # unrecognized custom selector behavior\n"))
        before = self.fingerprint()
        for mode in ("--check", "--propose", "--apply"):
            self.assertNotEqual(self.upgrade(mode).returncode, 0)
        self.assertEqual(self.fingerprint(), before)

    def test_duplicate_selector_is_refused(self):
        self.write(".finish/verify.sh", self.gate + OLD)
        before = self.fingerprint()
        self.assertNotEqual(self.upgrade("--apply").returncode, 0)
        self.assertEqual(self.fingerprint(), before)

    def test_symlink_gate_is_refused(self):
        target = self.root / "outside-gate.sh"
        (self.fd / "verify.sh").rename(target)
        (self.fd / "verify.sh").symlink_to(target)
        before = target.read_bytes()
        self.assertNotEqual(self.upgrade("--apply").returncode, 0)
        self.assertEqual(target.read_bytes(), before)
        self.assertTrue((self.fd / "verify.sh").is_symlink())

    def test_scaffold_refuses_new_bin_next_to_legacy_gate(self):
        self.write(".finish/bin/ledger.sh", "synthetic old-bin sentinel\n")
        before = self.fingerprint()
        result = self.run_command("bash", str(SKILL / "scripts/scaffold.sh"))
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("upgrade-gate", result.stdout + result.stderr)
        self.assertEqual(self.fingerprint(), before)

    def test_runner_refuses_new_bin_next_to_legacy_frozen_gate(self):
        self.write(".finish/bin/ledger.sh", "synthetic old-bin sentinel\n")
        self.frozen()
        before = self.fingerprint()
        result = self.run_command("bash", str(SKILL / "scripts/finish.sh"), str(self.root))
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("upgrade-gate", result.stdout + result.stderr)
        self.assertEqual(self.fingerprint(), before)

    def test_runner_checks_compatibility_on_selected_run_branch(self):
        starting_branch = self.run_command("git", "branch", "--show-current").stdout.strip()
        self.run_command("git", "branch", "finish-line", check=True)
        self.run_command("git", "checkout", "-q", "finish-line", check=True)
        self.write(".finish/verify.sh", self.gate.replace(OLD, NEW))
        self.commit()
        self.run_command("git", "checkout", "-q", starting_branch, check=True)

        result = self.run_command("bash", str(SKILL / "scripts/finish.sh"), str(self.root))

        self.assertEqual(result.returncode, 3, result.stdout + result.stderr)
        self.assertIn("switched to the finish-line branch", result.stdout)
        self.assertIn("Session cap MAX_SESSIONS=0 reached", result.stdout)
        self.assertEqual(self.run_command("git", "branch", "--show-current").stdout.strip(), "finish-line")

    def test_frozen_compatible_gate_with_stale_bin_is_never_reanchored(self):
        self.write(".finish/verify.sh", self.gate.replace(OLD, NEW))
        self.write(".finish/bin/lib.sh", "synthetic old-bin sentinel\n")
        self.frozen()
        before = self.fingerprint()
        for script in ("scaffold.sh", "finish.sh"):
            result = self.run_command("bash", str(SKILL / "scripts" / script))
            self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn("frozen", result.stdout.lower() + result.stderr.lower())
            self.assertEqual(self.fingerprint(), before)

    def test_prefreeze_scaffold_refreshes_bin_only_after_explicit_gate_repair(self):
        self.write(".finish/bin/ledger.sh", "synthetic old-bin sentinel\n")
        self.assertEqual(self.upgrade("--apply").returncode, 0)
        expected_gate = (self.fd / "verify.sh").read_bytes()
        result = self.run_command("bash", str(SKILL / "scripts/scaffold.sh"))
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual((self.fd / "verify.sh").read_bytes(), expected_gate)
        for name in ("ledger.sh", "lib.sh", "tamper.sh"):
            self.assertEqual((self.fd / "bin" / name).read_bytes(), (SKILL / "scripts" / name).read_bytes())
        gate = self.run_command("bash", ".finish/verify.sh")
        self.assertNotEqual(gate.returncode, 0)
        self.assertIn("GATE: FAIL at API", gate.stdout)

    def test_fresh_scaffold_installs_current_gate(self):
        shutil.rmtree(self.fd)
        result = self.run_command("bash", str(SKILL / "scripts/scaffold.sh"))
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual((self.fd / "verify.sh").read_bytes(), (SKILL / "templates/verify.sh").read_bytes())
        self.assertEqual(self.upgrade("--check").returncode, 0)

    def test_failed_install_preserves_gate_and_reports_no_success(self):
        tools = self.root / "synthetic-tools"
        tools.mkdir()
        mv = self.write("synthetic-tools/mv", "#!/bin/sh\nexit 73\n")
        mv.chmod(0o755)
        self.env["PATH"] = str(tools) + os.pathsep + self.env["PATH"]
        before = self.fingerprint()
        result = self.upgrade("--apply")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("could not install repaired gate", result.stderr)
        self.assertNotIn("gate selector repaired", result.stdout)
        self.assertEqual(self.fingerprint(), before)
        self.assertFalse((self.fd / ".gate-upgrade.lock").exists())
        self.assertEqual(list(self.fd.glob(".verify-*")), [])

    def test_active_runner_refuses_apply_without_gate_change(self):
        (self.root / ".git/finish-line.lock").mkdir()
        before = self.fingerprint()
        result = self.upgrade("--apply")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("runner active", result.stderr)
        self.assertEqual(self.fingerprint(), before)

    def test_new_scaffold_refuses_symlink_bin_even_without_existing_gate(self):
        (self.fd / "verify.sh").unlink()
        shutil.rmtree(self.fd / "bin")
        outside = self.root / "outside-bin"
        outside.mkdir()
        (self.fd / "bin").symlink_to(outside, target_is_directory=True)
        result = self.run_command("bash", str(SKILL / "scripts/scaffold.sh"))
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("symlink bin", result.stderr)
        self.assertEqual(list(outside.iterdir()), [])
        self.assertFalse((self.fd / "verify.sh").exists())

    def test_nontext_gate_is_refused_without_rewriting_bytes(self):
        gate = self.fd / "verify.sh"
        gate.write_bytes(gate.read_bytes() + b"# synthetic NUL \x00 suffix\n")
        before = self.fingerprint()
        result = self.upgrade("--apply")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("NUL", result.stderr)
        self.assertEqual(self.fingerprint(), before)

    def test_orphan_or_symlink_markers_also_refuse_apply(self):
        for name in ("FREEZE", "LEDGER.lock"):
            marker = self.fd / name
            for symlink in (False, True):
                if symlink:
                    marker.symlink_to("synthetic-missing-target")
                else:
                    marker.write_text("synthetic orphan marker\n")
                original = (self.fd / "verify.sh").read_bytes()
                result = self.upgrade("--apply")
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("frozen", result.stderr)
                self.assertEqual((self.fd / "verify.sh").read_bytes(), original)
                self.assertTrue(marker.is_symlink() if symlink else marker.is_file())
                marker.unlink()

    def test_ledger_fixture_isolated_from_hostile_global_signing_config(self):
        cfg = self.write("synthetic-global.gitconfig", "[commit]\n gpgsign = true\n[gpg]\n program = /synthetic/nonexistent/signing-program\n")
        env = {**self.env, "GIT_CONFIG_GLOBAL": str(cfg)}
        result = subprocess.run([
            sys.executable, "-m", "unittest", "discover", "-s", str(SKILL / "tests"),
            "-p", "test_ledger_integrity.py", "-k", "test_copied_gate_executes_existing_selected_spec", "-v",
        ], cwd=self.root, env=env, text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("Ran 1 test", result.stderr)
        self.assertIn("OK", result.stderr)
        self.assertIn("commit", cfg.read_text())

    def test_current_gate_and_matching_frozen_bin_pass_read_only_check(self):
        self.write(".finish/verify.sh", self.gate.replace(OLD, NEW))
        self.frozen()
        before = self.fingerprint()
        result = self.upgrade("--check")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.fingerprint(), before)


if __name__ == "__main__":
    unittest.main()
