#!/usr/bin/env python3
"""Resolve every conflict block in the given files by keeping both sides: ours, then theirs.

For append-only files (indexes, lists, logs) where both branches added entries. Understands merge-style and
diff3-style markers; a diff3 base section (`||||||| ...` up to `=======`) is dropped. Exits 1 if any marker is
left afterwards, so a half-resolved file is never committed.

Usage: union.py FILE...
"""
import re
import sys

BLOCK = re.compile(
    r"^<<<<<<< [^\n]*\n(.*?)(?:^\|\|\|\|\|\|\| [^\n]*\n.*?)?^=======\n(.*?)^>>>>>>> [^\n]*\n",
    re.S | re.M,
)
MARKER = re.compile(r"^(<<<<<<< |\|\|\|\|\|\|\| |=======$|>>>>>>> )", re.M)


def main(paths):
    status = 0
    for path in paths:
        with open(path, encoding="utf-8") as f:
            text = f.read()
        count = len(BLOCK.findall(text))
        text = BLOCK.sub(lambda m: m.group(1) + m.group(2), text)
        left = MARKER.search(text)
        if left:
            print(f"{path}: {count} resolved, marker left at offset {left.start()}", file=sys.stderr)
            status = 1
            continue
        with open(path, "w", encoding="utf-8") as f:
            f.write(text)
        print(f"{path}: {count} resolved")
    return status


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] in ("-h", "--help"):
        print(__doc__.strip())
        sys.exit(0)
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    sys.exit(main(sys.argv[1:]))
