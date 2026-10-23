# knowledge-maintenance

Audit and repair a markdown knowledge base: frontmatter, links, orphans, stale pages, duplicates, and taxonomy drift.

## What it does

- Scans every `.md` / `.mdx` page under a root.
- Checks frontmatter shape, required fields, and slug/path agreement.
- Resolves `[[wikilinks]]` and local Markdown links; reports broken targets.
- Finds pages with no inbound links.
- Flags pages older than a threshold.
- Finds duplicate titles and oversized pages.
- Outputs a Markdown report or JSON, with a non-zero exit code for CI.
- Never modifies a file; repairs are a separate, reviewed step.

## When to use

- "Check my brain health" / "audit my notes"
- "Find broken links" / "find orphan pages"
- "What is stale?"
- "Clean up frontmatter"
- After a large import, a rename, or a month of captures

## Install

```bash
python3 --version   # 3.8+
export KB_ROOT="${KB_ROOT:-$HOME/brain}"
```

No third-party packages. Optional [gbrain](https://github.com/garrytan/gbrain) for schema, taxonomy, and embedding checks.

## Usage

```bash
# Markdown report
python3 scripts/kb-audit.py --root "$KB_ROOT"

# Strict CI gate
python3 scripts/kb-audit.py --root "$KB_ROOT" --fail-on error

# JSON for a dashboard
python3 scripts/kb-audit.py --root "$KB_ROOT" --json > audit.json

# Tune thresholds
python3 scripts/kb-audit.py --root "$KB_ROOT" --stale-days 60 --max-lines 800
```

## Report

```md
# Knowledge Base Audit — 2026-05-21

Root: /path/to/brain
Files: 412
Findings: 31 (4 errors, 27 warnings)

| Code | Severity | Count |
|---|---|---:|
| broken_wikilink | error | 3 |
| missing_frontmatter | error | 1 |
| empty_frontmatter | error | 0 |
| missing_type | warn | 2 |
| orphan_page | warn | 12 |
| stale_page | warn | 9 |
...

## Errors
- `people/jane-doe.md` — broken wikilink: `companies/acme`

## Warnings
- `concepts/pricing.md` — stale since 2025-12-01 (171 days)
```

## Exit codes

| Code | Meaning |
|---|---|
| 0 | No findings at or above `--fail-on` |
| 1 | Findings at or above the threshold |
| 2 | Usage or runtime error |

## File layout

```
knowledge-maintenance/
├── SKILL.md
├── README.md
├── references/
│   ├── health-checks.md
│   ├── frontmatter-schema.md
│   └── taxonomy.md
└── scripts/
    └── kb-audit.py
```

## Known gotchas

| Gotcha | Fix |
|---|---|
| Intentional unlinked scratchpad flagged | Move it to `inbox/` or add it to the audit's ignore list |
| Slug mismatch after a rename | Update the frontmatter slug, then update inbound links |
| Orphan count explodes after an import | Link new pages from an index first |
| Historical minutes flagged stale | Mark them `status: archived` or move to `archive/` |
| Duplicate "Weekly review" titles | Include the date in the title |
| YAML repair breaks a page | Validate one file at a time; keep a backup |
| Audit is slow on a huge base | Scope `--root` to a subtree or exclude `archive/` |

## Pairs with

- `knowledge-capture` — fix frontmatter at write time.
- `knowledge-query` — use the repaired index for grounded answers.

## Credits

- Health-check dimensions, frontmatter validation classes, schema evolution, and taxonomy rules adapted from [gbrain](https://github.com/garrytan/gbrain) (MIT, Copyright (c) 2026 Garry Tan).

## License

MIT
