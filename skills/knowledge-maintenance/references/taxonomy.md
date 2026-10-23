# Taxonomy

A small, stable vocabulary beats a perfect one. Add a type only when the corpus demands it.

# Page types

| Type | What it is | Prefix |
|---|---|---|
| `note` | A captured thought or fragment | `inbox/` |
| `article` | Raw or summarized external writing | `originals/` |
| `meeting` | Transcript, decisions, action items | `meetings/` |
| `voice-note` | Verbatim transcript of a recording | `voice-notes/` |
| `person` | A human, with a timeline | `people/` |
| `company` | An organization | `companies/` |
| `concept` | A durable idea or definition | `concepts/` |
| `idea` | A product/experiment candidate | `ideas/` |
| `project` | A scoped body of work | `projects/` |
| `reflection` | Personal synthesis | `personal/` |
| `source` | A source document that is not an article | `originals/` |
| `report` | A generated health/briefing report | `reports/` |

# Prefixes

- Prefixes are directory names, not tags.
- A page type may have one canonical prefix.
- Do not create a prefix for fewer than ten pages.
- Do not move existing pages to a new prefix without updating inbound links.

# Link verbs

| Verb | From → To | Meaning |
|---|---|---|
| `works_at` | person → company | employment |
| `founded` | person → company | founder |
| `invested_in` | person/company → company | investment |
| `advises` | person → company | advisor |
| `attended` | person → meeting | attendance |
| `mentions` | page → entity | a reference |
| `source` | page → original | provenance |

Use the verb in prose or frontmatter; the audit only needs a resolvable link.

# When to add a type

Add a type when all are true:

- at least ten pages share the shape
- the type answers a query the current types cannot
- the prefix is clear and stable
- the name is one word, lowercase
- the type does not duplicate an existing type under a synonym

Otherwise use an existing type plus a tag.

# Aliases

When a page is renamed or a synonym appears:

```yaml
aliases: ['jane', 'j-doe', 'people/jane']
```

Aliases keep old links resolvable. Do not create a second page for every spelling.

# Merge and dedupe

1. Pick the canonical page: the one with the most inbound links and the best synthesis.
2. Merge unique content; preserve quotes and dates.
3. Move raw material to `originals/` if it is bulky.
4. Add aliases for the old slugs.
5. Update inbound links.
6. Leave a redirect page only when the old slug is public or widely linked.

# Naming

- lowercase, digits, hyphens
- no underscores, spaces, or file extensions in the slug
- dates as `YYYY-MM-DD`
- descriptive, not clever
- meeting slugs include the date: `meetings/2026-05-21-pricing-review`
- person slugs use the name: `people/jane-doe`

# Archive

Move to `archive/` when:

- the page is historical and no longer current
- the project ended
- the source is superseded but still useful as evidence

Keep the slug stable; archive is a location, not a deletion. Add `status: archived` or a note at the top.

# Review cadence

- Monthly: check that every type has at least one page and every prefix is used.
- Quarterly: review new-type proposals and dead prefixes.
- After a rename/import: run `knowledge-maintenance` and update aliases.
