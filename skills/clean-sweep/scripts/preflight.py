#!/usr/bin/env python3
"""preflight.py — hard preflight checks for a clean-sweep run.

Verifies the invariants that, if wrong, silently corrupt a whole run:
    1. `git` and `gh` are on PATH.
    2. The current directory is a git repo with a working `gh` remote.
    3. The integration BASE branch is NOT the default branch (M-5 guardrail — every
       per-finding PR merges into BASE, so `BASE == default` sends fixes straight to
       production, bypassing the anti-inflation gate and the human promotion review).
    4. BASE exists (locally or on origin).
    5. BASE was forked from the run's fork-point (a commit reachable from BASE that is
       also reachable from the default branch); rejects a BASE that was created off an
       unrelated history.
    6. If `--require-gitleaks` is passed (integrator will scan diffs), `gitleaks` must be
       on PATH; otherwise a soft warning is fine.

Usage:
    preflight.py --base <base-branch> [--default <default-branch>] [--require-gitleaks]
    # exit 0 = OK; exit 1 = usage/dependency; exit 2 = invariant violation

Wire it in at Phase 0 of the run (SKILL.md) and inside the integrator preamble before the
first `gh pr create` so a mid-run drift is caught, not tolerated.
"""
from __future__ import annotations

import argparse
import shutil
import subprocess
import sys


def _run(cmd: list[str]) -> tuple[int, str, str]:
    proc = subprocess.run(cmd, capture_output=True, text=True)
    return proc.returncode, proc.stdout.strip(), proc.stderr.strip()


def _which(name: str) -> bool:
    return shutil.which(name) is not None


def _default_branch_via_gh() -> str | None:
    rc, out, _ = _run(["gh", "repo", "view", "--json", "defaultBranchRef", "-q", ".defaultBranchRef.name"])
    return out if rc == 0 and out else None


def _branch_exists(ref: str) -> bool:
    rc, _, _ = _run(["git", "rev-parse", "--verify", "--quiet", ref])
    if rc == 0:
        return True
    rc, _, _ = _run(["git", "rev-parse", "--verify", "--quiet", f"origin/{ref}"])
    return rc == 0


def _merge_base(a: str, b: str) -> str | None:
    for pair in ((a, b), (f"origin/{a}", f"origin/{b}"), (a, f"origin/{b}"), (f"origin/{a}", b)):
        rc, out, _ = _run(["git", "merge-base", *pair])
        if rc == 0 and out:
            return out
    return None


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(prog="preflight.py")
    parser.add_argument("--base", required=True, help="The integration BASE branch name.")
    parser.add_argument("--default", help="Default branch (auto-derived via `gh` if omitted).")
    parser.add_argument(
        "--require-gitleaks",
        action="store_true",
        help="Fail if `gitleaks` isn't on PATH (the integrator will run a scoped secret scan).",
    )
    args = parser.parse_args(argv)

    errors: list[str] = []
    warnings: list[str] = []

    # 1. Required binaries.
    for binary in ("git", "gh"):
        if not _which(binary):
            errors.append(f"missing required binary on PATH: {binary}")
    if args.require_gitleaks and not _which("gitleaks"):
        errors.append("missing required binary on PATH: gitleaks (--require-gitleaks was set)")
    elif not _which("gitleaks"):
        warnings.append("gitleaks not on PATH — integrator secret scan step will be skipped")

    if errors:
        for e in errors:
            print(f"preflight: ERROR: {e}", file=sys.stderr)
        return 1

    # 2. In a git repo, with a gh-visible remote.
    rc, _, _ = _run(["git", "rev-parse", "--git-dir"])
    if rc != 0:
        print("preflight: ERROR: not inside a git repository", file=sys.stderr)
        return 1

    rc, repo, gh_err = _run(["gh", "repo", "view", "--json", "nameWithOwner", "-q", ".nameWithOwner"])
    if rc != 0 or not repo:
        print(f"preflight: ERROR: `gh repo view` failed: {gh_err or 'no output'}", file=sys.stderr)
        return 1

    # 3. Derive default branch if not given.
    default_branch = args.default or _default_branch_via_gh()
    if not default_branch:
        print("preflight: ERROR: could not derive default branch (pass --default)", file=sys.stderr)
        return 2

    # 4. BASE != DEFAULT_BRANCH (the M-5 guardrail).
    if args.base == default_branch:
        print(
            f"preflight: ERROR: BASE ({args.base!r}) equals DEFAULT_BRANCH ({default_branch!r}). "
            "Every per-finding PR is merged into BASE; if BASE is the default branch, fixes land "
            "straight on production and bypass both the anti-inflation gate and the human "
            "promotion review. Create a dedicated integration branch (e.g. `<maintainer>/clean-sweep`) "
            "off the current run's fork point and rerun.",
            file=sys.stderr,
        )
        return 2

    # 5. BASE exists.
    if not _branch_exists(args.base):
        print(
            f"preflight: ERROR: BASE branch {args.base!r} does not exist locally or on origin.",
            file=sys.stderr,
        )
        return 2

    # 6. BASE forks from a commit reachable from DEFAULT_BRANCH (guards against a BASE
    #    created off an unrelated history — e.g. a stale branch someone accidentally reused).
    mb = _merge_base(args.base, default_branch)
    if not mb:
        print(
            f"preflight: ERROR: no merge-base between {args.base!r} and {default_branch!r}; "
            "BASE does not appear to fork from the default branch's history.",
            file=sys.stderr,
        )
        return 2

    if warnings:
        for w in warnings:
            print(f"preflight: WARN: {w}", file=sys.stderr)

    print(
        f"preflight: OK — repo={repo}, base={args.base}, default={default_branch}, "
        f"fork_point={mb[:12]}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
