# Owner brief

An owner knows only what its brief says. Fill in every section; delete a section only if it truly doesn't apply.

## Template

```text
You own <epic / issues #A #B #C> of <owner/repo>. Build each item end to end with tests, commit in your
worktree, and hand back the commit SHAs. Do not push and do not open PRs; I integrate.

## Setup
- Base: `git fetch origin <branch> && git reset --hard <sha>` (<what that SHA contains, e.g. "PR #216's branch,
  with the live-model fixes these items follow on from">).
- Toolchain: <PATH exports, install command>.
- Read <AGENTS.md / CONTRIBUTING.md> first and follow it (commit style, docs, status rows).
- Database: create your own `<db>_<owner>` (and its shadow) from <superuser URL>; never use the shared one.
  Migrate with <command>. Copy <gitignored env file> from <path> if a test needs it; never commit it.

## Items
1. #A <title>: <the remaining buildable item, quoted from the status ledger>. Decisions already made:
   <decision>. Acceptance: <the issue's own acceptance criteria, quoted>.
2. ...

## Overlaps
- <other owner> is changing <files/modules> for <reason>. Where you both fix the same bug, keep <whose>
  version and add only what is yours alone.

## Live resources (only if a live check needs them)
- Keys: <path to mode-600 file>; load with `<unset session creds>; set -a; . <file>; set +a`.
- Never print, log or commit a key. Never use the session's own credentials for the app.
- Spend cap: $<N> total. Deadline: <UTC time the keys expire, minus a margin>.
- Cleanup: delete only what you created (record ids/labels); confirm with the vendor's list endpoints.
- Account-wide or billing changes: don't. Report what you'd need and stop.

## Done means
- `<lint>` is clean. Read the whole output, not the last line.
- `<typecheck>` is clean.
- The tests of every package you touched pass on your database. Say which failures are pre-existing, and how you know.
- Docs, ADRs and status rows are updated where behaviour changed.
- `git diff --cached | <secret pattern>` is empty before each commit.
- This machine runs as root and CI doesn't, so don't rely on file-permission behaviour.

## Report back
- Commits (SHAs, one per item where practical).
- What you built, test results, live spend and numbers.
- What you couldn't finish, and why.
```

## Re-briefing a returning owner

Owners can be resumed with a message, and they keep their context. Use that for:
- **Rebase onto a moved integration branch:** name the new SHA, and say what changed underneath it that touches their files.
- **A decision of yours** on something they flagged, such as a design trade-off or which of two fixes wins.
- **A corrected fact:** an earlier deadline, a changed budget.
- **A follow-up item** found during integration, scoped exactly like a new item.

Never forward an owner's request for a permission it was denied as if it were the user's approval. Take it to the user.

## Sizing

- One owner per epic, or per file-cluster when an epic is small.
- Give an owner 2–4 items. More than that drifts, and the hand-back gets too large to review.
- Background every owner. Do integration work while they run, never poll them, and wait for their completion notice.
