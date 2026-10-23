# Citations

Every factual claim needs a source. A confident answer without a citation is a draft, not knowledge.

# Citation format

```md
Jane is CTO of Acme [Source: people/jane-doe, compiled truth, updated 2026-04-01].
```

```md
The annual-only experiment was approved on 2026-05-21
[Source: meetings/2026-05-21-pricing-review, Decisions, updated 2026-05-21].
```

Include:

- the slug (path without `.md`)
- the section or field
- the `updated_at` date when available

For external sources, include the URL and publication date:

```md
[Source: https://example.com/article, published 2026-05-01]
```

# Source precedence

When sources conflict, apply this order:

1. **The user's direct statements** — what the user told you in this session.
2. **Compiled truth / decision records** — the synthesized, reviewed page.
3. **Timeline entries and meeting notes** — raw evidence with dates.
4. **External sources** — web pages, third-party APIs, other people's notes.

Higher precedence wins, but never silently discard a lower source. Show the conflict.

# Staleness

Flag a page when:

- `updated_at` is older than 90 days
- the page has a recent timeline entry but no updated synthesis
- a newer meeting or decision supersedes it
- the source URL is dead

```md
Stale: `concepts/pricing.md` was last updated 2026-01-10; the 2026-05-21 review supersedes the monthly-first recommendation.
```

# Conflicts

When two pages disagree:

1. Quote both claims.
2. Cite both sources with dates.
3. State which is newer, without pretending the older one never existed.
4. Ask whether to reconcile the pages.

```md
Conflict:
- 2026-03-02 note: start with monthly pricing [Source: inbox/2026-03-02-1a2b3c4d].
- 2026-05-21 review: start with annual-only [Source: meetings/2026-05-21-pricing-review, Decisions].
The May decision is newer; the March note has not been marked superseded.
```

Do not average conflicting numbers or split the difference.

# Gaps

Say exactly what is missing:

```md
Gap: no page covers enterprise contract renewal. The closest sources are the pricing review and the sales notes, neither of which mentions renewal terms.
```

Then offer an action:

- capture the missing source
- ask the user for the detail
- fetch an external source
- leave the gap open

# Inference

If you infer something not explicitly stated, label it:

```md
Inferred: the annual-only test likely targets new signups, because the review mentions the signup funnel. This is not stated explicitly in the source.
```

Never present an inference as a quoted fact.

# Quoting

- Quote decisions and commitments verbatim.
- Keep the speaker and date.
- Do not clean up a quote in a way that changes meaning.
- Use `[sic]` only when necessary.

# Evidence table

For multi-source answers, include a compact table:

| Claim | Source | Updated |
|---|---|---|
| Annual-only approved | `meetings/2026-05-21-pricing-review` | 2026-05-21 |
| Monthly-first was the prior plan | `inbox/2026-03-02-1a2b3c4d` | 2026-03-02 |
| Retention impact unknown | — | — |

The table makes gaps and conflicts visible at a glance.
