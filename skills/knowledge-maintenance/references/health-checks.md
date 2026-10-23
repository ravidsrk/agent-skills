# Health checks

Each dimension has a detection method, a threshold, and a repair action. Fix errors before warnings; fix the highest-traffic pages first.

# missing_frontmatter

**Severity:** error

**Detect:** the file does not start with `---`, or the opening block has no closing `---` before the first heading.

**Repair:** add a valid block with at least `title`, `type`, `slug`, `captured_at`, `content_hash`. If the page predates the schema, derive the slug from the path and set `captured_at` to the file's first commit date.

**Do not:** invent a `content_hash` for an edited page; recompute it from the body.

# empty_frontmatter

**Severity:** error

**Detect:** opening and closing `---` are present, but there are no fields between them.

**Repair:** fill the block from the page content: title, type, slug, captured_at, content_hash.

**Do not:** auto-fill `captured_at` with today's date for a historical page.

# missing_type

**Severity:** warn

**Detect:** frontmatter exists but has no `type`.

**Repair:** choose a type from `taxonomy.md`. Do not invent a type for a single page; use `note` plus a tag.

# frontmatter_parse_error

**Severity:** error

**Detect:** the block has an unterminated quote or array, or a line that is neither a key nor an indented continuation.

**Repair:** quote the value correctly, close the array, or indent the continuation. Re-run the audit on the single file.

**Do not:** delete the block to make the error disappear; the page loses its identity.

# missing_required_field

**Severity:** error

**Detect:** `slug`, `captured_at`, or `content_hash` is missing or empty.

**Repair:** derive the slug from the path, set `captured_at` from the page's first commit or capture receipt, and compute `content_hash` from the canonical body.

**Do not:** copy another page's hash.

# missing_title

**Severity:** error

**Detect:** no frontmatter `title` and no H1.

**Repair:** use the first meaningful heading or a short descriptive title. Do not use the filename slug as the title.

# slug_mismatch

**Severity:** error

**Detect:** frontmatter `slug` differs from the path-derived slug (`people/jane-doe` for `people/jane-doe.md`).

**Repair:** update the frontmatter to the path-derived slug. If the rename was intentional, update inbound links first, then rename.

**False positive:** a page that intentionally keeps a stable slug after a move. Record the exception in frontmatter (`aliases: [...]`) rather than ignoring the check.

# broken_wikilink

**Severity:** error

**Detect:** `[[target]]` or `[[target|label]]` resolves to no page by slug, path, title, or unique basename.

**Repair:** update the link to the new slug, create the missing page, or remove the link if the target is obsolete.

**Do not:** delete the source page to silence the warning.

# broken_asset

**Severity:** error

**Detect:** a local image, PDF, video, or other non-Markdown file link points to a path that does not exist.

**Repair:** restore the file, fix the relative path, or remove the link.

**Do not:** convert an asset link into a page link to silence the check.

# invalid_date

**Severity:** warn

**Detect:** `updated_at`, `captured_at`, `created_at`, or `published_at` does not start with a parseable `YYYY-MM-DD`.

**Repair:** use UTC ISO-8601 (`2026-05-21` or `2026-05-21T09:30:00Z`). Do not guess.

# stale_page

**Severity:** warn

**Detect:** the newest of `updated_at`, `captured_at`, `created_at` is older than `--stale-days` (default 90).

**Repair:** read the page and its timeline. Rewrite the synthesis if newer evidence exists; otherwise mark it `status: archived` or move it to `archive/`.

**Do not:** bump `updated_at` without changing the content.

# orphan_page

**Severity:** warn

**Detect:** zero inbound links from other pages.

**Repair:** link it from an index, entity, or project page; if it is genuinely isolated, archive or delete it after confirmation.

**Exempt:** `inbox/`, `archive/`, `README.md`, `index.md`, and the root landing page. Orphan checks are skipped when the base has fewer than three pages.

# duplicate_title

**Severity:** warn

**Detect:** two or more pages share a normalized title (lowercase, punctuation removed).

**Repair:** pick the canonical page, merge the content, leave an alias/redirect, and update inbound links.

**False positive:** recurring titles such as "Weekly review". Include the date in the title.

# oversized_page

**Severity:** warn

**Detect:** more than `--max-lines` lines (default 500).

**Repair:** split by subject, not by line count. Keep a hub page that links to the parts. Move raw reference material to `originals/` or `references/`.

# Threshold recommendations

| Base size | Stale days | Max lines | Orphan check |
|---|---:|---:|---|
| < 50 pages | 180 | 800 | off |
| 50–500 | 90 | 500 | on |
| 500+ | 60 | 400 | on, with archive exemptions |

# Report format

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
- `companies/acme.md` — confirm whether the page should be linked or archived.
```

# Never

- Delete pages to make a report green.
- Rewrite `updated_at` without a content change.
- Batch-fix links without reading the target.
- Run a repair on the only copy.
- Treat every orphan as a mistake; some pages are intentionally isolated.
