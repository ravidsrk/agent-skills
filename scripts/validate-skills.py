#!/usr/bin/env python3
"""
Validates every SKILL.md against the agentskills.io specification.
Spec: https://agentskills.io/specification

Rules enforced:
- name: 1-64 chars, lowercase letters/digits/hyphens, no leading/trailing hyphen,
  no consecutive --, must match folder name
- description: 1-1024 chars
- compatibility: optional, 1-500 chars

Exit code: 0 if all valid, 1 if any failures.
"""
import re
import sys
from pathlib import Path

SKILLS_DIR = Path(__file__).resolve().parent.parent / "skills"
NAME_RE = re.compile(r"^[a-z0-9]+(-[a-z0-9]+)*$")


def parse_frontmatter(text):
    if not text.startswith("---"):
        return None, "missing opening ---"
    end = text.find("\n---", 4)
    if end == -1:
        return None, "missing closing ---"
    block = text[3:end].strip()
    data = {}
    current_key = None
    multiline_indicator = None
    multiline_value = []
    for line in block.split("\n"):
        if multiline_indicator and (line.startswith("  ") or line.strip() == ""):
            multiline_value.append(line[2:] if line.startswith("  ") else line)
            continue
        else:
            if multiline_indicator:
                data[current_key] = " ".join(l.strip() for l in multiline_value if l.strip())
                multiline_indicator = None
                multiline_value = []

        m = re.match(r"^([a-zA-Z_-]+):\s*(.*)$", line)
        if m:
            key, val = m.group(1), m.group(2).strip()
            if val in (">", "|", ">-", "|-"):
                current_key = key
                multiline_indicator = val
                multiline_value = []
            elif val.startswith('"') and val.endswith('"'):
                data[key] = val[1:-1]
            elif val.startswith("'") and val.endswith("'"):
                data[key] = val[1:-1]
            elif val == "":
                current_key = key
                data[key] = "<object>"
            else:
                data[key] = val

    if multiline_indicator:
        data[current_key] = " ".join(l.strip() for l in multiline_value if l.strip())

    return data, None


def validate_skill(skill_dir):
    errors = []
    name = skill_dir.name
    skill_md = skill_dir / "SKILL.md"

    if not skill_md.exists():
        return [f"missing SKILL.md"]

    text = skill_md.read_text(encoding="utf-8")
    data, err = parse_frontmatter(text)
    if err:
        return [f"frontmatter parse error: {err}"]

    if "name" not in data:
        errors.append("missing 'name' field")
    else:
        n = data["name"]
        if not (1 <= len(n) <= 64):
            errors.append(f"name length {len(n)} out of 1-64")
        if not NAME_RE.match(n):
            errors.append(f"name '{n}' invalid (lowercase letters/digits/hyphens only)")
        if n != name:
            errors.append(f"name '{n}' does not match folder '{name}'")

    if "description" not in data:
        errors.append("missing 'description' field")
    else:
        d = data["description"]
        if not (1 <= len(d) <= 1024):
            errors.append(f"description length {len(d)} out of 1-1024")

    if "compatibility" in data:
        c = data["compatibility"]
        if c == "<object>":
            # spec requires a plain string; a nested mapping is invalid frontmatter
            errors.append("compatibility must be a string (1-500 chars), got a mapping")
        elif not (1 <= len(c) <= 500):
            errors.append(f"compatibility length {len(c)} out of 1-500")

    return errors


def main():
    if not SKILLS_DIR.exists():
        print(f"❌ skills/ not found at {SKILLS_DIR}", file=sys.stderr)
        return 2

    all_passed = True
    total = 0
    for skill_dir in sorted(SKILLS_DIR.iterdir()):
        if not skill_dir.is_dir() or skill_dir.name.startswith((".", "_")):
            continue
        total += 1
        errors = validate_skill(skill_dir)
        if errors:
            all_passed = False
            print(f"❌ {skill_dir.name}")
            for e in errors:
                print(f"   - {e}")
        else:
            print(f"✅ {skill_dir.name}")

    print()
    if all_passed:
        print(f"🟢 All {total} skills valid against agentskills.io spec.")
        return 0
    else:
        print(f"🔴 Validation failed.")
        return 1


if __name__ == "__main__":
    sys.exit(main())
