# Skills audit — 2026-07-08

Full review of all 7 skills against `docs/skill-anatomy.md`, `AGENTS.md`, and script correctness.
Validator: `python3 scripts/validate-skills.py` → all 7 pass (before and after fixes).

## Verdict

Structurally healthy: every skill has valid frontmatter, `README.md`, and resolving `SKILL.md` asset refs. No hardcoded secrets. Several real script bugs and doc drifts were found and fixed in this pass.

## Fixed in this PR

| Severity | Finding | Fix |
|---|---|---|
| Critical | `cutover-dns.sh` reported success even when `/health` never returned 200 | Fail with exit 1 after printing rollback command |
| High | `setHosts.py` upserted only on `(name, type, address)` — retargeting a CNAME duplicated records | Upsert on `(name, type)` |
| High | `rollback.sh` only checked `Status="OK"`, weaker than `migrate.sh flip` | Require `Updated="true"` when the attribute is present |
| High | `migrate.sh step_create` account lookup had no success/empty-result guard | `cf_assert_success` + empty-accounts abort |
| Medium | `verify-parity.sh` depended on undeclared `bc` | Compare with `python3` |
| Medium | DNS skills lacked SKILL-level “When NOT to use” | Added to `cloudflare-dns` + `namecheap-dns` |
| Medium | `clean-sweep` missing `license` / metadata / `allowed-tools` | Aligned with peers |
| Medium | Top-level README hero + Try-it omitted workflow skills | Updated; AGENTS Orca note; CONTRIBUTING README required |
| Low | Install docs used `cp -R`; integrator preflight path assumed repo checkout | Symlink install; path-agnostic preflight note |
| Low | Doc drift (CLAUDE structure blurb, deep-research file tree, author `@` prefix, Pairs with) | Corrected |

## Remaining / deferred (not blocking)

| Severity | Finding | Why deferred |
|---|---|---|
| High | Terraform templates: hardcoded container port 3000; `primary_domain` required with no default; `cloudflare-cache.tf` depends on `static-sites.tf` locals | Template coupling is documented in migration phases; needs a dedicated Terraform pass |
| Medium | `deep-research` banner visually labels MONID as an 8th source (auth/router in code) | **Fixed** in follow-up: MONID is center router; 8 cards are real sources |
| Medium | `spawn_worker.sh` swallows Orca dispatch failures (`\|\| true`) | Intentional retry/heartbeat pattern; tighten carefully |
| Medium | `make-poster.sh` installs `yq` from GitHub `latest` without checksum | Documented convenience path |
| Low | `fly-restrict-origin.md` lives under `scripts/` | Harmless; move to `references/` in a cleanup PR |
| Low | `terminal-poster` README Live Examples gallery shows 3 of 7 renders | Full set in `references/worked-examples.md` |
| Info | `clean-sweep` / `spec-to-ship` hard-depend on external Orca `orchestration` skill (not in this repo) | Now surfaced in AGENTS intent table + skill compatibility |

## Per-skill snapshot

| Skill | Spec | Banner | Scripts | Notes |
|---|---|---|---|---|
| `cloudflare-dns` | ✅ | ✅ jpg | ✅ | When NOT added; rollback + migrate hardened |
| `namecheap-dns` | ✅ | ✅ jpg | ✅ | Upsert bug fixed; When NOT added |
| `fly-to-aws-migration` | ✅ | ✅ png | ✅ | Cutover verify + parity `bc` fixed |
| `deep-research` | ✅ | ✅ jpg | ✅ | File tree + Pairs with; banner MONID label deferred |
| `terminal-poster` | ✅ | exception (examples) | ✅ | Pairs with added |
| `clean-sweep` | ✅ | exception (coordinator) | ✅ | Frontmatter + install + Pairs with |
| `spec-to-ship` | ✅ | exception (coordinator) | n/a | `allowed-tools` + author + symlink install |

## Security skim

- No hardcoded API keys/tokens in skill scripts.
- Auth via env vars at runtime across DNS, research, poster, migration.
- Intentional secret-adjacent disk writes remain documented: Origin CA keys in `.dns-state/`, migration dumps under `/tmp` / `.migration/`.
