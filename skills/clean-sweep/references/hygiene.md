# Clean-Sweep — commit & secret hygiene

The rules every worker (builder, integrator, reviewer, merge) must follow. Baked into every
preamble; also referenced from SKILL.md.

## Commit hygiene (non-negotiable)

Every commit in the entire run is authored **`{{MAINTAINER}}` with NO trailers** — no
`Co-authored-by`, no `Generated-with`, no agent/tool trailers. Bot-pushed commits (BugBot
autofix, etc.) violate this by default: integrators **rebase to reset author + strip trailers
across all commits** before merge. **Never squash** — preserving individual commits is a hard
requirement. Do not rewrite pre-existing history commits that already carry trailers
(destructive, out of scope) — note them as inherited and move on.

The `gh pr merge --merge` merge commit is authored server-side with the GitHub account's
display name/email, which may differ from `git config user.email`. This is **unforceable**
without switching to a local `git merge --no-ff` + push. Treat the account identity as the
accepted maintainer identity — see `learnings.md` #22. Only branch-commit author/trailer
hygiene is enforceable.

## Secret hygiene

Run a secret scanner (`gitleaks`, if installed — see the Optional compatibility note)
**scoped to the branch diff** (`--log-opts origin/{{BASE}}..HEAD`), not full history —
pre-existing history hits are adjudicated once (placeholders / research data / docs are
non-live) and allowlisted via a config file, not re-litigated per PR.

Never commit real secrets; never echo secret values into PR bodies or comments (public IDs +
`file:line` only).

The run needs NO live secrets. If the user offers any (production API keys/tokens), decline
them — workers operate on code + tests + a LOCAL throwaway DB. If secrets nonetheless
transited the chat, advise the user to rotate them.
