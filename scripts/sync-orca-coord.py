#!/usr/bin/env python3
"""sync-orca-coord.py — regenerate vendored copies of the shared Orca coordinator helpers.

`scripts/orca-coord/` is the single source of truth (Codex review E2 remediation:
96 hand-copied helpers had already drifted, with no propagation path for fixes).
Every skill that vendors a helper under `skills/<name>/scripts/` gets a GENERATED
copy stamped with a do-not-edit header pointing back here.

Usage:
    python3 scripts/sync-orca-coord.py            # rewrite every vendored copy
    python3 scripts/sync-orca-coord.py --check    # exit 1 if any copy drifted (CI)

`scripts/validate-skills.py` runs `--check` automatically.
"""
from __future__ import annotations

import argparse
import stat
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
CANONICAL = REPO / "scripts" / "orca-coord"
SKILLS = REPO / "skills"
HELPERS = ("spawn_worker.sh", "preflight.py", "pm.py")


def generated_content(name: str) -> str:
    """Canonical text with a DO-NOT-EDIT header inserted after the shebang."""
    text = (CANONICAL / name).read_text(encoding="utf-8")
    lines = text.splitlines(keepends=True)
    header = (
        f"# GENERATED FROM scripts/orca-coord/{name} — DO NOT EDIT THIS COPY.\n"
        f"# Edit the canonical file, then run: python3 scripts/sync-orca-coord.py\n"
    )
    if lines and lines[0].startswith("#!"):
        return lines[0] + header + "".join(lines[1:])
    return header + text


def vendored_copies(name: str) -> list[Path]:
    return sorted(SKILLS.glob(f"*/scripts/{name}"))


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(prog="sync-orca-coord.py")
    parser.add_argument("--check", action="store_true", help="verify copies, write nothing")
    args = parser.parse_args(argv)

    drifted: list[Path] = []
    written = 0
    total = 0
    for name in HELPERS:
        expected = generated_content(name)
        for copy in vendored_copies(name):
            total += 1
            current = copy.read_text(encoding="utf-8") if copy.exists() else ""
            if current == expected:
                continue
            if args.check:
                drifted.append(copy)
            else:
                copy.write_text(expected, encoding="utf-8")
                if name.endswith(".sh"):
                    copy.chmod(copy.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
                written += 1

    if args.check:
        if drifted:
            print(f"sync-orca-coord: DRIFT in {len(drifted)}/{total} vendored copies:", file=sys.stderr)
            for p in drifted:
                print(f"  - {p.relative_to(REPO)}", file=sys.stderr)
            print("  fix: python3 scripts/sync-orca-coord.py", file=sys.stderr)
            return 1
        print(f"sync-orca-coord: OK — {total} vendored copies match canonical")
        return 0

    print(f"sync-orca-coord: wrote {written}/{total} vendored copies from scripts/orca-coord/")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
