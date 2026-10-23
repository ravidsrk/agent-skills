# Specialized ingestion

Each input type has a different contract. Keep the raw source; add synthesis in a separate section.

# Articles and links

1. Fetch the readable text, not the navigation chrome.
2. Preserve the title, author, publication, and canonical URL.
3. Store the raw text under `originals/`.
4. Add a summary section above the raw text.
5. Extract named entities and link their pages.
6. Record `provenance: external`.

```yaml
---
title: "Postgres vs SQLite"
type: "article"
slug: "originals/2026-05-21-postgres-vs-sqlite"
source: "https://example.com/postgres-vs-sqlite"
author: "Jane Doe"
published_at: "2026-05-01"
provenance: "external"
content_hash: "..."
---
```

Do not replace the source with a summary. If the link dies, the raw text is the only evidence.

# Meetings

1. Capture the transcript verbatim.
2. Extract attendees and link their person pages.
3. Extract decisions (what was decided, by whom).
4. Extract action items (owner, due date, status).
5. Extract open questions.
6. Link the meeting from each attendee page.

```md
# Pricing review — 2026-05-21

## Attendees
- [[people/jane-doe|Jane Doe]]
- [[people/sam-lee|Sam Lee]]

## Decisions
- Test annual-only pricing for new signups.

## Action items
- [ ] Jane: draft the experiment brief by 2026-05-28.
- [ ] Sam: instrument the signup funnel.

## Open questions
- Does annual-only hurt monthly retention?
```

# Voice notes

- Preserve exact phrasing. Do not paraphrase the transcript.
- Mark uncertain words with `[?]` rather than guessing.
- Put a cleaned summary in a separate section.
- Keep the audio file or a stable pointer in `originals/`.
- Record the duration and source device if known.
- Set `type: voice-note`.

# Media (images, video, PDFs)

- Store the file or a stable pointer under `originals/<slug>/`.
- Add a text description, dimensions/duration, and source.
- Do not rely on the file name as the title.
- For screenshots, record the viewport and the URL.
- For video, record the encoded dimensions and duration, not the requested viewport.

# Meeting transcripts from a recorder

- Keep speaker labels.
- Do not merge speakers.
- Keep timestamps if they help trace a decision.
- Redact sensitive personal data before sharing.

# Archives

Bulk archives (Dropbox, Drive, email takeout, old hard drives) are not a capture: they are a filtering problem.

1. Inventory file types and date ranges.
2. Filter for the user's own writing, ideas, and relationships.
3. Skip duplicates and generated files.
4. Capture the high-value subset.
5. Leave the rest in cold storage with an index page.

Do not loop `capture.sh` over thousands of files; use a batch importer that writes pages and reports counts, or capture only the subset worth keeping.

# Redaction

Before capture:

- remove secrets, tokens, passwords, and API keys
- redact production personal data
- replace real customer names with fictional ones in examples
- do not capture a screen recording that shows another app or terminal with credentials
