#!/usr/bin/env python3
"""Audit a markdown knowledge base. Read-only.

Checks frontmatter, slug/path agreement, wikilinks, orphans, stale pages,
duplicate titles, and oversized pages. Exits non-zero when findings meet
the --fail-on threshold.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
from collections import Counter, defaultdict
from datetime import date, datetime, timedelta, timezone
from pathlib import Path

EXCLUDE_DIRS = {".git", "node_modules", ".obsidian", ".trash", "vendor", "dist", "build"}
FRONTMATTER_FIELDS = ("updated_at", "captured_at", "created_at", "published_at")
WIKILINK_RE = re.compile(r"\[\[([^\]|#]+)(?:[|#][^\]]*)?\]\]")
MDLINK_RE = re.compile(r"\[[^\]]*\]\(([^)\s]+)(?:\s+\"[^\"]*\")?\)")
H1_RE = re.compile(r"^#\s+(.+?)\s*$", re.MULTILINE)
FENCE_RE = re.compile(r"```.*?```", re.DOTALL)

SEVERITY = {
    "missing_frontmatter": "error",
    "empty_frontmatter": "error",
    "frontmatter_parse_error": "error",
    "missing_required_field": "error",
    "missing_title": "error",
    "slug_mismatch": "error",
    "broken_wikilink": "error",
    "broken_asset": "error",
    "missing_type": "warn",
    "invalid_date": "warn",
    "stale_page": "warn",
    "orphan_page": "warn",
    "duplicate_title": "warn",
    "oversized_page": "warn",
    "read_error": "error",
}

NEXT_ACTIONS = {
    "missing_frontmatter": "Add a valid frontmatter block (see references/frontmatter-schema.md).",
    "empty_frontmatter": "Fill the empty frontmatter from the page content.",
    "frontmatter_parse_error": "Fix the malformed YAML line named in the finding.",
    "missing_required_field": "Add the missing required field (title, type, slug, captured_at, content_hash).",
    "missing_title": "Add a frontmatter title or an H1.",
    "slug_mismatch": "Set the frontmatter slug to the path-derived slug, or update links before renaming.",
    "broken_wikilink": "Fix the target, create the missing page, or remove the link.",
    "broken_asset": "Restore the file, fix the relative path, or remove the link.",
    "missing_type": "Add a type from references/taxonomy.md.",
    "invalid_date": "Use a UTC date (`YYYY-MM-DD` or ISO-8601 with Z).",
    "stale_page": "Read the page and its timeline; rewrite, archive, or confirm it is historical.",
    "orphan_page": "Link it from an index/entity page, archive it, or delete it after confirmation.",
    "duplicate_title": "Pick a canonical page, merge, alias, and update inbound links.",
    "oversized_page": "Split by subject and keep a hub page.",
    "read_error": "Check file permissions and encoding, then re-run.",
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Audit a markdown knowledge base (read-only).",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            "Examples:\n"
            "  kb-audit.py --root ./brain\n"
            "  kb-audit.py --root ./brain --fail-on warn\n"
            "  kb-audit.py --root ./brain --json > audit.json\n"
        ),
    )
    parser.add_argument("--root", default=os.environ.get("KB_ROOT", "."), help="Knowledge base root (default: $KB_ROOT or .)")
    parser.add_argument("--stale-days", type=int, default=90, help="Flag pages older than N days (default: 90)")
    parser.add_argument("--max-lines", type=int, default=500, help="Flag pages longer than N lines (default: 500)")
    parser.add_argument("--json", action="store_true", help="Print JSON instead of Markdown")
    parser.add_argument("--fail-on", choices=("none", "warn", "error"), default="error", help="Exit 1 at this severity (default: error)")
    return parser.parse_args()


def find_closing_quote(value, quote):
    index = 1
    while index < len(value):
        char = value[index]
        if quote == '"' and char == "\\" and index + 1 < len(value):
            index += 2
            continue
        if char == quote:
            if quote == "'" and index + 1 < len(value) and value[index + 1] == "'":
                index += 2
                continue
            return index
        index += 1
    return -1


def find_closing_bracket(value):
    depth = 0
    quote = None
    item_start = True
    index = 0
    while index < len(value):
        char = value[index]
        if quote:
            if quote == '"' and char == "\\" and index + 1 < len(value):
                index += 2
                continue
            if char == quote:
                if quote == "'" and index + 1 < len(value) and value[index + 1] == "'":
                    index += 2
                    continue
                quote = None
                item_start = False
            index += 1
            continue
        if char in "\"'":
            if item_start:
                quote = char
            else:
                item_start = False
        elif char == "[":
            depth += 1
            item_start = True
        elif char == "]":
            depth -= 1
            if depth == 0:
                return index
            item_start = False
        elif char == ",":
            item_start = True
        elif char in " \t":
            pass
        else:
            item_start = False
        index += 1
    return -1


def strip_inline_comment(value):
    if not value:
        return value
    if value[0] in "\"'":
        end = find_closing_quote(value, value[0])
        return value[: end + 1] if end != -1 else value
    if value[0] == "[":
        end = find_closing_bracket(value)
        return value[: end + 1] if end != -1 else value
    index = value.find(" #")
    return value[:index].rstrip() if index != -1 else value


def parse_frontmatter(text: str):
    lines = text.splitlines()
    if not lines or lines[0].strip() != "---":
        return None, text, "missing_open", 0, None
    end = None
    for i in range(1, len(lines)):
        if lines[i].strip() == "---":
            end = i
            break
    if end is None:
        return None, text, "missing_close", 0, None
    data = {}
    current = None
    parse_error = None
    for raw in lines[1:end]:
        if not raw.strip() or raw.lstrip().startswith("#"):
            continue
        m = re.match(r"^([A-Za-z0-9_-]+):\s*(.*)$", raw)
        if m:
            key, value = m.group(1), strip_inline_comment(m.group(2).strip())
            if value in (">", "|", ">-", "|-"):
                current = key
                data[key] = ""
            elif value.startswith("["):
                bracket_end = find_closing_bracket(value)
                if bracket_end == -1:
                    parse_error = parse_error or f"unterminated array in '{key}'"
                    data[key] = value
                    current = key
                else:
                    inner = value[1:bracket_end]
                    data[key] = [item.strip().strip("'\"") for item in inner.split(",") if item.strip()]
                    current = None
            elif value and value[0] in "\"'":
                quote_end = find_closing_quote(value, value[0])
                if quote_end == -1:
                    parse_error = parse_error or f"unterminated quote in '{key}'"
                    data[key] = value[1:]
                else:
                    inner = value[1:quote_end]
                    if value[0] == '"':
                        inner = inner.replace('\\"', '"')
                    else:
                        inner = inner.replace("''", "'").replace("\\'", "'")
                    data[key] = inner
                current = key
            else:
                data[key] = value
                current = key
        elif current and (raw.startswith("  ") or raw.startswith("\t")):
            stripped = raw.strip()
            if stripped.startswith("- "):
                if not isinstance(data.get(current), list):
                    data[current] = []
                data[current].append(strip_inline_comment(stripped[2:].strip()).strip("'\""))
            else:
                data[current] = (str(data.get(current, "")) + " " + stripped).strip()
        else:
            parse_error = parse_error or f"unrecognized line: {raw[:60]}"
    body = "\n".join(lines[end + 1 :])
    if parse_error:
        return data, body, "parse_error", end + 1, parse_error
    if not data:
        return data, body, "empty", end + 1, None
    return data, body, "ok", end + 1, None


def parse_date(value):
    if not isinstance(value, str) or len(value) < 10:
        return None
    try:
        return datetime.strptime(value[:10], "%Y-%m-%d").date()
    except ValueError:
        return None


def strip_code(text: str) -> str:
    return FENCE_RE.sub("", text)


def extract_title(frontmatter, body):
    if frontmatter and isinstance(frontmatter.get("title"), str) and frontmatter["title"].strip():
        return frontmatter["title"].strip()
    match = H1_RE.search(body)
    return match.group(1).strip() if match else ""


def normalize_title(title: str) -> str:
    return re.sub(r"[^a-z0-9]+", " ", title.lower()).strip()


def rel_slug(path: Path, root: Path) -> str:
    rel = path.relative_to(root).as_posix()
    for suffix in (".mdx", ".md"):
        if rel.endswith(suffix):
            return rel[: -len(suffix)]
    return rel


def is_asset_target(raw):
    clean = raw.split("#", 1)[0].split("?", 1)[0]
    ext = os.path.splitext(clean)[1].lower()
    return bool(ext) and ext not in (".md", ".mdx")


def resolve_asset(raw, page, root):
    clean = raw.split("#", 1)[0].split("?", 1)[0]
    if not clean:
        return True
    candidate = (root / clean.lstrip("/")) if clean.startswith("/") else (page.parent / clean)
    try:
        return candidate.resolve().exists()
    except OSError:
        return False


def resolve_target(raw, page, root, slugs, titles, aliases):
    target = raw.strip()
    if not target or target.startswith(("#", "http://", "https://", "mailto:", "tel:", "//", "data:")):
        return None
    target = target.split("#", 1)[0].split("?", 1)[0]
    if not target:
        return None
    target = target.replace("\\", "/")
    for suffix in (".mdx", ".md"):
        if target.endswith(suffix):
            target = target[: -len(suffix)]
            break
    target = target.lstrip("./").strip("/")
    if target in slugs:
        return target
    if target in aliases:
        return aliases[target]
    if target.lower() in aliases:
        return aliases[target.lower()]
    normalized = normalize_title(target)
    if normalized in titles:
        return titles[normalized]
    basename_matches = [slug for slug in slugs if slug.rsplit("/", 1)[-1].lower() == target.lower()]
    if len(basename_matches) == 1:
        return basename_matches[0]
    if "/" in raw:
        try:
            candidate = (page.parent / raw.split("#", 1)[0]).resolve()
            candidate_slug = rel_slug(candidate, root.resolve())
            if candidate_slug in slugs:
                return candidate_slug
        except (ValueError, OSError):
            pass
    return None


def audit(root: Path, stale_days: int, max_lines: int) -> dict:
    pages = []
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = sorted(d for d in dirnames if d not in EXCLUDE_DIRS and not d.startswith("."))
        for filename in sorted(filenames):
            if filename.endswith((".md", ".mdx")):
                pages.append(Path(dirpath) / filename)

    findings = []
    slugs = {rel_slug(path, root) for path in pages}
    titles = {}
    aliases = {}
    inbound = Counter()
    records = []

    for path in pages:
        rel = path.relative_to(root).as_posix()
        try:
            text = path.read_text(encoding="utf-8", errors="replace")
        except OSError as exc:
            findings.append(
                {"code": "read_error", "severity": "error", "path": rel, "detail": str(exc)}
            )
            continue
        frontmatter, body, status, body_start, parse_error = parse_frontmatter(text)
        title = extract_title(frontmatter, body)
        slug = rel_slug(path, root)
        if title:
            titles.setdefault(normalize_title(title), slug)
        if frontmatter:
            alias_values = frontmatter.get("aliases")
            if isinstance(alias_values, str):
                alias_values = [alias_values]
            elif not isinstance(alias_values, list):
                alias_values = []
            for alias in alias_values:
                alias_key = str(alias).strip().strip("/")
                if alias_key:
                    aliases[alias_key] = slug
                    aliases[alias_key.lower()] = slug
        records.append(
            {
                "path": path,
                "rel": rel,
                "slug": slug,
                "frontmatter": frontmatter,
                "body": body,
                "status": status,
                "body_start": body_start,
                "title": title,
                "line_count": len(text.splitlines()),
            }
        )

        if status == "missing_open":
            findings.append({"code": "missing_frontmatter", "severity": "error", "path": rel, "detail": "no opening --- block"})
        elif status == "missing_close":
            findings.append({"code": "missing_frontmatter", "severity": "error", "path": rel, "detail": "no closing --- before the first heading"})
        elif status == "empty":
            findings.append({"code": "empty_frontmatter", "severity": "error", "path": rel, "detail": "frontmatter block is empty"})
        elif status == "parse_error":
            findings.append({"code": "frontmatter_parse_error", "severity": "error", "path": rel, "detail": parse_error or "malformed frontmatter"})

        if not title:
            findings.append({"code": "missing_title", "severity": "error", "path": rel, "detail": "no frontmatter title or H1"})
        if frontmatter is not None and status in ("ok", "parse_error"):
            for field in ("slug", "captured_at", "content_hash"):
                value = frontmatter.get(field)
                if value is None or (isinstance(value, str) and not value.strip()):
                    findings.append({"code": "missing_required_field", "severity": "error", "path": rel, "detail": f"missing required field '{field}'"})
        if frontmatter is not None and status in ("ok", "parse_error") and not str(frontmatter.get("type", "")).strip():
            findings.append({"code": "missing_type", "severity": "warn", "path": rel, "detail": "frontmatter has no type"})
        if frontmatter is not None and isinstance(frontmatter.get("slug"), str):
            declared = frontmatter["slug"].strip().strip("/")
            if declared and declared != slug:
                findings.append({"code": "slug_mismatch", "severity": "error", "path": rel, "detail": f"frontmatter slug '{declared}' != path slug '{slug}'"})

        dates = []
        if frontmatter:
            for field in FRONTMATTER_FIELDS:
                value = frontmatter.get(field)
                if value in (None, ""):
                    continue
                parsed = parse_date(value)
                if parsed is None:
                    findings.append({"code": "invalid_date", "severity": "warn", "path": rel, "detail": f"{field}='{value}' is not a YYYY-MM-DD date"})
                else:
                    dates.append(parsed)
        if dates:
            archived = rel.startswith("archive/") or str((frontmatter or {}).get("status", "")).lower() in ("archived", "archive")
            newest = max(dates)
            cutoff = datetime.now(timezone.utc).date() - timedelta(days=stale_days)
            if not archived and newest < cutoff:
                findings.append({"code": "stale_page", "severity": "warn", "path": rel, "detail": f"newest date {newest.isoformat()} is older than {stale_days} days"})

        if len(text.splitlines()) > max_lines:
            findings.append({"code": "oversized_page", "severity": "warn", "path": rel, "detail": f"{len(text.splitlines())} lines > {max_lines}"})

    for record in records:
        body = strip_code(record["body"])
        for regex in (WIKILINK_RE, MDLINK_RE):
            for match in regex.finditer(body):
                target = match.group(1)
                line = record["body_start"] + body[: match.start()].count("\n") + 1
                if regex is MDLINK_RE:
                    if target.startswith(("http://", "https://", "mailto:", "tel:", "//", "data:")):
                        continue
                    if is_asset_target(target):
                        if not resolve_asset(target, record["path"], root):
                            findings.append(
                                {
                                    "code": "broken_asset",
                                    "severity": "error",
                                    "path": record["rel"],
                                    "detail": f"line {line}: asset '{target}' does not exist",
                                }
                            )
                        continue
                if not target.strip() or target.startswith("#"):
                    continue
                resolved = resolve_target(target, record["path"], root, slugs, titles, aliases)
                if resolved is None:
                    findings.append(
                        {
                            "code": "broken_wikilink",
                            "severity": "error",
                            "path": record["rel"],
                            "detail": f"line {line}: target '{target}' does not resolve",
                        }
                    )
                elif resolved != record["slug"]:
                    inbound[resolved] += 1

    if len(records) >= 3:
        for record in records:
            rel = record["rel"]
            if rel.startswith(("inbox/", "archive/")) or rel.lower() in ("readme.md", "index.md"):
                continue
            if inbound[record["slug"]] == 0:
                findings.append({"code": "orphan_page", "severity": "warn", "path": rel, "detail": "no inbound links"})

    title_groups = defaultdict(list)
    for record in records:
        if record["title"]:
            title_groups[normalize_title(record["title"])].append(record["rel"])
    for normalized, paths in title_groups.items():
        if len(paths) > 1:
            detail = "duplicate title shared by: " + ", ".join(paths)
            for path in paths[1:]:
                findings.append({"code": "duplicate_title", "severity": "warn", "path": path, "detail": detail})

    counts = Counter(finding["code"] for finding in findings)
    errors = sum(1 for finding in findings if finding["severity"] == "error")
    warnings = sum(1 for finding in findings if finding["severity"] == "warn")
    return {
        "root": str(root),
        "generated_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "files": len(records),
        "findings": findings,
        "counts": dict(sorted(counts.items())),
        "summary": {"total": len(findings), "errors": errors, "warnings": warnings},
    }


def render_markdown(result: dict) -> str:
    lines = [
        f"# Knowledge Base Audit — {result['generated_at'][:10]}",
        "",
        f"Root: `{result['root']}`",
        f"Files: {result['files']}",
        f"Findings: {result['summary']['total']} ({result['summary']['errors']} errors, {result['summary']['warnings']} warnings)",
        "",
        "| Code | Severity | Count |",
        "|---|---|---:|",
    ]
    for code, count in sorted(result["counts"].items(), key=lambda item: (-item[1], item[0])):
        lines.append(f"| {code} | {SEVERITY.get(code, 'error')} | {count} |")
    if not result["counts"]:
        lines.append("| — | — | 0 |")

    for severity, heading in (("error", "Errors"), ("warn", "Warnings")):
        matching = [finding for finding in result["findings"] if finding["severity"] == severity]
        if not matching:
            continue
        lines.extend(["", f"## {heading}", ""])
        for finding in matching:
            lines.append(f"- `{finding['path']}` — {finding['code']}: {finding['detail']}")

    if result["findings"]:
        lines.extend(["", "## Next actions", ""])
        codes = sorted({finding["code"] for finding in result["findings"]})
        for index, code in enumerate(codes, 1):
            lines.append(f"{index}. {NEXT_ACTIONS.get(code, 'Review the finding.')}")
    else:
        lines.extend(["", "No findings. The base passes the current checks."])
    return "\n".join(lines) + "\n"


def main() -> int:
    args = parse_args()
    root = Path(args.root).expanduser()
    if not root.exists() or not root.is_dir():
        print(f"error: knowledge base not found: {root}", file=sys.stderr)
        return 2
    if args.stale_days < 0 or args.max_lines < 1:
        print("error: --stale-days must be >= 0 and --max-lines must be >= 1", file=sys.stderr)
        return 2

    result = audit(root.resolve(), args.stale_days, args.max_lines)
    if args.json:
        print(json.dumps(result, indent=2))
    else:
        print(render_markdown(result), end="")

    if args.fail_on == "none":
        return 0
    if args.fail_on == "warn":
        return 1 if result["summary"]["total"] else 0
    return 1 if result["summary"]["errors"] else 0


if __name__ == "__main__":
    sys.exit(main())
