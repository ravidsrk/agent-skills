# Frontmatter

Every captured page starts with YAML frontmatter. Keep it small and consistent; the query and maintenance skills depend on it.

# Required fields

| Field | Type | Example | Why |
|---|---|---|---|
| `title` | string | `"Pricing review"` | Human and search label |
| `type` | string | `meeting` | Routing and filtering |
| `slug` | string | `meetings/2026-05-21-pricing-review` | Stable identity |
| `captured_at` | ISO-8601 string | `2026-05-21T09:30:00Z` | Recency and staleness |
| `content_hash` | string | `f3a7b9c0...` | Dedupe key |

# Recommended fields

| Field | Type | Example |
|---|---|---|
| `source` | URL or string | `https://example.com/article` |
| `author` | string | `"Jane Doe"` |
| `published_at` | ISO-8601 | `2026-05-01` |
| `tags` | array of strings | `['pricing', 'experiment']` |
| `provenance` | enum | `user`, `agent`, `external` |
| `captured_via` | string | `capture.sh` |
| `updated_at` | ISO-8601 | `2026-05-22T10:00:00Z` |

# Type vocabulary

Use an existing type before inventing one:

`note`, `article`, `meeting`, `voice-note`, `person`, `company`, `concept`, `idea`, `project`, `reflection`, `source`, `report`.

A new type should be shared by at least ten pages and declared in the taxonomy. See `knowledge-maintenance/references/taxonomy.md`.

# YAML quoting

YAML breaks on unescaped quotes and colons. Use these rules:

```yaml
# Simple values: unquoted is fine
type: note
slug: inbox/2026-05-21-f3a7b9c0

# Values with a colon, quote, or leading special char: double-quote and escape
title: "Pricing: annual-only first"
title: "The \"quiet\" launch"

# Values with an apostrophe: double quotes are easiest
title: "Men's fashion guide"

# Arrays: single-quoted flow is canonical
tags: ['pricing', 'experiment']

# Arrays with an apostrophe inside a value: double-quote that item
tags: ["Men's fashion", 'pricing']
```

Do not use JSON objects inside a YAML flow sequence unless every item is an object:

```yaml
# Broken
tags: [{"name": "sports"}, "posterous"]

# Correct
tags:
  - sports
  - posterous
```

# Dates and times

- Use UTC ISO-8601 with a trailing `Z`.
- `captured_at` is the capture time, not the source publication time.
- `published_at` is the source's publication date when known.
- `updated_at` changes when the page body is materially edited.

# Provenance

| Value | Meaning | May be presented as fact? |
|---|---|---|
| `user` | The user said or wrote it | Yes, attributed to the user |
| `agent` | An agent inferred or synthesized it | No; label as inference |
| `external` | A third-party source | Yes, with a citation and date |

If provenance is omitted, treat the page as `user` only when the body is the user's own words. Otherwise set it explicitly.

# Example

```yaml
---
title: "Pricing review"
type: "meeting"
slug: "meetings/2026-05-21-pricing-review"
captured_at: "2026-05-21T09:30:00Z"
updated_at: "2026-05-21T11:00:00Z"
captured_via: "capture.sh"
provenance: "user"
tags: ['pricing', 'experiment']
content_hash: "f3a7b9c0d1e2f3a4..."
---
```

# Validation

`knowledge-maintenance/scripts/kb-audit.py` checks:

- opening and closing `---`
- required fields present and non-empty
- `slug` matches the path
- `captured_at` / `updated_at` parse as dates
- `tags` is a list
- duplicate titles across pages

Run it before committing a batch of captures.
