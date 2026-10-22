"""Native tamper regressions in disposable Git fixtures, never product acceptance.

Uses --base to model a frozen baseline without approving or freezing a real run.
Run: python3 -m unittest discover -s skills/finish-line/tests -p test_tamper_integrity.py -v
"""

import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


SCRIPTS = Path(__file__).resolve().parents[1] / "scripts"


class TamperIntegrity(unittest.TestCase):
    def setUp(self):
        self.scratch = tempfile.TemporaryDirectory(prefix="finish-tamper-fixture-")
        self.addCleanup(self.scratch.cleanup)
        self.root = Path(self.scratch.name)
        self.env = {**os.environ, "GIT_CONFIG_GLOBAL": os.devnull, "GIT_CONFIG_SYSTEM": os.devnull}
        self.run_command("git", "init", "-q")
        self.run_command("git", "config", "user.name", "Finish Test")
        self.run_command("git", "config", "user.email", "finish@example.invalid")

    def run_command(self, *args, check=True):
        return subprocess.run(args, cwd=self.root, env=self.env, text=True,
                              stdout=subprocess.PIPE, stderr=subprocess.STDOUT, check=check)

    def write(self, path, content):
        target = self.root / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(content, encoding="utf-8")

    def baseline(self, files):
        for path, content in files.items():
            self.write(path, content)
        self.run_command("git", "add", ".")
        self.run_command("git", "commit", "-qm", "synthetic tamper parser baseline")
        self.base = self.run_command("git", "rev-parse", "HEAD").stdout.strip()

    def tamper(self):
        return self.run_command("bash", str(SCRIPTS / "tamper.sh"), "--base", self.base, check=False)

    def assert_clean(self):
        result = self.tamper()
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertIn("TAMPER: CLEAN", result.stdout)

    def assert_refused(self, message):
        result = self.tamper()
        self.assertEqual(result.returncode, 1, result.stdout)
        self.assertIn(message, result.stdout)

    def test_unchanged_ordinary_assertions_are_clean(self):
        self.baseline({"tests/value.test.cjs": "const assert = require('node:assert/strict');\nassert.equal(actual, expected);\n"})
        self.assert_clean()

    def test_removing_assertion_cannot_hide_a_native_failure(self):
        self.assertIsNotNone(shutil.which("node"), "native Node is required for the negative control")
        setup = "const assert = require('node:assert/strict');\nconst actual = 2;\n"
        self.baseline({"tests/value.test.cjs": setup + "assert.equal(actual, 1);\n"})
        original = self.run_command("node", "tests/value.test.cjs", check=False)
        self.assertNotEqual(original.returncode, 0)
        self.assertIn("ERR_ASSERTION", original.stdout)
        self.assert_clean()
        self.write("tests/value.test.cjs", setup)
        self.assertEqual(self.run_command("node", "tests/value.test.cjs").returncode, 0)
        self.assert_refused("assertion count decreased")

    def test_partial_ordinary_assertion_removal_is_refused(self):
        self.baseline({"src/value.test.ts": "expect(actual).toBe(1);\nexpect(other).toBe(2);\n"})
        self.write("src/value.test.ts", "expect(actual).toBe(1);\n")
        self.assert_refused("assertion count decreased")

    def test_protected_assertions_are_checked_before_first_pass(self):
        self.baseline({"e2e/finish/J-001.spec.ts": "expect(actual).toBe(1);\nexpect(other).toBe(2);\n"})
        self.write("e2e/finish/J-001.spec.ts", "expect(actual).toBe(1);\n")
        self.assert_refused("assertion count decreased")

    def test_same_count_assertion_edit_is_not_claimed_as_semantic_proof(self):
        self.baseline({"src/value.test.ts": "expect(actual).toBe(expected);\n"})
        self.write("src/value.test.ts", "expect(actual).toEqual(expected);\n")
        self.assert_clean()

    def test_renamed_test_with_preserved_assertions_is_clean(self):
        self.baseline({"tests/value.test.ts": "expect(actual).toBe(1);\nexpect(other).toBe(2);\n"})
        self.run_command("git", "mv", "tests/value.test.ts", "tests/renamed.test.ts")
        self.assert_clean()

    def test_renamed_test_with_fewer_assertions_is_refused(self):
        content = "const actual = result();\n" + "// unchanged source context\n" * 16
        self.baseline({"tests/value.test.ts": content + "expect(actual).toBe(1);\nexpect(other).toBe(2);\n"})
        self.run_command("git", "mv", "tests/value.test.ts", "tests/renamed.test.ts")
        self.write("tests/renamed.test.ts", content + "expect(actual).toBe(1);\n")
        self.assert_refused("assertion count decreased")

    def test_unstaged_protected_move_cannot_hide_a_native_failure(self):
        setup = "const assert = require('node:assert/strict');\nconst actual = 2;\n"
        old = "e2e/finish/original.spec.cjs"
        new = "e2e/finish/moved/original.spec.cjs"
        self.baseline({old: setup + "assert.equal(actual, 1);\nassert.equal(actual, 2);\n"})
        red = self.run_command("node", old, check=False)
        self.assertNotEqual(red.returncode, 0)
        self.assertIn("ERR_ASSERTION", red.stdout)
        self.write(new, setup + "assert.equal(actual, 2);\n")
        (self.root / old).unlink()
        self.assertEqual(self.run_command("node", new).returncode, 0)
        self.assert_refused("protected test deleted")

    def test_protected_move_requires_a_real_git_rename(self):
        old = "e2e/finish/original.spec.ts"
        new = "e2e/finish/moved/original.spec.ts"
        content = "expect(actual).toBe(expected);\n"
        self.baseline({old: content})
        self.write(new, content)
        (self.root / old).unlink()
        self.assert_refused("protected test deleted")
        self.run_command("git", "add", old, new)
        self.assert_clean()

    def test_vitest_include_narrowing_is_refused(self):
        self.baseline({"vitest.config.ts": "export default { test: { include: ['src/**/*.test.ts'] } };\n"})
        self.write("vitest.config.ts", "export default { test: { include: ['src/safe.test.ts'] } };\n")
        self.assert_refused("test or coverage config rule changed")

    def test_multiline_quoted_include_narrowing_is_refused(self):
        self.baseline({"vitest.config.ts": "export default { test: {\n  'include': [\n    'src/**/*.test.ts',\n  ],\n} };\n"})
        self.write("vitest.config.ts", "export default { test: {\n  'include': [\n    'src/safe.test.ts',\n  ],\n} };\n")
        self.assert_refused("test or coverage config rule changed")

    def test_existing_exclude_guard_still_refuses(self):
        self.baseline({"vitest.config.ts": "export default { test: { exclude: [] } };\n"})
        self.write("vitest.config.ts", "export default { test: { exclude: ['src/unsafe.test.ts'] } };\n")
        self.assert_refused("test or coverage config rule changed")

    def test_unchanged_include_is_clean(self):
        self.baseline({"vitest.config.ts": "export default { test: { include: ['src/**/*.test.ts'] } };\n"})
        self.assert_clean()

    def test_other_edit_in_config_with_include_requires_review(self):
        self.baseline({"vitest.config.ts": "export default { test: { include: ['src/**/*.test.ts'] }, name: 'before' };\n"})
        self.write("vitest.config.ts", "export default { test: { include: ['src/**/*.test.ts'] }, name: 'after' };\n")
        self.assert_refused("config containing include changed (review required)")

    def test_unrelated_config_without_include_does_not_trigger_include_guard(self):
        self.baseline({"vitest.config.ts": "export default { name: 'before' };\n"})
        self.write("vitest.config.ts", "export default { name: 'after' };\n")
        self.assert_clean()


if __name__ == "__main__":
    unittest.main()
