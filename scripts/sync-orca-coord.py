#!/usr/bin/env python3
"""sync-orca-coord.py — regenerate vendored copies of the shared Orca coordinator helpers.

`scripts/orca-coord/` is the single source of truth (Codex review E2 remediation:
96 hand-copied helpers had already drifted, with no propagation path for fixes).
Every skill listed in `scripts/orca-coord/MANIFEST` gets GENERATED copies of all
helpers (plus the README) under `skills/<name>/scripts/`, each stamped with a
do-not-edit header pointing back here.

The MANIFEST is the committed inventory: `--check` fails on a drifted copy, a
MISSING copy (deletion is drift too), a lost executable bit, or a skill that
vendors helpers without being in the MANIFEST. Adding or removing a
participating skill is a deliberate MANIFEST edit.

Usage:
    python3 scripts/sync-orca-coord.py            # rewrite every vendored copy
    python3 scripts/sync-orca-coord.py --check    # verify, write nothing (CI)

`scripts/validate-skills.py` runs `--check` automatically.
"""
from __future__ import annotations

import argparse
import os
import stat
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
CANONICAL = REPO / "scripts" / "orca-coord"
MANIFEST = CANONICAL / "MANIFEST"
SKILLS = REPO / "skills"
HELPERS = ("spawn_worker.sh", "preflight.py", "pm.py", "README.md")


def generated_content(name: str) -> str:
    """Canonical text with a DO-NOT-EDIT header (after the shebang for scripts)."""
    text = (CANONICAL / name).read_text(encoding="utf-8")
    if name.endswith(".md"):
        header = (
            f"<!-- GENERATED FROM scripts/orca-coord/{name} — DO NOT EDIT THIS COPY.\n"
            f"     Edit the canonical file, then run: python3 scripts/sync-orca-coord.py -->\n"
        )
        return header + text
    header = (
        f"# GENERATED FROM scripts/orca-coord/{name} — DO NOT EDIT THIS COPY.\n"
        f"# Edit the canonical file, then run: python3 scripts/sync-orca-coord.py\n"
    )
    lines = text.splitlines(keepends=True)
    if lines and lines[0].startswith("#!"):
        return lines[0] + header + "".join(lines[1:])
    return header + text


def manifest_skills() -> list[str]:
    if not MANIFEST.exists():
        print(f"sync-orca-coord: ERROR: missing {MANIFEST.relative_to(REPO)}", file=sys.stderr)
        sys.exit(1)
    return [
        line.strip()
        for line in MANIFEST.read_text(encoding="utf-8").splitlines()
        if line.strip() and not line.startswith("#")
    ]


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(prog="sync-orca-coord.py")
    parser.add_argument("--check", action="store_true", help="verify copies, write nothing")
    args = parser.parse_args(argv)

    skills = manifest_skills()
    problems: list[str] = []
    written = 0
    total = 0

    for name in HELPERS:
        expected = generated_content(name)
        for skill in skills:
            copy = SKILLS / skill / "scripts" / name
            total += 1
            exists = copy.exists()
            current = copy.read_text(encoding="utf-8") if exists else None
            content_ok = current == expected
            exec_ok = (not name.endswith(".sh")) or (exists and os.access(copy, os.X_OK))
            if content_ok and exec_ok:
                continue
            if args.check:
                if not exists:
                    problems.append(f"MISSING  {copy.relative_to(REPO)}")
                elif not content_ok:
                    problems.append(f"DRIFTED  {copy.relative_to(REPO)}")
                else:
                    problems.append(f"NOT-EXEC {copy.relative_to(REPO)}")
            else:
                copy.parent.mkdir(parents=True, exist_ok=True)
                copy.write_text(expected, encoding="utf-8")
                if name.endswith(".sh"):
                    copy.chmod(copy.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
                written += 1

    # Skills vendoring helpers without being in the MANIFEST are drift too.
    listed = set(skills)
    for helper in HELPERS:
        for copy in SKILLS.glob(f"*/scripts/{helper}"):
            skill = copy.parent.parent.name
            if skill not in listed:
                problems.append(f"UNLISTED {copy.relative_to(REPO)} (add {skill!r} to MANIFEST or remove the copy)")

    if args.check:
        if problems:
            print(f"sync-orca-coord: {len(problems)} problem(s) across {total} expected copies:", file=sys.stderr)
            for p in problems:
                print(f"  - {p}", file=sys.stderr)
            print("  fix: python3 scripts/sync-orca-coord.py (or edit MANIFEST deliberately)", file=sys.stderr)
            return 1
        print(f"sync-orca-coord: OK — {total} vendored copies match canonical ({len(skills)} skills × {len(HELPERS)} files)")
        return 0

    print(f"sync-orca-coord: wrote {written}/{total} vendored copies from scripts/orca-coord/")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
