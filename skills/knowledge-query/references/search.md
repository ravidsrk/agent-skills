# Search

Three layers, in order. Use the cheapest layer that answers the question; escalate only when it does not.

# Layer 1 — keyword

Fast, explainable, and good for names, decisions, and distinctive phrases.

```bash
bash scripts/search.sh "annual-only pricing" --limit 20
bash scripts/search.sh "Jane Doe" --type person
bash scripts/search.sh "works_at" --files-only
```

Raw `rg` equivalents:

```bash
rg -n -i --glob '*.md' --glob '*.mdx' "annual-only pricing" "$KB_ROOT"
rg -l '^type:\s*"?person"?\s*$' "$KB_ROOT" --glob '*.md'
```

Query shapes to try:

- exact name or phrase
- distinctive words from the decision
- folder names (`meetings`, `people`, `companies`)
- tags from frontmatter
- error messages, identifiers, or dates

# Layer 2 — semantic

Use gbrain or an MCP search tool when the question is conceptual and the exact words are unknown.

```bash
gbrain query "why did we choose annual-only pricing?"
gbrain search "pricing decision" --limit 20
```

If no semantic tool is available:

1. Expand the question into 5–10 synonyms and related terms.
2. Search each term.
3. Read the top chunks.
4. State that the search was keyword-only.

Do not claim semantic recall you did not run.

# Layer 3 — graph

For "who knows who", "who works at X", "what connects A and B", and "what attended this meeting":

```bash
rg -n '\[\[people/jane-doe' "$KB_ROOT" --glob '*.md'
rg -n '\[\[companies/acme' "$KB_ROOT" --glob '*.md'
```

With gbrain:

```bash
gbrain graph-query people/jane-doe --depth 2 --direction both
gbrain graph-query companies/acme --type works_at --direction in
```

Typed relationships live in frontmatter or See Also sections. Search for the verb (`works_at`, `founded`, `invested_in`, `advises`, `attended`, `mentions`, `source`).

# Ranking

When multiple pages match:

1. Exact title or slug match
2. Recent `updated_at`
3. Entity pages over mentions
4. Decision records and meeting notes over summaries
5. `originals/` for the raw source, not for the current decision

Show the ranking signal to the user when it changes the answer ("the most recent note says...").

# Token budget

Search returns chunks; full pages can be large.

| Step | Budget |
|---|---|
| Search results | 10–20 hits |
| Chunks read | 3–5 |
| Full pages loaded | 0–2 |
| Final answer | 1–3 paragraphs plus evidence |

Load a full page only when:

- the chunk confirms relevance
- the question needs the complete timeline or compiled truth
- the user explicitly asks for the full page

# Query templates

| Question | Queries |
|---|---|
| Who is X? | `"X"`, `--type person`, `[[people/x]]` inbound |
| What do we know about Y? | `"Y"`, related concepts, recent pages |
| Why did we choose Z? | decision, chose, approved, meeting date |
| What changed? | `updated_at`, recent meetings, changelog |
| What is blocked? | blocked, waiting, open question, action item |
| Who works at Acme? | `works_at`, `[[companies/acme]]` inbound |
| What did we promise? | promised, committed, deadline, due |

# When search fails

1. Confirm `$KB_ROOT` is correct.
2. Search a single distinctive word.
3. Search filenames: `rg --files "$KB_ROOT" | rg -i "pricing"`.
4. List types: `rg -l '^type:' "$KB_ROOT" --glob '*.md' | wc -l`.
5. Try the graph layer.
6. If the base truly has nothing, state the gap. Do not invent an answer.

# Output

Keep the raw hits available for evidence:

```text
people/jane-doe.md:12: Jane is CTO of Acme.
meetings/2026-05-21-pricing-review.md:28: Decided: test annual-only.
```

Cite the file and section in the final answer, not the raw line number alone.
