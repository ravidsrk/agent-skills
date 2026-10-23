# Frontmatter schema

The audit script parses a deliberately small YAML subset. Keep frontmatter simple: one scalar or inline array per key, no nested mappings.

# Required fields

| Field | Type | Rule |
|---|---|---|
| `title` | string | non-empty, ≤ 200 chars |
| `type` | string | from the taxonomy; lowercase |
| `slug` | string | matches the path without `.md` |
| `captured_at` | date/ISO | `YYYY-MM-DD` or ISO-8601 |
| `content_hash` | string | hex digest of the body |

A page without these is a capture failure, not a stylistic choice.

# Recommended fields

| Field | Type | Purpose |
|---|---|---|
| `updated_at` | date/ISO | freshness and staleness |
| `created_at` | date/ISO | original creation |
| `source` | URL/string | provenance |
| `author` | string | attribution |
| `published_at` | date | source date |
| `tags` | inline array | retrieval |
| `provenance` | enum | `user`, `agent`, `external` |
| `status` | enum | `active`, `archived`, `draft` |
| `aliases` | inline array | stable links after renames |

# Validation classes

| Code | Meaning | Auto-fixable |
|---|---|---|
| `MISSING_OPEN` | file does not start with `---` | no |
| `MISSING_CLOSE` | no closing `---` before the first heading | yes |
| `YAML_PARSE` | the block does not parse | sometimes |
| `SLUG_MISMATCH` | `slug` differs from the path | yes |
| `NULL_BYTES` | binary corruption | yes |
| `NESTED_QUOTES` | `title: "outer "inner" outer"` | yes |
| `EMPTY_FRONTMATTER` | opening and closing present but empty | no |
| `INVALID_DATE` | date does not start with `YYYY-MM-DD` | no |
| `MISSING_TITLE` | no title and no H1 | no |

# YAML quoting rules

```yaml
# Simple values
type: note
status: active

# Colon, quote, or leading special character: double-quote and escape
title: "Pricing: annual-only first"
title: "The \"quiet\" launch"

# Apostrophe: double quotes
title: "Men's fashion guide"

# Inline arrays: single-quoted items are canonical
tags: ['pricing', 'experiment']

# Block arrays
tags:
  - pricing
  - experiment
```

Do not use JSON objects inside a flow sequence unless every item is an object:

```yaml
# Broken
tags: [{"name": "sports"}, "posterous"]
```

# Dates

- UTC, ISO-8601.
- Date-only is fine for `published_at`.
- Use a trailing `Z` for timestamps.
- `updated_at` changes only when the body materially changes.

# Content hash

- Hash the body after stripping the frontmatter block.
- Use SHA-256 hex.
- Recompute after a material edit; do not reuse the old hash.
- The hash is an identity/dedupe key, not a signature.

# Repair workflow

1. Read the file.
2. Fix one validation class at a time.
3. Keep a `.bak` or a git commit before batch fixes.
4. Re-run the audit on the file or subtree.
5. Do not auto-fix `MISSING_OPEN` or `EMPTY_FRONTMATTER` without reading the page; they usually mean an unfinished draft.
