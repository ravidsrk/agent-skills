#!/usr/bin/env python3
"""
Validates every SKILL.md against the agentskills.io specification.
Spec: https://agentskills.io/specification

Rules enforced (hard failures — non-zero exit):
- name: 1-64 chars, lowercase letters/digits/hyphens, no leading/trailing hyphen,
  no consecutive --, must match folder name
- description: 1-1024 chars
- compatibility: optional, 1-500 chars
- README.md must exist alongside SKILL.md (skill-anatomy spec)
- Any explicit relative reference of the form (scripts|references|templates|assets)/<path>
  inside SKILL.md must resolve to a file on disk

Warnings (do NOT fail the run):
- description missing "when"-flavored trigger phrasing (heuristic — contains
  "use when" / "when the user" / "trigger" / "when you")

Frontmatter parsing prefers PyYAML when installed (`import yaml`); falls back
to a hand-rolled regex parser when PyYAML is unavailable so the script has no
hard dependency.

Exit code: 0 if all valid, 1 if any hard failures, 2 if skills/ is missing.
"""
import re
import sys
from pathlib import Path

try:
    import yaml  # type: ignore
    HAVE_YAML = True
except Exception:
    HAVE_YAML = False

SKILLS_DIR = Path(__file__).resolve().parent.parent / "skills"
NAME_RE = re.compile(r"^[a-z0-9]+(-[a-z0-9]+)*$")

# We only enforce dangling-reference checks on paths that appear inside a
# STRONG-reference form:
#   1. inline code:      `scripts/foo.py`
#   2. markdown link:    [label](references/bar.md)
# Prose paths, wildcard placeholders (`cluster-X-*.md`), and hypothetical
# example paths (`your-spec.yaml`) are NOT wrapped this way, so they don't
# trip the check. Every backtick/markdown-link ref in every current SKILL.md
# has been verified to resolve; new dangling refs will fail CI.
BACKTICK_REF_RE = re.compile(
    r"`((?:scripts|references|templates|assets)/[A-Za-z0-9._/-]+)`"
)
MDLINK_REF_RE = re.compile(
    r"\]\(((?:scripts|references|templates|assets)/[A-Za-z0-9._/-]+)\)"
)


def parse_frontmatter_yaml(text):
    """Parse `--- ... ---` frontmatter using PyYAML."""
    if not text.startswith("---"):
        return None, "missing opening ---"
    end = text.find("\n---", 4)
    if end == -1:
        return None, "missing closing ---"
    block = text[3:end]
    try:
        data = yaml.safe_load(block)
    except yaml.YAMLError as exc:
        return None, f"YAML parse error: {exc}"
    if data is None:
        return {}, None
    if not isinstance(data, dict):
        return None, "frontmatter is not a YAML mapping"
    normalized = {}
    for k, v in data.items():
        if isinstance(v, (dict, list)):
            normalized[str(k)] = "<object>"
        elif v is None:
            normalized[str(k)] = ""
        else:
            normalized[str(k)] = str(v)
    return normalized, None


def parse_frontmatter_regex(text):
    """Fallback parser used when PyYAML is not installed.

    Handles the shape used by every SKILL.md in this repo: top-level
    `key: value` pairs, quoted strings, and folded (`>-`, `|`) block
    scalars indented by two spaces. Nested keys under a bare parent
    (e.g. `metadata:`) are recorded as "<object>" — same convention as
    the YAML path.
    """
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
                data[current_key] = " ".join(
                    l.strip() for l in multiline_value if l.strip()
                )
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


def parse_frontmatter(text):
    """Prefer PyYAML; fall back to the regex parser if PyYAML isn't installed
    OR if the frontmatter isn't strict YAML (e.g. unquoted values containing
    colons). The regex parser is intentionally lenient about YAML edge cases
    the skills in this repo happen to use.
    """
    if HAVE_YAML:
        data, err = parse_frontmatter_yaml(text)
        if err is None:
            return data, None
        # Only fall back on YAML-parse errors — not on structural errors like
        # "missing opening/closing ---".
        if err.startswith("YAML parse error") or err.startswith("frontmatter is not"):
            return parse_frontmatter_regex(text)
        return None, err
    return parse_frontmatter_regex(text)


WHEN_HEURISTIC = re.compile(
    r"\buse when\b|\buse whenever\b|\bwhen the user\b|\bwhen you\b|\btrigger\b|\bactivate\b",
    re.IGNORECASE,
)


def strip_trailing_punct(s: str) -> str:
    # Strip trailing punctuation commonly attached to inline references
    # like `scripts/foo.py.` or `assets/x.jpg,`.
    return s.rstrip(",.;:)]}!?\"'`>")


def collect_references(text: str):
    """Yield relative paths (scripts|references|templates|assets)/... that
    appear inside a strong-reference form (inline backticks or a markdown link).
    """
    for regex in (BACKTICK_REF_RE, MDLINK_REF_RE):
        for m in regex.finditer(text):
            cleaned = strip_trailing_punct(m.group(1))
            parts = cleaned.split("/", 1)
            # Bare-directory refs like `scripts/` are valid if the dir exists —
            # we just need to be able to resolve them, so keep the empty tail.
            if not parts[0]:
                continue
            yield cleaned


def validate_skill(skill_dir):
    errors = []
    warnings = []
    name = skill_dir.name
    skill_md = skill_dir / "SKILL.md"

    if not skill_md.exists():
        return ["missing SKILL.md"], []

    text = skill_md.read_text(encoding="utf-8")
    data, err = parse_frontmatter(text)
    if err:
        return [f"frontmatter parse error: {err}"], []

    # name
    if "name" not in data:
        errors.append("missing 'name' field")
    else:
        n = data["name"]
        if not (1 <= len(n) <= 64):
            errors.append(f"name length {len(n)} out of 1-64")
        if not NAME_RE.match(n):
            errors.append(
                f"name '{n}' invalid (lowercase letters/digits/hyphens only)"
            )
        if n != name:
            errors.append(f"name '{n}' does not match folder '{name}'")

    # description
    if "description" not in data:
        errors.append("missing 'description' field")
    else:
        d = data["description"]
        if not (1 <= len(d) <= 1024):
            errors.append(f"description length {len(d)} out of 1-1024")
        elif not WHEN_HEURISTIC.search(d):
            warnings.append(
                "description lacks 'use when' / 'when the user' / 'trigger' phrasing "
                "— the spec asks for what + WHEN"
            )

    # compatibility (optional)
    if "compatibility" in data:
        c = data["compatibility"]
        if c != "<object>" and not (1 <= len(c) <= 500):
            errors.append(f"compatibility length {len(c)} out of 1-500")

    # README.md is required per skill-anatomy.md
    if not (skill_dir / "README.md").exists():
        errors.append("missing README.md (required per docs/skill-anatomy.md)")

    # Dangling reference check
    seen = set()
    for cleaned in collect_references(text):
        if cleaned in seen:
            continue
        seen.add(cleaned)
        target = skill_dir / cleaned
        if not target.exists():
            errors.append(
                f"dangling reference in SKILL.md: '{cleaned}' does not exist"
            )

    return errors, warnings


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
        errors, warnings = validate_skill(skill_dir)
        if errors:
            all_passed = False
            print(f"❌ {skill_dir.name}")
            for e in errors:
                print(f"   - {e}")
        else:
            print(f"✅ {skill_dir.name}")
        for w in warnings:
            print(f"   ⚠️  warning: {w}")

    print()
    if not HAVE_YAML:
        print("ℹ️  PyYAML not installed — used regex fallback parser. "
              "Install `pyyaml` for strict YAML validation.")
    if all_passed:
        print(f"🟢 All {total} skills valid against agentskills.io spec.")
        return 0
    else:
        print(f"🔴 Validation failed.")
        return 1


if __name__ == "__main__":
    sys.exit(main())
