# Routing

Default to `inbox/` unless the input clearly belongs somewhere else. Filing is cheap; losing the raw thought is not.

# Destination tree

```
$KB_ROOT/
├── inbox/                  # unprocessed captures, triage weekly
├── originals/              # raw articles, documents, source material
├── meetings/               # one folder per meeting
├── people/                 # person pages
├── companies/              # company pages
├── concepts/               # durable ideas and definitions
├── ideas/                  # product/experiment ideas
├── personal/               # reflections, private notes
├── voice-notes/            # verbatim transcripts
├── projects/               # project-scoped notes
└── archive/                # cold storage, still searchable
```

# Input → destination

| Input | Destination | Notes |
|---|---|---|
| Short thought, no context | `inbox/` | Triage later |
| Link with article text | `originals/` | Keep raw text, add source metadata, summarize separately |
| Link without text | `inbox/` | Fetch and enrich before filing |
| Meeting transcript | `meetings/YYYY-MM-DD-<slug>/` | Capture transcript, then extract attendees/decisions/actions |
| Voice note | `voice-notes/` | Preserve verbatim; summary goes in a separate section |
| Person fact | `people/<slug>/` | Backlink from every page that mentions them |
| Company fact | `companies/<slug>/` | Same |
| Durable concept | `concepts/` | Define once; link from related pages |
| Product/experiment idea | `ideas/` | Include the problem and the test |
| Personal reflection | `personal/` | Private by default; check before sharing |
| Raw file/binary | `originals/<slug>/` | Store the file or a pointer; add a text description |
| Bulk archive | `archive/` | Filter for the user's own writing and high-value content |

# Routing rules

1. **Raw before summary.** Store the source, then add synthesis.
2. **One primary subject per page.** If a capture covers three topics, split it or file it in `inbox/` for triage.
3. **Entity mentions create links.** A page that names a person or company needs a backlink from that entity page.
4. **Do not over-file.** A capture with no clear subject belongs in `inbox/`.
5. **Do not invent structure.** Use the existing folders; propose a new one only when at least ten pages share the shape.
6. **Private stays private.** `personal/` and anything with personal data must not be published or shared by default.

# Triage checklist (weekly)

- [ ] `inbox/` is empty or every item has a decision
- [ ] New entity pages have at least one inbound link
- [ ] Meetings have attendees, decisions, and action items
- [ ] Articles have source, author, and date
- [ ] Voice notes are verbatim
- [ ] No secrets or production personal data

# Examples

```bash
# A thought
bash scripts/capture.sh "Try annual-only pricing first."

# An article
bash scripts/capture.sh --file article.txt --slug originals/2026-05-21-postgres-vs-sqlite \
  --source "https://example.com/postgres-vs-sqlite" --type article

# A meeting
bash scripts/capture.sh --file transcript.txt --type meeting \
  --slug meetings/2026-05-21-pricing-review --title "Pricing review"

# A voice note
bash scripts/capture.sh --file voice.txt --type voice-note \
  --slug voice-notes/2026-05-21-pricing-idea --title "Pricing idea"
```
