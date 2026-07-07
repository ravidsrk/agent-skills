# Phases — detailed step-by-step

Each phase has: **goal → exact commands → verification → PR template → rollback link**.

---

# Phase 0: Audit (15 min, no changes)

**Goal:** know exactly what's on Fly before touching AWS.

```bash
# List all Fly apps
flyctl apps list

# For each app, get full inventory
for APP in $(flyctl apps list -j | jq -r '.[].Name'); do
  echo "=== $APP ==="
  flyctl machines list -a $APP
  flyctl scale show -a $APP
  flyctl secrets list -a $APP
  flyctl ips list -a $APP
done

# Postgres inventory
flyctl postgres list

# `flyctl postgres connect` opens psql; pass SQL after `--`.
flyctl postgres connect -a <db-app> -- -c "
  SELECT
    pg_size_pretty(pg_database_size(current_database())) AS db_size,
    (SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public') AS table_count,
    (SELECT COUNT(*) FROM pg_stat_user_tables) AS user_tables;
"

# Get table-by-table row counts (use for parity check later).
# n_live_tup is a stat estimate — good enough for baseline sizing, NOT for
# post-restore parity. scripts/db-migrate.sh uses real COUNT(*) for parity.
flyctl postgres connect -a <db-app> -- -c "
  SELECT schemaname, tablename, n_live_tup
  FROM pg_stat_user_tables
  ORDER BY n_live_tup DESC;
" > /tmp/fly-rowcounts.txt

# Volume sizes
flyctl volumes list -a <app>

# Existing DNS records at Cloudflare (zone API)
curl -sSf -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
  "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records?per_page=100" \
  | jq -r '.result[] | "\(.id)|\(.type)|\(.name)|\(.content)|proxied=\(.proxied)"' > /tmp/fly-dns.txt
```

**Verification:**
- Save `/tmp/fly-rowcounts.txt` and `/tmp/fly-dns.txt` — used in Phase 4 and 5 for parity check
- Count Fly machines × CPU × memory → estimate ECS task sizing
- Note all secret names (you'll re-group them in Phase 3)

**Output:** A short markdown doc summarizing what exists. Save to `.migration/00-audit.md`.

---

# Phase 1: Foundation IaC (60-90 min)

**Goal:** Build all the AWS resources that don't need data. Nothing user-facing changes yet.

## 🔴 PREFLIGHT: CAA records must authorize Amazon

Skipping this preflight costs ~25 min per incident (see `gotchas.md` #19). The ACM cert issued by ALB and CloudFront will hang in `PENDING_VALIDATION` for 10 min then fail if a Cloudflare-injected CAA record forbids Amazon.

```bash
# Set the apex you're migrating
DOMAIN="yourdomain.com"

CAA=$(dig +short CAA "$DOMAIN" @1.1.1.1)
echo "$CAA"

if [ -n "$CAA" ] && ! echo "$CAA" | grep -qE '(amazon|amazontrust)\.com'; then
  echo "🔴 CAA records present but Amazon not authorized — ACM issuance WILL fail."
  echo "   Add CAA records for amazon.com + amazontrust.com (both issue + issuewild) BEFORE terraform apply."
  echo "   Snippet in gotchas.md #19."
  exit 1
fi
echo "🟢 CAA OK — safe to proceed."
```

**Resources to create (~80+ in the production case):**

| Category | Resources |
|---|---|
| VPC | 1 VPC, 3 private + 3 public subnets, 1 IGW, 1 NAT GW, route tables, S3 gateway endpoint |
| Security | Security groups for ALB, ECS tasks, Aurora |
| IAM | task-execution-role, task-role, github-deploy-role (OIDC), policies |
| Aurora | Cluster + 1 instance, parameter group, subnet group, KMS key |
| ECR | Repository for API image |
| ALB | LB + target group + HTTPS listener (cert pending in Phase 2/3) |
| Secrets | Empty placeholder secret groups (filled in Phase 3) |
| CloudWatch | Log groups for API + migrate + scheduler |
| VPC Endpoints | Interface endpoints for ECR, Secrets, Logs, SSM (cost-sensitive — see gotchas.md) |

**Commands:**

```bash
# Initialize TF state — use S3 backend in same region
cd .migration/terraform/
terraform init

# Plan + review + apply
export TF_VAR_aws_region="ap-southeast-1"  # or wherever
export TF_VAR_project="myproject"
export TF_VAR_environment="prod"
export TF_VAR_cloudflare_api_token="$CLOUDFLARE_API_TOKEN"  # scoped token, not global key
export TF_VAR_cloudflare_zone_id="$CLOUDFLARE_ZONE_ID"
export TF_VAR_domain="yourdomain.com"

terraform plan -out=tfplan
terraform apply tfplan
```

**Verification:**

```bash
# Aurora is up
aws rds describe-db-clusters --db-cluster-identifier $PROJECT-$ENV-aurora \
  | jq '.DBClusters[0].Status'  # should be "available"

# ECR is empty (will push in Phase 2)
aws ecr describe-repositories --repository-names $PROJECT-$ENV-api

# ALB has no targets yet (will register in Phase 4)
aws elbv2 describe-load-balancers --names $PROJECT-$ENV-alb

# Test connectivity from outside: ALB DNS should respond 503 (no targets)
curl -I https://$(aws elbv2 describe-load-balancers --names $PROJECT-$ENV-alb \
  | jq -r '.LoadBalancers[0].DNSName')/
```

**PR title:** `feat(aws-migration): Phase 0 + 1 — audit + foundation IaC (~84 resources)`

**Rollback:** `terraform destroy` — pure infra, no user impact.

---

# Phase 2: Code prep (30 min)

**Goal:** Make the code AWS-deployable. Build + push to ECR. No production switch yet.

**Common Dockerfile patches (inlined below, no external file):**

1. **Respect `PORT` env var** (Fly assigns it dynamically; ECS hardcodes it in the task definition, typically `3000`). ALB target group and container port MUST match.

   Fly-style Dockerfile:
   ```dockerfile
   # Fly assigns PORT — no ENV needed
   CMD ["node", "server.js"]
   ```

   AWS-friendly Dockerfile:
   ```dockerfile
   ENV PORT=3000
   EXPOSE 3000
   CMD ["node", "server.js"]
   ```

2. **Drop Fly-only env at build time** (`FLY_APP_NAME`, `FLY_MACHINE_ID`, `FLY_REGION`). Anything referencing them in the runtime path must fall back cleanly.

3. **Use `npm` in the CI builder stage, not `bun`** (Bun + Next.js 16 hang; see gotcha #1). Local dev with Bun is fine.

   ```dockerfile
   FROM node:22-slim AS build
   WORKDIR /app
   COPY package*.json ./
   RUN npm ci
   COPY . .
   RUN npm run build
   ```

4. **Singleton task awareness** — If any background job assumes "I'm the only machine" (Fly's `FLY_MACHINE_ID` pattern), move it to a **separate ECS service with `desired_count=1`**. Env-var-based election does NOT work on Fargate (there is no per-task stable identity that maps to a leader). See `gotchas.md` → "singleton race".

5. **Health endpoint** — must respond <5s, no DB calls (or with short timeout). ALB target group default is 5s timeout.

6. **Add `.github/workflows/deploy-api.yml`** — builds + pushes to ECR via OIDC, then `aws ecs update-service --force-new-deployment`.

```bash
# Test build locally
docker build -t test-api ./apps/api
docker run -p 3000:3000 --env DATABASE_URL=postgresql://... test-api
curl http://localhost:3000/health  # should 200

# Push manually for first time (CI takes over after this)
aws ecr get-login-password --region $REGION \
  | docker login --username AWS --password-stdin $ECR_URI
docker tag test-api $ECR_URI:initial
docker push $ECR_URI:initial
```

**Verification:**
- ECR shows image: `aws ecr describe-images --repository-name $REPO`
- Image is multi-arch if needed (ARM64 for Graviton = cheaper)
- GitHub Actions can push (test the workflow on a dummy branch)

**PR title:** `feat(aws-migration): Phase 2 — Dockerfile fixes + ECR push workflow`

**Rollback:** Revert Dockerfile changes. ECR images are harmless.

---

# Phase 3: Secrets + DB **schema** (30-60 min)

**Goal:** Get production secrets into Secrets Manager. Get the production **schema** (no data) into Aurora. Data goes in Phase 4 to keep the outage window under 9 min.

🔴 **Critical insight:** Group secrets by category, not 1-to-1. Each Secrets Manager entry costs $0.40/mo. 50 individual secrets = $20/mo. 8 grouped entries = $3.20/mo.

**Recommended groupings:**

| Secret name | Contains |
|---|---|
| `$PROJECT/$ENV/db` | DATABASE_URL, REDIS_URL |
| `$PROJECT/$ENV/llm` | OPENAI_API_KEY, ANTHROPIC_API_KEY, GOOGLE_AI_KEY |
| `$PROJECT/$ENV/email` | RESEND_API_KEY, SENDGRID_API_KEY |
| `$PROJECT/$ENV/social` | TWITTER_*, DISCORD_*, etc. |
| `$PROJECT/$ENV/payments` | STRIPE_*, PAYPAL_* |
| `$PROJECT/$ENV/data-providers` | DATA_API_KEY_1, DATA_API_KEY_2, etc. |
| `$PROJECT/$ENV/auth` | JWT_SECRET, OAUTH_SECRETS |
| `$PROJECT/$ENV/telemetry` | SENTRY_DSN, POSTHOG_API_KEY |

```bash
# 1. Migrate secrets — script maps flyctl secrets → 8 grouped entries.
#    Dry-run first, then --apply.
scripts/secrets-migrate.sh <fly-api-app> --dry-run
scripts/secrets-migrate.sh <fly-api-app> --apply
```

In your ECS task definition, reference an env var out of a grouped secret's JSON key:

```json
{
  "secrets": [
    {"name": "OPENAI_API_KEY", "valueFrom": "arn:aws:secretsmanager:...:llm-xyz:OPENAI_API_KEY::"},
    {"name": "ANTHROPIC_API_KEY", "valueFrom": "arn:aws:secretsmanager:...:llm-xyz:ANTHROPIC_API_KEY::"}
  ]
}
```

**Database schema migration (recommended path):**

```bash
# Load schema from Fly (no data) into Aurora.
# db-migrate.sh --schema-only is the default mode.
scripts/db-migrate.sh --schema-only \
  --fly-app <fly-db-app> \
  --aurora-secret $PROJECT/$ENV/db
```

This dumps schema-only, restores under `psql -v ON_ERROR_STOP=1 -1 -f` (single transaction; aborts on the first error), then runs a real `SELECT COUNT(*)` per table on both sides — both must be zero here (schema-only).

At this point Aurora has your schema. **No data yet.** Fly is still authoritative.

**Alternative: full data dump in Phase 3 (single-shot).** For very small DBs (<200 MB) or when you can accept a maintenance window equal to `dump_time + restore_time` you can do:

```bash
scripts/db-migrate.sh --full \
  --fly-app <fly-db-app> \
  --aurora-secret $PROJECT/$ENV/db \
  --i-have-frozen-writes
```

The `--i-have-frozen-writes` flag is required; the script refuses to touch data without it. Alternative also collapses Phases 3 and 4, so if you go this route, the Phase 4 data-delta step below is skipped.

**Alternative: logical replication (zero-downtime).** pglogical from Fly Postgres → Aurora with `pgoutput`. Sketch:

```bash
# On Fly (source)
CREATE PUBLICATION migration_pub FOR ALL TABLES;
ALTER SYSTEM SET wal_level = logical;

# On Aurora (target) — pglogical extension + subscription
CREATE EXTENSION pglogical;
SELECT pglogical.create_node(node_name := 'aurora', dsn := '...');
SELECT pglogical.create_subscription(
  subscription_name := 'fly_migration',
  provider_dsn      := 'host=<fly-pg> ...'
);
```

Not scripted here — a full pglogical playbook is out of scope for this skill. Use it only if downtime must be <60s and the DB is large enough to justify the operational cost.

**Critical singleton check** — if your app has any background task that uses "primary machine" logic:

```bash
# On Fly, the singleton machine ID is exposed as FLY_MACHINE_ID
# On ECS, no equivalent. Pick one:
#   1. Run a separate ECS service with desired_count=1 (recommended)
#   2. Use EventBridge Scheduler → ECS RunTask for cron jobs

# Env-var-based election on Fargate does NOT work — every task in the same
# service sees the same env, so every task thinks it's the leader. Without a
# leader-election coordinator (DB advisory lock, DynamoDB conditional put),
# you'll get duplicate scanner runs / duplicate cron jobs.
```

**PR title:** `feat(aws-migration): Phase 3 — secrets migration + Aurora schema + data import`

**Rollback:** Drop Aurora database, recreate from snapshot. Fly is still authoritative.

---

# Phase 4+5: API production cutover (30 min, ≤9 min user-facing downtime)

**Goal:** Flip api.yourdomain.com from Fly to AWS.

## 🔴 PRE-STEP (do this 15+ minutes BEFORE the outage window)

The ≤9 min budget is only realistic if ECS is **warm** when the cutover starts. Fargate cold starts on ARM64 + a big Bun image + `health_check_grace_period_seconds = 120` will otherwise burn 4-6 minutes.

```bash
# 1. Ensure the API task is desired_count=1 against the schema-only Aurora.
aws ecs update-service \
  --cluster $PROJECT-$ENV-cluster \
  --service $PROJECT-$ENV-api \
  --desired-count 1 \
  --force-new-deployment

# 2. Wait for ALB target group to report 1 healthy target.
aws ecs wait services-stable \
  --cluster $PROJECT-$ENV-cluster \
  --services $PROJECT-$ENV-api

# 3. Verify — this container must serve /health via ALB DNS BEFORE the DB
#    delta and DNS flip happen.
ALB_DNS=$(aws elbv2 describe-load-balancers --names $PROJECT-$ENV-alb \
  | jq -r '.LoadBalancers[0].DNSName')
curl -sSf "https://$ALB_DNS/health" >/dev/null && echo "🟢 pre-warm OK"
```

**Pre-cutover checklist:**

- [ ] ECS task warm, healthy against ALB for ≥15 min (see pre-step above)
- [ ] Aurora has full schema (Phase 3) — data will be delta-loaded in step 1 below
- [ ] Secrets Manager has all required secrets
- [ ] ALB target group health: 1/1 healthy
- [ ] `curl -sSf https://<alb-dns>/health` and `.../health/full` both 200
- [ ] Cloudflare cert validation already passed (ACM cert in `ISSUED` state)
- [ ] Cloudflare `api.$DOMAIN` record is already proxied=true (so the flip is atomic)
- [ ] Communicate maintenance window to users

**Cutover steps (in order):**

```bash
# 1. FREEZE Fly writes. Scale API workers to 0 — DB is Fly-managed and stays up.
#    From this moment on, Fly is not accepting writes.
flyctl scale count 0 -a <fly-api>

# 2. Final DATA-ONLY delta dump from Fly Postgres → Aurora.
#    scripts/db-migrate.sh --data-only requires --i-have-frozen-writes.
scripts/db-migrate.sh --data-only \
  --fly-app <fly-db-app> \
  --aurora-secret $PROJECT/$ENV/db \
  --i-have-frozen-writes

# 3. Force ECS to redeploy so it picks up the now-populated DB
#    (task-def unchanged; just needs a rolling replacement).
aws ecs update-service \
  --cluster $PROJECT-$ENV-cluster \
  --service $PROJECT-$ENV-api \
  --force-new-deployment
aws ecs wait services-stable --cluster $PROJECT-$ENV-cluster --services $PROJECT-$ENV-api

# 4. Flip Cloudflare DNS atomically.
ALB_DNS=$(aws elbv2 describe-load-balancers --names $PROJECT-$ENV-alb \
  | jq -r '.LoadBalancers[0].DNSName')
scripts/cutover-dns.sh "api.$DOMAIN" "$ALB_DNS"

# 5. Verify within 60s (Cloudflare proxied = instant).
for i in 1 2 3 4 5; do
  curl -sSf https://api.yourdomain.com/health
  sleep 5
done
```

**Verification:**

```bash
# Run parity check
./scripts/verify-parity.sh https://api.yourdomain.com

# Watch ECS logs for 5 min
aws logs tail /ecs/$PROJECT-$ENV-api --follow

# Watch DB connections (should ramp up)
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name DatabaseConnections \
  --dimensions Name=DBClusterIdentifier,Value=$PROJECT-$ENV-aurora \
  --start-time $(date -u -d '15 minutes ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 60 --statistics Maximum
```

**PR title:** `feat(aws-migration): Phase 4+5 — API production cutover (Fly → AWS)`

**Rollback:** Single Cloudflare API call to flip DNS back to Fly. Fly machines are still in your account (stopped, not destroyed). Restart with `flyctl scale count 2 -a <fly-api>`.

---

# Phase 6: Static sites cutover (zero downtime)

**Goal:** Move static frontend (Next.js, Astro, etc.) from Fly to S3 + CloudFront.

**Resources to add (~27):**

- 1 S3 bucket per site (private + OAC)
- 1 ACM cert in us-east-1 with all aliases as SANs
- DNS validation records via Cloudflare
- 1 CloudFront distribution per site
- 1 CloudFront function for URI rewrite (`/foo` → `/foo.html` for Next.js static export)
- Response-headers policy (HSTS, X-Content-Type, Frame DENY)
- IAM policy for GitHub OIDC deploy

**Build commands:**

```bash
# Static export build
cd apps/web
npm install --ignore-scripts
NEXT_PUBLIC_API_URL=https://api.yourdomain.com \
  npm run build  # outputs to ./out

# Upload with proper Cache-Control
aws s3 sync out/ s3://$BUCKET/ \
  --delete --exclude "*" --include "*.html" \
  --content-type "text/html; charset=utf-8" \
  --cache-control "public, max-age=300, s-maxage=300"

aws s3 sync out/ s3://$BUCKET/ \
  --delete --exclude "*.html" \
  --cache-control "public, max-age=31536000, immutable"

# Invalidate
aws cloudfront create-invalidation \
  --distribution-id $CF_ID \
  --paths "/*"
```

**DNS flip (for static sites — usually safer to do all at once since they're stateless):**

```bash
AUTH=("-H" "Authorization: Bearer $CLOUDFLARE_API_TOKEN")
ZONE="https://api.cloudflare.com/client/v4/zones/$ZONE_ID"

# www CNAME
curl -sSf -X PATCH "${AUTH[@]}" -H "Content-Type: application/json" \
  "$ZONE/dns_records/$WWW_ID" \
  -d '{"content":"<cf-dns>","proxied":true}'

# Apex — Cloudflare CNAME flattening (delete A+AAAA, create CNAME)
curl -sSf -X DELETE "${AUTH[@]}" "$ZONE/dns_records/$APEX_A_ID"
curl -sSf -X DELETE "${AUTH[@]}" "$ZONE/dns_records/$APEX_AAAA_ID"
curl -sSf -X POST "${AUTH[@]}" -H "Content-Type: application/json" \
  "$ZONE/dns_records" \
  -d '{"type":"CNAME","name":"yourdomain.com","content":"<cf-dns>","proxied":true}'

# docs CNAME
curl -sSf -X PATCH "${AUTH[@]}" -H "Content-Type: application/json" \
  "$ZONE/dns_records/$DOCS_ID" \
  -d '{"content":"<cf-dns>","proxied":true}'
```

**Verification:** All 3 URLs return 200, hit your new content, with correct content-type and cache headers.

**PR title:** `feat(aws-migration): Phase 6 — migrate web + docs to S3/CloudFront`

**Rollback:** Reverse DNS flips. Fly static apps are still there.

---

# Phase 7: Perf tuning — Cloudflare cache layer (20 min, $0/mo)

**Goal:** Cut static-site TTFB from ~300ms to ~65ms (~4.6x speedup).

**Why this matters:** Cloudflare default is `cf-cache-status: DYNAMIC` for HTML — even sitting on top of CloudFront, HTML responses go ALL the way back to S3 on every request. Adding a cache rule + tiered cache fills this gap.

```bash
# All Cloudflare API calls use a scoped API token.
AUTH=("-H" "Authorization: Bearer $CLOUDFLARE_API_TOKEN")

# 1. Enable Tiered Cache (free)
curl -sSf -X PATCH "${AUTH[@]}" \
  -H "Content-Type: application/json" \
  "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/argo/tiered_caching" \
  -d '{"value":"on"}'

# 2. Enable Smart Tiered Cache Topology
curl -sSf -X PATCH "${AUTH[@]}" \
  -H "Content-Type: application/json" \
  "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/cache/tiered_cache_smart_topology_enable" \
  -d '{"value":"on"}'

# 3. Add cache rule for HTML
curl -sSf -X PUT "${AUTH[@]}" \
  -H "Content-Type: application/json" \
  "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/rulesets/phases/http_request_cache_settings/entrypoint" \
  -d '{
    "rules": [{
      "expression": "(http.host eq \"yourdomain.com\") or (http.host eq \"www.yourdomain.com\") or (http.host eq \"docs.yourdomain.com\")",
      "action": "set_cache_settings",
      "action_parameters": {
        "cache": true,
        "edge_ttl": {"mode": "respect_origin"},
        "browser_ttl": {"mode": "respect_origin"}
      }
    }]
  }'
```

**Verification:**

```bash
# First request — MISS
curl -I https://yourdomain.com/ | grep cf-cache-status  # MISS

# Second request — HIT, much faster
curl -I https://yourdomain.com/ | grep cf-cache-status  # HIT
curl -w "TTFB=%{time_starttransfer}s\n" https://yourdomain.com/  # ~65ms (down from ~300ms, ~4.6x)
```

**Codify in Terraform:**

```hcl
resource "cloudflare_tiered_cache" "main" {
  zone_id    = var.cloudflare_zone_id
  cache_type = "smart"
}

resource "cloudflare_ruleset" "static_sites_cache" {
  zone_id = var.cloudflare_zone_id
  name    = "default"  # 🟡 entrypoint rulesets MUST be "default"
  kind    = "zone"
  phase   = "http_request_cache_settings"
  rules {
    expression = "(http.host eq \"...\") or ..."
    action     = "set_cache_settings"
    action_parameters {
      cache = true
      edge_ttl    { mode = "respect_origin" }
      browser_ttl { mode = "respect_origin" }
    }
  }
}
```

**PR title:** `chore(aws-migration): Phase 7 — codify Cloudflare cache layer`

**Rollback:** Pure additive, no rollback needed. Run `terraform destroy -target=cloudflare_ruleset.static_sites_cache` to revert.

---

# Final: T+48h Fly decommission

After 48h of stable production on AWS:

```bash
# Permanently destroy
flyctl apps destroy <api-app>
flyctl apps destroy <web-app>
flyctl apps destroy <docs-app>
flyctl apps destroy <db-app>  # after taking final snapshot
```

Optional cleanup PR: remove `apps/*/fly.toml`, `apps/*/Dockerfile.fly` if you kept Fly-specific files.
