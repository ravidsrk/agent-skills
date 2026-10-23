---
name: knowledge-query
description: >-
  Answer questions from a markdown knowledge base with grounded citations —
  keyword, semantic, and graph search; source precedence; gap flags; daily
  briefings; research synthesis. Use when the user asks "what do we know about
  X", "search my notes/brain", "who is X", "give me a briefing", "summarize what
  I know about Y", or needs an answer traceable to sources.
license: MIT
compatibility: Requires ripgrep (rg) for keyword search; optional jq for JSON output. Optional gbrain CLI/MCP for semantic and graph search.
metadata:
  version: "0.1.0"
  author: "@ravidsrk"
allowed-tools: Bash Read Write Edit
---

# Knowledge Query

Answer from the knowledge base, not from vibes. Every claim traces to a page; every gap is stated; every conflict is surfaced instead of silently resolved.

This skill works on a plain markdown tree (`$KB_ROOT`). If gbrain is installed, its hybrid search and graph queries replace the keyword layer; the answer contract stays the same.

# When to use

- "What do we know about X?"
- "Search my notes / my brain for Y"
- "Who is X?" / "How are A and B connected?"
- "What happened with X?"
- "Give me a briefing for today"
- "Summarize what I know about Y"
- "Research this topic using my notes plus the web"
- Any question where an uncited answer would be untrustworthy

# When NOT to use

- The knowledge base has no relevant content and the user wants general knowledge — say so and use a web/research tool instead.
- The user wants a creative draft, not a grounded answer.
- The question is about a live system state that must be queried from an API, not from notes.

# Setup

```bash
export KB_ROOT="${KB_ROOT:-$HOME/brain}"
rg --version
```

Optional gbrain:

```bash
gbrain query "what do we know about pricing?"
gbrain graph-query companies/acme --type works_at --direction in
```

# The answer contract

1. **Grounded** — answer from pages in the knowledge base, not from the model's memory.
2. **Cited** — every factual claim carries `[Source: <slug>, <section>, updated <date>]`.
3. **Gap-aware** — if the base does not contain the answer, say "the knowledge base has no information on X" and name what is missing.
4. **Conflict-aware** — if sources disagree, show both with citations; do not pick one silently.
5. **Freshness-aware** — flag pages older than 90 days, or whose `updated_at` predates newer evidence.
6. **Token-aware** — read search chunks first; load full pages only when needed.

# Workflow

## Step 1 — Decompose the question

Break it into searchable parts:

| Question type | Strategy |
|---|---|
| Entity lookup ("who is Jane?") | Keyword + person page + backlinks |
| Topic recall ("what do we know about pricing?") | Keyword + concept pages + recent pages |
| Relationship ("how are Jane and Acme connected?") | Graph/backlinks + typed links |
| Timeline ("what happened last month?") | Date filters + meeting/timeline entries |
| Decision ("why did we choose X?") | Meeting notes + decision records + source docs |
| Gap ("do we have anything on Y?") | Keyword + semantic, then state the gap |

## Step 2 — Layer 1: keyword search

```bash
bash scripts/search.sh "pricing experiment" --limit 20
bash scripts/search.sh "Jane Doe" --type person
```

Use several query shapes: exact names, distinctive phrases, synonyms, and likely folder names. Search filenames and frontmatter, not just body text.

## Step 3 — Layer 2: semantic search

If gbrain or an MCP search tool is available:

```bash
gbrain query "why did we choose annual-only pricing?"
```

Otherwise expand the keyword search with synonyms and related terms. Do not claim semantic coverage you did not run.

## Step 4 — Layer 3: graph search

For relationship questions, follow links:

```bash
rg -n '\[\[people/jane-doe' "$KB_ROOT" --glob '*.md'
rg -n 'works_at|founded|invested_in|advises' "$KB_ROOT" --glob '*.md'
```

With gbrain:

```bash
gbrain graph-query people/jane-doe --depth 2 --direction both
```

## Step 5 — Read the top results

- Start with the search chunks.
- Load the full page only when the chunk is insufficient.
- Read the page's citations and timeline, not just the body.
- Prefer the most recent page when two pages cover the same fact.

## Step 6 — Synthesize with citations

```md
Jane is CTO of Acme [Source: people/jane-doe, updated 2026-04-01].
The annual-only pricing experiment was approved on 2026-05-21
[Source: meetings/2026-05-21-pricing-review, Decisions section].
```

Rules:

- Cite the slug and the section, not a vague "notes".
- If you synthesize across pages, cite each one.
- Quote exact phrasing for decisions and commitments.
- Put inference behind an explicit label: "Inferred from ...".

## Step 7 — State gaps, staleness, and conflicts

```md
Gap: the knowledge base has no information on the enterprise contract renewal.
Stale: the pricing page was last updated 2026-01-10; newer meeting notes may supersede it.
Conflict: the 2026-03-02 note says monthly-first; the 2026-05-21 review says annual-only.
```

Never fill a gap with plausible-sounding detail.

## Step 8 — Offer the next action

- "Want me to capture the missing source?"
- "Want me to reconcile the two conflicting notes?"
- "Want the full timeline for this entity?"

# Answer format

```md
## Answer
{Direct answer in 1–3 sentences.}

## Evidence
- {Claim} [Source: {slug}, {section}, updated {date}]
- ...

## Gaps and conflicts
- {What the base does not cover}
- {Conflicting sources, with both citations}

## Suggested next step
- {Capture the missing source / reconcile / read the full page}
```

# Daily briefing

A briefing is a query with a fixed shape:

1. Brain pulse: new facts, contradictions, pending consolidation.
2. Today's meetings and attendees.
3. Active deals / projects and approaching deadlines.
4. Open action items.
5. Recent changes (last 24 hours).
6. People in play.
7. Stale pages relevant to today.

See `references/briefing.md` for the query list and output template.

# Research and synthesis

For "research this using my notes plus the web":

1. Query the knowledge base first.
2. State what is already known, with citations.
3. Fetch external sources only for what is missing or needs verification.
4. Label external facts and their dates.
5. Return "what is new vs what the base already knew".

See `references/research.md` for academic verification, strategic reading, book mirroring, and concept synthesis.

# Common gotchas

| Gotcha | Fix |
|---|---|
| Answer sounds confident but has no citation | Treat it as a draft; go back to search |
| Search returns nothing because of wording | Try synonyms, folder names, and exact phrases |
| Two pages disagree | Show both; do not average them |
| Page is stale | Flag the date; prefer newer evidence |
| Full page is too large | Read chunks first; load sections on demand |
| Search hits `inbox/` triage noise | Filter by type or folder; triage the inbox |
| External research overwrites the base | Label external facts; capture the source separately |
| The base has no answer | Say so explicitly; offer to capture the missing source |

# References

- `references/search.md` — query templates, layers, ranking, token budget
- `references/citations.md` — source precedence, citation format, staleness, conflicts
- `references/briefing.md` — daily briefing sections and queries
- `references/research.md` — external research, academic verification, strategic reading, book mirror, concept synthesis
- `scripts/search.sh` — keyword search over `$KB_ROOT`
