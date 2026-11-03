# Issue hygiene

## The status ledger

Keep one markdown table in the repo, for example `docs/plan/status.md`, with a row per open issue:

```markdown
| Issue | State | Remaining buildable | Blocked on |
|---|---|---|---|
| #42 E3.5 Bitbucket † | blocked | — (what landed, briefly) | Contract run on recordings from a Bitbucket workspace (#206) |
```

- **State:** `partial`, `blocked`, `done (in review)` or `done (on merge)`.
- **Remaining buildable** is the owner's work list. A `—` means code-complete.
- **Blocked on** names the outside resource and its tracker issue.
- **`†`** marks a row changed since the last audit.
- Owners update their own rows, and `merge_rows.py` merges row edits by key.

## When to close an issue

Close it when **Remaining buildable** is `—`, every acceptance criterion that code can meet is met, and the rest is moved to a tracker. Don't close an issue with buildable work left. Build it, or assign it.

The closing comment says:
- what landed (the PR, with numbers for live results);
- where each remaining live check is tracked (`#204`, `#206`).

## Tracker issues

Group outside-resource checks by the resource they need, not by epic:

| Tracker | Holds |
|---|---|
| Test org / staging | Checks that need a deployed service and real installs (GitHub App, webhooks) |
| Datasets and labels | Bars measured on public benchmarks, recorded corpora or human labels |
| Third-party accounts | Vendor accounts, paid plans, registries, partners, compliance |

Each tracker is a checklist: `- [ ] #N: <check>; needs <resource>`. Tick items as they're met, with a pointer to the PR or doc that has the result. When the user provides a resource (a key, an account, a decision), update the tracker the same hour.

## Epics

- An epic closes when every sub-issue is closed, whether completed or not-planned, each with its reason.
- Check sub-issues with the GitHub API rather than memory; a late PR changes the answer.
- The closing comment names the last sub-issues to close, and any phase-exit criteria that live in trackers.

## Audits

Every few PRs, check each open issue against merged code:
- **Done but still open:** close it with a comment.
- **Ledger wrong:** fix the row.
- **Missing work:** assign an owner.

Parallel read-only agents can audit about 20 issues each.
