# fly-to-aws-migration

**End-to-end playbook for migrating a Fly.io project to AWS.** Seven phases, five PRs, ~6 hours of work, full rollback preserved at every step.

🟢 **Coverage:** Fly Postgres → Aurora Serverless v2, Fly Machines → ECS Fargate, Fly static sites → S3+CloudFront, secrets → AWS Secrets Manager, DNS cutover → Cloudflare
🟢 **Battle-tested:** API + 2 static sites + 87-table Postgres migrated with **9 min total downtime**
🟢 **Reversible:** every phase can be independently rolled back

# What it does

Most "migrate to AWS" guides assume you're starting from scratch. This skill assumes you have a **live, production Fly.io app** with users, real DB state, custom domains, and CI — and you can't afford a long outage.

It frames the migration as **7 phases, each its own PR**:

| Phase | Goal | PR | Wall time |
|---|---|---|---|
| 0 | Audit current Fly setup | none | 15 min |
| 1 | Foundation IaC (VPC, IAM, Aurora, ECR, ALB) | PR #1 | 60–90 min |
| 2 | Code prep (Dockerfile fixes, ECR push workflow) | PR #2 | 30 min |
| 3 | Secrets + DB schema migration | PR #3 | 30–60 min |
| 4+5 | API production cutover (Fly off, AWS on) | PR #4 | ≤9 min downtime |
| 6 | Static sites cutover | PR #5 | zero downtime |
| 7 | Perf tuning (Cloudflare cache layer) | PR #6 | optional |

🔴 **Core philosophy.** Never destroy a Fly resource until its AWS replacement has served real production traffic for ≥24h. Every phase is independently mergeable. If you pause for a week between Phase 3 and Phase 4, nothing breaks.

🔴 **DNS is the cutover point**, not infrastructure. Everything gets built in parallel; DNS flips last.

# When to use it

The skill's `description` triggers on phrases like:

- *"Migrate from Fly to AWS"* / *"Move my Fly app to AWS"* / *"Leave Fly"*
- *"AWS migration"* / *"ECS migration"*
- *"I have $X K of AWS credits and want to use them"*
- *"Fly Postgres is too expensive"* / *"Fly Machines pricing"*
- *Paste of a `fly.toml` or `apps/api/fly.toml` structure with "host this on AWS"*

🔴 **Do NOT use this skill for:**

- **AWS → Fly** (reverse direction — different problem set)
- Single-process Fly apps that need only a single Lambda or static site (overkill — use SST, Vercel, or `serverless-framework` instead)
- Apps with hard real-time / sub-5ms latency requirements (AWS adds ~10ms vs Fly's edge POPs)

# Install

# 1. Get the skill

```bash
git clone https://github.com/ravidsrk/agent-skills.git
ln -s "$(pwd)/agent-skills/skills/fly-to-aws-migration" ~/.claude/skills/fly-to-aws-migration
# Or your runtime's skill directory
```

# 2. Required tools

You'll need these CLIs on PATH:

| Tool | Why |
|---|---|
| `fly` | Read source state, set NS, eventually destroy resources |
| `aws` (v2) | All AWS provisioning + deploys |
| `terraform` (≥1.5) | IaC for the AWS side (Phase 1) |
| `docker` (or `buildx`) | Building images for ECR (Phase 2) |
| `psql` + `pg_dump` / `pg_restore` | Postgres migration (Phase 3) |
| `jq` | JSON munging across every script |

# 3. Required credentials

```bash
# AWS — use a dedicated IAM user or SSO profile with AdministratorAccess for the migration
export AWS_PROFILE=migration

# Fly — for reading state and the final NS flip / destroy
export FLY_API_TOKEN=...

# Cloudflare — for the DNS cutover (Phase 6)
export CLOUDFLARE_API_KEY=...
```

🔴 **Drop AdministratorAccess to a least-privilege role** once Phase 7 completes. The migration needs it; steady-state doesn't.

# Usage

# Phase 0 — Audit

```bash
cd skills/fly-to-aws-migration
scripts/audit-fly.sh ./.migration/
```

Writes `./.migration/00-audit.md` summarizing every Fly app, machine size, secret name, custom domain, and Postgres cluster. Read it before touching anything else.

# Phase 1 — Foundation IaC

```bash
mkdir -p ./.migration/terraform
cp -r templates/terraform/* ./.migration/terraform/
cd ./.migration/terraform
terraform init && terraform plan && terraform apply
```

Provisions VPC (2 AZs), IAM roles, Aurora Serverless v2 cluster, ECR repo, ALB, and S3+CloudFront for any static sites. **~80+ AWS resources** for a typical web app + DB + 2 static sites.

🔴 **Use `terraform state` from S3 + DynamoDB lock from day 1.** The `main.tf` template has the block commented out — uncomment and configure before the second `terraform apply`.

# Phase 2 — Code prep

Adds a `.github/workflows/deploy-api.yml` that pushes images to ECR. Template at `templates/github-workflows/deploy-api.yml`.

Common Dockerfile fixes for Fly→ECS:
- 🟡 Multi-stage builds with `bun` in dev → must use `npm` in builder stage (Bun image isn't in ECS-friendly base images)
- 🟡 `PORT` env var: Fly assigns it dynamically; ECS task def must hardcode it (typically `3000`)
- 🟡 `internal_port` in `fly.toml` → `containerPort` in ECS task def — these MUST match

# Phase 3 — Secrets + DB schema

```bash
# Export Fly secrets, push into AWS Secrets Manager
scripts/db-migrate.sh your-app-db your-app/prod/db
```

Then **schema-only** migration to Aurora (so Phase 4 just needs a final delta sync):

```bash
fly proxy 5432:5432 -a your-app-db &
pg_dump --schema-only -h localhost -U postgres > schema.sql
psql "postgresql://...aurora..." < schema.sql
```

🔴 **Don't restore data here.** Data sync happens during the Phase 4 cutover window so you don't have to handle dual-writes.

# Phase 4+5 — API cutover

The actual outage window. Run from a checklist:

```
[ ] Fly app set to read-only / maintenance mode
[ ] Final pg_dump --data-only from Fly Postgres
[ ] psql restore --data-only into Aurora (parallel jobs)
[ ] ECS service scale 0 → desired_count
[ ] DNS A record: example.com → ALB DNS name (TTL=60 ahead of time)
[ ] curl health checks against new endpoint
[ ] Smoke test: login, write, read, payment, etc.
[ ] Watch CloudWatch logs for 10 min
[ ] If anything's off → rollback (see references/rollback.md)
```

In production, this phase typically takes **6–9 minutes of actual user-facing downtime** for a small/medium app.

# Phase 6 — Static sites

```bash
scripts/cutover-dns.sh docs.example.com
```

Static sites are simpler — there's no state to migrate. Sync the build artifacts to S3, invalidate CloudFront, flip the CNAME at Cloudflare. **Zero downtime** if you do it in that order.

# Phase 7 — Cache layer (optional)

`templates/terraform/cloudflare-cache.tf` adds an aggressive Cloudflare cache rule that lets CF serve 70%+ of API GET traffic without hitting the ALB. Cuts ECS bill significantly.

# Verifying parity

```bash
scripts/verify-parity.sh https://api.example.com https://your-app.fly.dev /health /api/version /api/me
```

Hits the same endpoints on both old (Fly) and new (AWS) origins side-by-side; flags any non-matching responses. Run this *before* the DNS flip to catch ECS misconfigs while users are still on Fly.

# Cost model

Real numbers from a production migration (Singapore region, 2026):

| Item | As-built | Right-sized |
|---|---|---|
| Aurora Serverless v2 | $215 | $115 |
| ECS Fargate (2 × API + 1 × scheduler) | $185 | $80 |
| ALB | $25 | $25 |
| NAT Gateway × 2 | $90 | $45 (1 AZ) |
| S3 + CloudFront × 2 sites | $35 | $20 |
| Secrets Manager + CloudWatch | $20 | $10 |
| Data transfer | $70 | $35 |
| **Total** | **~$640/mo** | **~$330/mo** |

🟡 **The "right-sized" column is what to target on month 2** after watching real metrics. Most as-built numbers are conservative defaults — actual usage is much lower.

Full breakdown in [`references/cost-model.md`](references/cost-model.md).

# Known gotchas

Critical traps documented in [`references/gotchas.md`](references/gotchas.md). The most expensive ones:

- 🔴 **`sslmode=require` doesn't work with Aurora's cert chain** by default — connections fail with `SSL error: certificate verify failed`. Fix: `sslmode=no-verify` (TLS-encrypted, just no chain check — safe in VPC) OR install the RDS root cert.
- 🔴 **CAA records survive the migration.** If your Fly setup had `issue "letsencrypt.org"` and AWS Certificate Manager uses Amazon Trust Services, ACM cert issuance silently fails. Fix: add `digicert.com` and `amazon.com` to CAA before flipping DNS.
- 🔴 **ECS deploys are silent by default.** A failed deploy looks identical to a queued one until you `aws ecs describe-services`. Add a deploy-watch step to CI that polls `deployment.status` and fails the workflow.
- 🟡 **Scheduler / cron jobs** need their own ECS service with `desired_count=1` (or EventBridge Scheduler). Don't try to fit them in the API service.
- 🟡 **`fly proxy` is the friendliest way to do data migration**, but it'll time out on databases >50GB. Use ECS one-shot task with S3 dump-and-restore instead (full recipe in gotchas.md).

[`references/gotchas.md`](references/gotchas.md) has **12 more** — read it before starting any phase.

# Rollback

Every phase has a rollback path documented in [`references/rollback.md`](references/rollback.md):

- Phase 1: `terraform destroy` (no production traffic yet)
- Phase 3: drop Aurora schema (Fly Postgres untouched)
- Phase 4: flip DNS back to Fly + re-enable Fly app (≤2 min)
- Phase 6: revert CloudFront origin / DNS

🔴 **Never destroy a Fly resource until its AWS replacement has served real production traffic for ≥24h.** If you keep Fly running in parallel for the first day, rollback is just a DNS flip.

# File layout

```
fly-to-aws-migration/
├── SKILL.md                                  ← Manifest (agent reads this)
├── README.md                                 ← This file (humans)
├── references/
│   ├── phases.md                             ← Detailed step-by-step for each phase
│   ├── gotchas.md                            ← 12+ traps with fixes
│   ├── rollback.md                           ← Per-phase rollback procedures
│   └── cost-model.md                         ← AWS pricing breakdown
├── scripts/
│   ├── audit-fly.sh                          ← Phase 0: snapshot Fly setup
│   ├── db-migrate.sh                         ← Phase 3: secrets + schema
│   ├── verify-parity.sh                      ← Side-by-side Fly vs AWS checks
│   └── cutover-dns.sh                        ← Phase 6 static-site DNS flip
└── templates/
    ├── terraform/                            ← Full IaC for Phase 1
    │   ├── main.tf
    │   ├── vpc.tf
    │   ├── aurora.tf
    │   ├── ecs-api.tf
    │   ├── alb.tf
    │   ├── static-sites.tf
    │   └── cloudflare-cache.tf
    └── github-workflows/
        ├── deploy-api.yml
        └── deploy-static-sites.yml
```

# Pairs with

- 🔗 **[`cloudflare-dns`](../cloudflare-dns/)** — DNS cutover for Phase 4 (API) and Phase 6 (static sites)
- 🔗 **[`namecheap-dns`](../namecheap-dns/)** — registrar-side ops if your domain isn't on Cloudflare yet

# License

MIT.
