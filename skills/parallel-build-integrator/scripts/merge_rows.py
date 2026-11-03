#!/usr/bin/env python3
"""Resolve diff3 conflict blocks in a markdown table, row by row.

A row's key is its first cell (`| #42 E3.5 Bitbucket | ...` -> `#42 E3.5 Bitbucket`; a leading `#N` alone is used
when present, so a retitled row keeps its key). For each key in a conflict block:
  - both sides equal          -> take it
  - ours unchanged from base  -> take theirs
  - theirs unchanged from base -> take ours
  - both changed              -> unresolved: markers stay, exit 1
A key that appears in the conflict block and also elsewhere in the file (a row one side moved) is reported as a
duplicate, exit 1. Non-table lines inside a block are kept from both sides, ours first.

The file must hold diff3 markers: run `git checkout --conflict=diff3 FILE` first.

Usage: merge_rows.py FILE
"""
import re
import sys

ISSUE = re.compile(r"^\|\s*(#\d+)\b")
CELL = re.compile(r"^\|([^|]*)\|")


def key(line):
    m = ISSUE.match(line)
    if m:
        return m.group(1)
    m = CELL.match(line)
    return m.group(1).strip() if m else None


def main(path):
    with open(path, encoding="utf-8") as f:
        lines = f.read().split("\n")
    out, unresolved, conflict_keys = [], [], []
    i = 0
    while i < len(lines):
        if not lines[i].startswith("<<<<<<< "):
            out.append(lines[i])
            i += 1
            continue
        ours, base, theirs = [], [], []
        i += 1
        while not lines[i].startswith(("||||||| ", "=======")):
            ours.append(lines[i])
            i += 1
        if not lines[i].startswith("||||||| "):
            sys.exit(f"{path}: not diff3 markers; run `git checkout --conflict=diff3 {path}` first")
        i += 1
        while lines[i] != "=======":
            base.append(lines[i])
            i += 1
        i += 1
        while not lines[i].startswith(">>>>>>> "):
            theirs.append(lines[i])
            i += 1
        i += 1
        b = {key(x): x for x in base if key(x)}
        o = {key(x): x for x in ours if key(x)}
        t = {key(x): x for x in theirs if key(x)}
        # One pass over ours then theirs: each row key resolved where it first appears, other lines kept once.
        seen_keys, seen_text = set(), set()
        for x in ours + theirs:
            k = key(x)
            if k is None:
                if x not in seen_text:
                    seen_text.add(x)
                    out.append(x)
                continue
            if k in seen_keys:
                continue
            seen_keys.add(k)
            conflict_keys.append(k)
            ov, bv, tv = o.get(k), b.get(k), t.get(k)
            if ov == tv:
                res = ov
            elif ov == bv:
                res = tv
            elif tv == bv:
                res = ov
            else:
                unresolved.append(k)
                out += ["<<<<<<< ours", ov or "", "=======", tv or "", ">>>>>>> theirs"]
                continue
            if res is not None:
                out.append(res)
    counts = {}
    for line in out:
        k = key(line)
        if k:
            counts[k] = counts.get(k, 0) + 1
    duplicates = sorted({k for k in conflict_keys if counts.get(k, 0) > 1 and k not in unresolved})
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(out))
    if unresolved or duplicates:
        print(f"{path}: unresolved {unresolved}; duplicate keys {duplicates}", file=sys.stderr)
        return 1
    print(f"{path}: resolved {len(conflict_keys)} rows")
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    sys.exit(main(sys.argv[1]))
