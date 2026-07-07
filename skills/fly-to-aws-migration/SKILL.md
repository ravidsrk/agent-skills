---
name: fly-to-aws-migration
description: End-to-end playbook for migrating a Fly.io project to AWS — handles Fly Postgres → Aurora Serverless v2, Fly Machines → ECS Fargate, Fly static sites → S3+CloudFront, secrets migration via Secrets Manager, DNS cutover via Cloudflare. Use when the user says "migrate from Fly to AWS", "move my Fly app to AWS", "leave Fly", "AWS migration", "ECS migration", "switch to AWS", or pastes a Fly project structure (apps/, fly.toml files) and asks to move it. Covers 7 phases (audit → foundation → code prep → secrets → API cutover → static sites → cache layer), with rollback paths preserved at every step. Battle-tested on a production migration (2026) — migrated API + 2 static sites + 87-table Postgres with 9 min total downtime.
license: MIT
compatibility: Requires flyctl, aws v2, terraform >=1.5, docker, psql/pg_dump/pg_restore, jq. Env vars: AWS_PROFILE, FLY_API_TOKEN, CLOUDFLARE_API_TOKEN (scoped token — global API key is deprecated), CLOUDFLARE_ZONE_ID.
metadata:
  version: "1.1.0"
  author: "@ravidsrk"
allowed-tools: Bash Read Write Edit
---

# Fly.io → AWS Migration Playbook

This skill turns "I want to leave Fly for AWS" into a 7-phase, ~6-hour migration that ships in 5 PRs with every state-bearing component verified for parity and full rollback preserved.

# When to use

User says any of:
- "migrate from Fly to AWS" / "move to AWS" / "leave Fly"
- "AWS migration" / "ECS migration"
- Pastes a Fly project structure (`apps/api/fly.toml`, `apps/web/fly.toml`, etc.) and asks to host on AWS
- Has $X K of AWS credits and wants to use them
- Mentions cost concerns about Fly Machines pricing
- Wants Fly Postgres → managed AWS DB (Aurora / RDS)

**Do NOT use this skill for:**
- AWS → Fly (reverse direction)
- Single-process Fly apps that need only a single Lambda or static site (overkill)
- Apps with hard real-time / sub-5ms latency requirements (AWS adds ~10ms vs Fly's edge)

# Core philosophy: phased + reversible

🔴 **Never destroy a Fly resource until its AWS replacement has served real production traffic for ≥24h.**

🔴 **Every phase must be independently mergeable and rollback-able.** If the user pauses for a week between Phase 3 and Phase 4, nothing breaks.

🟢 **DNS is the cutover point**, not infrastructure. Build everything in parallel, flip DNS last.

# The 7 phases

| Phase | Goal | PR | Duration |
|---|---|---|---|
| 0 | Audit current Fly setup | none | 15 min |
| 1 | Foundation IaC (VPC, IAM, Aurora, ECR, ALB) | PR #1 | 60-90 min |
| 2 | Code prep (Dockerfile fixes, ECR push workflow) | PR #2 | 30 min |
| 3 | Secrets + **schema-only** DB migration | PR #3 | 30-60 min |
| 4+5 | API production cutover — data delta + DNS flip | PR #4 | 30 min wall, ≤9 min user-facing downtime |
| 6 | Static sites cutover | PR #5 | zero downtime |
| 7 | Perf tuning (Cloudflare cache layer) | PR #6 | optional |

🟢 **Phase 3 = schema only, Phase 4 = data delta.** This is the recommended strategy end to end (SKILL, README, phases.md, `scripts/db-migrate.sh`). Doing the full data dump in Phase 3 is documented in phases.md as an **Alternative** — it collapses two phases into one but blows the ≤9 min downtime budget on any DB larger than a few hundred MB.

Read `references/phases.md` for the detailed step-by-step. Read `references/gotchas.md` BEFORE running any phase — 23 traps documented, each with symptom → root cause → fix, most cost real time on a production migration.

# Critical inputs to collect before starting

Ask the user upfront:

1. 🔴 **AWS account ID** + which region they want (`ap-southeast-1` for SEA, `us-east-1` for US, `eu-west-1` for EU)
2. 🔴 **Cloudflare zone ID** (where DNS lives) + **scoped API token** (`CLOUDFLARE_API_TOKEN`, `Zone:DNS:Edit` + `Zone:Cache Purge`). The legacy Global API Key still works but is discouraged — the templates default to `api_token`.
3. 🔴 **List of Fly apps** to migrate — `flyctl apps list`
4. 🔴 **Database size** — `flyctl postgres connect -a <db> -c "SELECT pg_size_pretty(pg_database_size(current_database()))"`
5. 🔴 **Maintenance window** — when can we tolerate ~10 min API downtime?
6. 🟡 **Available AWS credits** — informs Aurora ACU sizing and ECS task count
7. 🟡 **Is `apps/api/Dockerfile` set to listen on `process.env.PORT` or a hardcoded port?** (Phase 2 fix needed if hardcoded)

# Workflow at a glance

```
Phase 0  → flyctl apps list, flyctl machines list, fly pg connect, du -sh state
Phase 1  → CAA preflight (dig CAA — Amazon must be authorized)
            → terraform apply foundation (VPC, IAM, Aurora, ECR, ALB, ACM)
            └─ outputs: aurora endpoint, ECR URI, ALB DNS, github_deploy role ARN
Phase 2  → fix Dockerfile if needed, add ECR push workflow, push :latest
Phase 3  → SCHEMA-ONLY dump from Fly → restore to Aurora (no data yet)
            └─ migrate flyctl secrets → AWS Secrets Manager (8 secret groups by category)
Phase 4+5 → pre-warm ECS with an idle Aurora connection → freeze Fly writes →
            data-only delta dump/restore → ECS force-new-deployment → wait healthy →
            flip Cloudflare CNAME api.* → ALB
Phase 6  → S3 + CloudFront for static sites (web + docs)
            └─ npm build → aws s3 sync → flip DNS
Phase 7  → Cloudflare Tiered Cache + cache rule for HTML (~4.6x TTFB win: 300ms→65ms, $0/mo)
```

# Decision matrix: which AWS services per Fly component

| Fly component | AWS replacement | Reasoning |
|---|---|---|
| 🟢 Fly Machines (Node/Bun API) | ECS Fargate | Closest to "container, no servers". Lambda only if request rate <1/s. |
| 🟢 Fly Postgres | Aurora Serverless v2 | Auto-scaling, ACU range 0.5-4. Use RDS Postgres for fixed sizing >1k req/s. |
| 🟢 Fly static sites | S3 + CloudFront + Cloudflare | Single ACM cert in us-east-1, CloudFront function for URI rewrite |
| 🟢 Fly secrets | AWS Secrets Manager (grouped) | Group secrets by category (db, llm, social, email, etc.) — fewer secrets = less cost |
| 🟢 Fly volumes | EFS or S3 | EFS for write-heavy, S3 for read-mostly or backups |
| 🟢 Fly logs | CloudWatch Logs | 30-day retention default |
| 🟢 Fly internal networking | VPC with private subnets + NAT | Don't put services in public subnets |
| 🟢 Fly Cron | EventBridge Scheduler → ECS RunTask | OR keep singleton task in ECS with internal cron |
| 🟡 Fly health checks | ALB target group health checks | 30s interval, 5s timeout, 2 healthy / 3 unhealthy |
| 🔴 Fly Anycast IPs | Cloudflare proxied DNS | AWS doesn't have anycast; rely on Cloudflare edge instead |

# Hard-won lessons (READ THESE)

🔴 **`bun run build` hangs on Next.js 16 in CI.** Use `npm run build` in CI workflows. Local dev with bun is fine.

🔴 **Fumadocs + Shiki needs ≥4 GB heap.** Set `NODE_OPTIONS=--max-old-space-size=4096` for docs builds.

🔴 **CloudFront cert MUST be in us-east-1.** Even if your stack is in another region. Add a second provider alias for that one cert.

🔴 **Bun + Prisma WASM crash class.** Same Bun version + same Prisma version + different app code can JIT-compile into a bad state that crashes ONLY on production singleton background tasks. The `/health` endpoint passes; signals stop writing. See `references/gotchas.md` for the 5-min post-deploy DB-write check.

🔴 **Cloudflare ruleset entrypoints MUST be named `"default"`.** Setting any other name forces destroy/recreate.

🔴 **`cloudflare_argo` resource requires paid Argo subscription.** Use `cloudflare_tiered_cache` resource for the free tiered-cache feature.

🔴 **Aurora Serverless v2 starts at 0.5 ACU minimum** (currently — was 0 in newer regions). $58/mo floor regardless of usage. Use provisioned instance class for low-traffic apps if cost matters more than auto-scale.

🟡 **Cloudflare proxied DNS = instant propagation** (no TTL wait). This is the secret to <10s cutover windows.

🟡 **ECS task `:latest` does NOT auto-update.** You need `aws ecs update-service --force-new-deployment` to pick up new images even with `:latest` tag.

🟡 **Migrate role permissions cap at runtime.** If migrate task uses task-execution-role only, it can't read Secrets Manager. Use task-role for runtime AWS access.

🟢 **Cloudflare DNS API is faster than terraform apply** for the cutover moment itself. Pre-build everything in TF, do the actual DNS flip via `curl` API call for atomic <1s cutover.

# Reference files

- `references/phases.md` — Every phase with exact commands, AWS resource counts, verification steps
- `references/gotchas.md` — Every trap with symptom → root cause → fix
- `references/cost-model.md` — Real pricing from a production migration (Singapore region, ~$667/mo as-built, ~$291/mo right-sized)
- `references/rollback.md` — Per-phase rollback procedures (each <5 min)

# Templates

- `templates/terraform/` — Reusable Terraform modules (VPC, Aurora, ECS, ALB, S3+CF static sites)
- `templates/github-workflows/` — Deploy workflows (API to ECS, static sites to S3)

Common Fly → AWS Dockerfile patches (respect `$PORT`, drop Fly-only env, avoid Bun in CI builder) are inlined in [`references/phases.md`](references/phases.md) → Phase 2.

# Scripts

- `scripts/audit-fly.sh` — Run Phase 0 audit against a Fly account
- `scripts/db-migrate.sh` — pg_dump from Fly + restore to Aurora with real per-table COUNT(\*) parity. Modes: `--schema-only` (default, Phase 3), `--data-only` (Phase 4 delta), `--full` (alternative single-shot)
- `scripts/secrets-migrate.sh` — Map `flyctl secrets` → 8 grouped AWS Secrets Manager entries. `--dry-run` (default) prints the mapping; `--apply` writes it
- `scripts/cutover-dns.sh` — Atomic DNS flip via Cloudflare API (scoped token; verifies proxied)
- `scripts/verify-parity.sh` — Compare Fly vs AWS production responses for drift (single request per side)

# How to use this skill

1. Read this SKILL.md
2. Read `references/phases.md` for the phase you're on
3. Read `references/gotchas.md` ENTIRELY before starting — most traps cost 30-60 min to diagnose
4. Use `templates/` as starting points, not copy-paste-final
5. After each phase, verify per `references/phases.md` before moving on
6. After cutover, run `scripts/verify-parity.sh` for at least 24h before destroying Fly resources

# Reference: production migration scorecard

Migrated 2026-05-22. Single project, 1 API + 2 static sites + 87-table Postgres.

| Phase | Resources | Wall time | Issues |
|---|---|---|---|
| 0 | inventory | 15 min | none |
| 1 | 84 AWS resources (VPC, Aurora, ALB, ECR, IAM, Secrets) | 90 min | 6 VPC endpoints × 3 AZ accidentally → $171/mo (right-size later) |
| 2 | Dockerfile fix + ECR push workflow | 30 min | bun + Next.js 16 build hang (workaround: npm) |
| 3 | 87 tables + 8 secret groups | 45 min | flyctl pg_dump SSL cert issue (use --ignore-ssl-errors flag) |
| 4+5 | API cutover with 9 min downtime | 30 min | scheduler singleton not migrating cleanly — needed PRIMARY_MACHINE_ID env var |
| 6 | 2 static sites (S3 + CloudFront) | 60 min | bun build hang again, Fumadocs OOM at 2GB |
| 7 | Cloudflare cache layer | 20 min | cloudflare_argo deprecated + paid; use cloudflare_tiered_cache |
| **Total** | **~115 AWS resources** | **~5 hours** | **All recovered, no data loss** |

Production state post-migration:
- 🟢 API: 104ms p50 TTFB (was ~500ms on Fly)
- 🟢 Static sites: 65ms p50 TTFB (was ~300ms on Fly with CDN)
- 🟢 Database: identical row counts, parity verified via `verify-parity.sh`
- 🟡 Cost: $667/mo as-built (Fly was ~$150/mo). Right-sized to ~$291/mo possible (see `references/cost-model.md` for the itemized breakdown).

# Final reminder

🔴 **The user's data is on Fly. Treat the migration as a backup/restore with DNS in the middle, not a "lift and shift."** Always have the option to flip DNS back. Always.
