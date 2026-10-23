# Backlinks

A knowledge base becomes useful when pages point at each other. A mention without a backlink is an incomplete capture.

# The back-link law

If page A mentions entity B and B has a page, B must link back to A.

- A mention in prose is not enough.
- A link only in A's direction leaves B's page blind.
- Every new durable page needs at least one inbound link from a related page.
- A page with zero inbound links is an orphan; `knowledge-maintenance` reports it.

# Link types

Use wikilinks with an optional label:

```md
[[people/jane-doe]]
[[people/jane-doe|Jane Doe]]
```

Use relative Markdown links when the target is a file outside the knowledge base:

```md
[the pricing review](../meetings/2026-05-21-pricing-review.md)
```

Typed relationships can be recorded in frontmatter or a See Also section:

| Verb | From → To | Example |
|---|---|---|
| `works_at` | person → company | Jane works at Acme |
| `founded` | person → company | Jane founded Acme |
| `invested_in` | person/company → company | Acme invested in Beta |
| `advises` | person → company | Jane advises Beta |
| `attended` | person → meeting | Jane attended the pricing review |
| `mentions` | page → entity | The review mentions Jane |
| `source` | page → original | The summary came from this article |

# Back-link format

Append to the entity page's timeline or See Also section:

```md
- **2026-05-21** | Referenced in [Pricing review](meetings/2026-05-21-pricing-review.md) — annual-only experiment
```

Rules:

- date first, ISO or `YYYY-MM-DD`
- the link text is the referencing page's title
- a short context phrase after the dash
- newest first
- do not duplicate the same reference

# Filing rules

1. **One primary subject per page.** If a capture has three subjects, split it or leave it in `inbox/`.
2. **Entity pages are hubs.** A person/company page collects timeline entries, links, and facts.
3. **Original sources are immutable.** Store the raw article/transcript in `originals/`; summarize elsewhere.
4. **Do not re-file without a reason.** Moving a page breaks links; update the backlinks first.
5. **Prefer the existing tree.** Add a new folder only when ten pages share the shape.

# Creating an entity page

```md
---
title: "Jane Doe"
type: "person"
slug: "people/jane-doe"
captured_at: "2026-05-21T09:30:00Z"
content_hash: "..."
---

# Jane Doe

CTO at Acme.

## Timeline
- **2026-05-21** | Referenced in [Pricing review](meetings/2026-05-21-pricing-review.md) — annual-only experiment
- **2026-05-10** | Met at [Demo Day](meetings/2026-05-10-demo-day.md)
```

# Checking links

```bash
# Find mentions that are not links
rg -n "Jane Doe" "$KB_ROOT" --glob '*.md'

# Find orphan pages (no inbound links)
python3 knowledge-maintenance/scripts/kb-audit.py --root "$KB_ROOT"
```

# Common mistakes

| Mistake | Fix |
|---|---|
| Linking from A to B but not B to A | Add the backlink to B |
| Linking to a title instead of a slug | Use `[[people/jane-doe]]` or the exact file path |
| Duplicating the same year of timeline entries | Keep the specific reference, drop the duplicate |
| Creating a new person page for every spelling | Add an alias to the canonical page |
| Filing an article in `concepts/` | Keep the source in `originals/`, summarize in `concepts/` |
