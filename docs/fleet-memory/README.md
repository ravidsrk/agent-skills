# Fleet memory store

Append-only JSONL consumed by the [`fleet-memory`](../../skills/fleet-memory/SKILL.md) skill.

| File | Role |
|------|------|
| `learnings.jsonl` | One learning object per line (`status`, `confidence` 1–10, `fleet`, optional `tags`) |
| `specialist-stats.jsonl` | One line per review dispatch (`specialist` = canonical id) |

Create-on-first-write is fine if these files are missing in a consumer repo; this pack
seeds empty files so the path convention is checked in. **Commit the store with the run**
(no secrets — evidence pointers only).
