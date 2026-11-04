#!/usr/bin/env python3
"""
Checks that every relative link in the repo's Markdown files points at a file that exists.

Covers Markdown links and images (`[text](path)`, `![alt](path)`) and HTML `src="..."` /
`href="..."` attributes. Links inside fenced code blocks and inline code spans are ignored
(they are examples, not references), as are absolute URLs, mailto: links and bare anchors.

Exit code: 0 if every link resolves, 1 if any is broken.
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FENCE = re.compile(r"^(```|~~~)[^\n]*\n.*?^\1[ \t]*$", re.S | re.M)
INLINE_CODE = re.compile(r"`[^`\n]*`")
MD_LINK = re.compile(r"!?\[[^\]]*\]\(([^)\s]+)(?:\s+\"[^\"]*\")?\)")
HTML_ATTR = re.compile(r"\b(?:src|href)=\"([^\"]+)\"")
SKIP = re.compile(r"^(https?:|mailto:|#|data:)")


def targets(text):
    text = FENCE.sub("", text)
    text = INLINE_CODE.sub("", text)
    for m in MD_LINK.finditer(text):
        yield m.group(1)
    for m in HTML_ATTR.finditer(text):
        yield m.group(1)


def main():
    files = sorted(p for p in ROOT.rglob("*.md") if ".git" not in p.parts)
    broken = []
    for md in files:
        text = md.read_text(encoding="utf-8", errors="replace")
        for raw in targets(text):
            if SKIP.match(raw):
                continue
            target = raw.split("#", 1)[0]
            if target and not (md.parent / target).exists():
                broken.append((md.relative_to(ROOT), raw))
    for md, raw in broken:
        print(f"❌ {md}: {raw}")
    if broken:
        print(f"\n🔴 {len(broken)} broken link(s) across {len(files)} Markdown files.")
        return 1
    print(f"🟢 All relative links resolve across {len(files)} Markdown files.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
