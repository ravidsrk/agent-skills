# Briefing

A daily briefing is a read-only query with a fixed shape. It answers: what changed, who is in play, what is due, and what is stale.

# Output template

```md
DAILY BRIEFING — YYYY-MM-DD

## Brain pulse
- Contradictions resolved overnight: ...
- New facts since the last briefing: ...
- Pending consolidation: N facts

## Today's meetings
- HH:MM — Meeting name
  - Attendee — [Source: people/slug, updated DATE]
  - Context: one line

## Active projects / deals
- Project — status, deadline
  - Recent: [Source: ...]

## Action items
- [ ] Item — owner, due date [Source: ...]

## Recent changes (24h)
- `slug` — what changed

## People in play
- Name — why they are active

## Stale or missing
- `slug` — stale since DATE; relevant because ...
- Gap: no page for ...

## Suggested focus
1. ...
2. ...
```

# Query list

Run these before composing the briefing:

```bash
# New or changed pages
rg -l 'updated_at:' "$KB_ROOT" --glob '*.md'

# Meetings today
bash scripts/search.sh "$(date -u +%Y-%m-%d)" --type meeting

# Open action items
rg -n '\[ \]' "$KB_ROOT" --glob '*.md'

# Active projects
rg -n '^status:[[:space:]]*"?active"?[[:space:]]*$' "$KB_ROOT" --glob '*.md'

# People recently mentioned
bash scripts/search.sh "met" --limit 20
```

With gbrain:

```bash
gbrain recall --since-last-run --supersessions --pending --rollup --json
gbrain query "active deals status"
gbrain query "meetings this week"
gbrain query "pending commitments follow-ups"
gbrain search --type person --sort updated --limit 10
```

# Rules

- **Read-only by default.** Do not create or update pages while composing a briefing unless the user asks.
- **Cite every fact.** A briefing is not a summary from memory.
- **Name the gap.** If an attendee has no page, say so.
- **Be short.** One line per item; the user can drill in.
- **Lead with what changed**, not with a recap of everything.
- **Flag stale context** instead of presenting it as current.

# Before a meeting

For each attendee:

```bash
bash scripts/search.sh "Attendee Name" --type person
```

Read their page and recent timeline. If no page exists:

```md
Gap: no page for Sarah Chen. Consider capturing her role and last interaction.
```

# Before an email reply

1. Search the sender.
2. Read their page and recent timeline.
3. Cite the last interaction in your reply.
4. Do not invent shared history.

# After the briefing

Offer the next actions:

- capture a missing person/company page
- reconcile a conflict
- schedule the follow-up
- triage `inbox/`

# Failure modes

| Symptom | Cause | Fix |
|---|---|---|
| Briefing is a wall of text | No ranking | One line per item; lead with changes |
| Facts have no citations | Composed from memory | Re-run the queries |
| Stale pages look current | No freshness check | Flag pages older than 90 days |
| Missing attendee context is silent | Gap not stated | Name the missing page |
| Same items every day | No diff against the last briefing | Track `since-last-run` or a local cursor |
