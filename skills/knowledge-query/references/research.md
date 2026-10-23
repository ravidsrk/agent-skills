# Research and synthesis

Use the knowledge base first, then external sources for what it cannot answer. The output should make "what is new" obvious.

# Brain-augmented research

1. Query the base for the topic, entities, and prior decisions.
2. Summarize what is already known, with citations.
3. Identify the specific gaps.
4. Fetch external sources only for those gaps.
5. Label external facts and dates.
6. Return a "new vs known" split.

```md
## What the base already knew
- ... [Source: concepts/pricing, updated 2026-04-01]

## What is new
- ... [Source: https://example.com/report, published 2026-05-01]

## What remains unknown
- ...
```

# Academic verification

When a claim cites a paper or study, trace it:

1. Find the publication (DOI, venue, year).
2. Read the methodology, not just the abstract.
3. Check the sample, controls, and effect size.
4. Look for independent replication.
5. Separate the paper's claim from the press release's claim.

Output:

```md
Claim: ...
Paper: ...
Method: ...
Sample: ...
Replication: ...
Verdict: supported / partially supported / unsupported / cannot verify
```

Do not treat a single preprint as settled science.

# Strategic reading

Read a book, article, transcript, or case study through a specific problem:

1. State the problem and the decision you are trying to make.
2. Extract only the passages that bear on it.
3. Map each idea to an action or a test.
4. Note where the source disagrees with the base.
5. Produce an applied playbook, not a summary.

```md
## Problem
...

## What the source says
- Idea — quote/page — implication

## What we should do
- Action — why — how to verify

## What does not transfer
- ...
```

# Book mirror

For a full book:

1. Preserve the chapter structure.
2. Summarize each chapter in the left column.
3. Map each idea to the user's projects, decisions, or open questions in the right column.
4. Mark chapters with no application.
5. Keep quotes short and attributed.

Do not replace the book with a generic summary; the value is the mapping to the user's context.

# Concept synthesis

When the base has many raw stubs on one topic:

1. Cluster by meaning, not filename.
2. Identify the canonical definition.
3. Trace how the idea evolved across sources.
4. Tier it: T1 canon, T2 established, T3 working, T4 riff.
5. Merge duplicates; keep aliases.
6. Link every cluster to its sources.

Output a map, not a pile:

```md
## T1 — Canon
- Concept — definition — sources

## T2 — Established
- ...

## T3 — Working
- ...

## T4 — Riff
- ...
```

# External source rules

- Cite URL, author, and publication date.
- Distinguish primary sources from commentary.
- Note paywalls, dead links, and inaccessible data.
- Do not copy long passages; summarize and quote briefly.
- Capture the source into the knowledge base if it will be reused.
- Label `provenance: external`.

# What not to do

- Do not answer from the model's memory when the base has relevant pages.
- Do not present a single source as consensus.
- Do not hide a conflict between the base and an external source.
- Do not synthesize a book or paper you did not read.
- Do not let external research overwrite the user's own notes.
