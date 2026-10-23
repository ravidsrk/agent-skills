---
name: knowledge-maintenance
description: >-
  Audit and repair a markdown knowledge base — missing or malformed frontmatter,
  broken wikilinks, orphan pages, stale pages, duplicate titles, oversized pages,
  and taxonomy drift. Use when the user asks to "check brain health", "audit my
  notes", "fix broken links", "find stale pages", "clean up my knowledge base",
  or after a large import.
license: MIT
compatibility: Requires Python 3.8+ (standard library only). Optional gbrain CLI for schema-aware and semantic checks.
metadata:
  version: "0.1.0"
  author: "@ravidsrk"
allowed-tools: Bash Read Write Edit
---

# Knowledge Maintenance

A knowledge base degrades quietly: captures pile up with missing frontmatter, links point at renamed pages, entities become orphans, and old decisions stay on the front page after newer evidence lands. This skill makes the decay visible and fixes it one category at a time.

The audit script is generic and standard-library-only. If gbrain is installed, its schema, taxonomy, and embedding checks can run in addition.

# When to use

- "Check my brain health"
- "Audit my notes / knowledge base"
- "Find broken links" / "find orphan pages"
- "What is stale?"
- "Clean up frontmatter"
- "The taxonomy is a mess"
- After a large import, a rename, or a month of captures
- Before relying on the base for a decision

# When NOT to use

- The base has fewer than ten pages; read them directly.
- The user wants a content rewrite, not a structural audit.
- A page is intentionally unlinked (a scratchpad); mark it as exempt instead of "fixing" it.
- A destructive cleanup without a backup; always snapshot first.

# Setup

```bash
export KB_ROOT="${KB_ROOT:-$HOME/brain}"
python3 --version
```

Optional gbrain:

```bash
gbrain doctor --json
gbrain schema stats --json
gbrain frontmatter audit --json
```

# The workflow

## Step 1 — Snapshot

If the base is a git repo, commit or stash first. If it is not, copy it or create a tar archive. Never run a repair on the only copy.

```bash
git -C "$KB_ROOT" status --short
git -C "$KB_ROOT" add -A && git -C "$KB_ROOT" commit -m "chore: snapshot before KB audit"
```

## Step 2 — Audit

```bash
python3 scripts/kb-audit.py --root "$KB_ROOT"
```

Machine-readable:

```bash
python3 scripts/kb-audit.py --root "$KB_ROOT" --json > audit.json
```

The audit is read-only. It reports:

| Code | Severity | Meaning |
|---|---|---|
| `missing_frontmatter` | error | No opening/closing `---` block |
| `empty_frontmatter` | error | Opening and closing present but nothing between |
| `frontmatter_parse_error` | error | Malformed YAML (unterminated quote/array, unknown line) |
| `missing_required_field` | error | `slug`, `captured_at`, or `content_hash` is missing |
| `missing_title` | error | No frontmatter title or H1 |
| `missing_type` | warn | Frontmatter has no `type` |
| `slug_mismatch` | error | Frontmatter `slug` differs from the path |
| `broken_wikilink` | error | `[[target]]` resolves to no page |
| `broken_asset` | error | A local image/PDF/file link does not exist |
| `read_error` | error | The page could not be read (permissions/encoding) |
| `invalid_date` | warn | `updated_at` / `captured_at` is not parseable |
| `stale_page` | warn | Older than `--stale-days` (default 90) |
| `orphan_page` | warn | No inbound links |
| `duplicate_title` | warn | Two pages share a normalized title |
| `oversized_page` | warn | More than `--max-lines` (default 500) |

## Step 3 — Triage

Fix errors first, then warnings. Within a category, fix the highest-traffic pages first: `index.md`, entity pages, and pages with many inbound links.

Do not batch-fix a category you have not read. A "broken" link may be a deliberate reference to a page you are about to create.

## Step 4 — Repair, one category at a time

### Frontmatter

- Add missing `title`, `type`, `slug`, `captured_at`, `content_hash`.
- Fix YAML quoting. A title with a colon or quote must be quoted and escaped.
- Fix slug mismatches by updating the frontmatter to the path-derived slug, not by renaming the file (unless the rename is intentional).

### Broken links

- If the target exists under a new slug, update the link.
- If the target is a person/company that should exist, create the page and add the backlink.
- If the target is obsolete, remove the link or point it at `archive/`.
- Do not delete a page to silence a link.

### Orphans

- Link them from the relevant index, entity, or project page.
- If they are genuinely isolated, move them to `archive/` or delete them after confirmation.
- Exempt `inbox/`, `archive/`, `README.md`, and `index.md` from the orphan check.

### Stale pages

- Read the page and its timeline.
- Rewrite the synthesis if newer evidence exists.
- If the page is historical, set `status: archived` or move it to `archive/`.
- Do not merely bump `updated_at`.

### Duplicate titles

- Pick the canonical page.
- Merge the content.
- Leave a redirect or an alias in the old page.
- Update inbound links.

### Oversized pages

- Split by subject, not by line count.
- Keep a hub page that links to the parts.
- Move reference material to `references/` or `originals/`.

## Step 5 — Re-run

```bash
python3 scripts/kb-audit.py --root "$KB_ROOT" --fail-on error
```

The repair is done when the same findings are gone, not when the count happens to drop.

## Step 6 — Report

```md
## Knowledge Base Health — YYYY-MM-DD

| Dimension | Found | Fixed | Remaining |
|---|---:|---:|---:|
| Missing frontmatter | 4 | 4 | 0 |
| Broken links | 9 | 7 | 2 |
| Orphans | 6 | 3 | 3 |
| Stale pages | 12 | 5 | 7 |
| Duplicate titles | 2 | 2 | 0 |
| Oversized pages | 1 | 0 | 1 |

### Needs a human
- ...
```

Store the report with the base or in the PR. It is the audit trail.

# Schema and taxonomy

A large base needs a small vocabulary:

- **Page types:** note, article, meeting, person, company, concept, idea, project, reflection, source, report.
- **Prefixes:** `people/`, `companies/`, `meetings/`, `concepts/`, `ideas/`, `projects/`, `originals/`, `voice-notes/`.
- **Link verbs:** `works_at`, `founded`, `invested_in`, `advises`, `attended`, `mentions`, `source`.

Add a new type only when at least ten pages share the shape. See `references/taxonomy.md`.

# Cadence

| Cadence | Check |
|---|---|
| Every capture | frontmatter + one backlink |
| Weekly | inbox triage, broken links, orphans |
| Monthly | stale pages, duplicate titles, oversized pages |
| Quarterly | taxonomy, schema, archive review |
| After a rename/import | full audit |

# Common gotchas

| Gotcha | Fix |
|---|---|
| Audit flags an intentional unlinked scratchpad | Move it to `inbox/` or add an exemption |
| Slug mismatch after a rename | Update the frontmatter slug; links still need updating |
| Orphan count explodes after an import | Link the new pages from an index before re-running |
| Stale flag on historical minutes | Mark historical pages `status: archived` |
| Duplicate titles are legitimate (two "Weekly review" pages) | Include the date in the title |
| Repair deletes content | Never delete without confirmation; snapshot first |
| YAML fix breaks a page | Validate one file at a time; keep the backup |
| gbrain and plain-markdown counts disagree | They scan different roots/sources; report the root explicitly |

# References

- `references/health-checks.md` — every dimension, threshold, and repair action
- `references/frontmatter-schema.md` — fields, validation classes, YAML traps
- `references/taxonomy.md` — page types, prefixes, link verbs, merge rules
- `scripts/kb-audit.py` — read-only audit with Markdown and JSON output
