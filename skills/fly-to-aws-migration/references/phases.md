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
flyctl postgres list 2>&1
flyctl postgres connect -a <db-app> -c "
  SELECT
    pg_size_pretty(pg_database_size(current_database())) AS db_size,
    (SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public') AS table_count,
    (SELECT COUNT(*) FROM pg_stat_user_tables) AS user_tables;
"

# Get table-by-table row counts (use for parity check later)
flyctl postgres connect -a <db-app> -c "
  SELECT schemaname, tablename, n_live_tup
  FROM pg_stat_user_tables
  ORDER BY n_live_tup DESC;
" > /tmp/fly-rowcounts.txt

# Volume sizes
flyctl volumes list -a <app>

# Existing DNS records at Cloudflare (zone API)
curl -sS -H "X-Auth-Email: $CLOUDFLARE_EMAIL" -H "X-Auth-Key: $CLOUDFLARE_GLOBAL_API_KEY" \
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
export TF_VAR_cloudflare_email="$CLOUDFLARE_EMAIL"
export TF_VAR_cloudflare_global_api_key="$CLOUDFLARE_GLOBAL_API_KEY"

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

**Common required changes:**

1. **Dockerfile must respect `PORT` env var** (Fly defaults to 8080; ALB target group config will use whatever port we set)
   ```dockerfile
   ENV PORT=3000
   EXPOSE 3000
   CMD ["bun", "run", "start"]  # or `node` etc.
   ```

2. **Singleton task awareness** — If any background job assumes "I'm the only machine" (Fly's pattern), add a `PRIMARY_MACHINE_ID` env var override that ECS sets explicitly. See `gotchas.md` → "singleton race".

3. **Health endpoint** — must respond <5s, no DB calls (or with short timeout). ALB target group default is 5s timeout.

4. **Add `.github/workflows/deploy-api.yml`** — builds + pushes to ECR via OIDC, then `aws ecs update-service --force-new-deployment`.

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

# Phase 3: Secrets + DB schema (30-60 min)

**Goal:** Get production data into Aurora. Get production secrets into Secrets Manager.

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
# 1. Migrate secrets — read from Fly, write to AWS Secrets Manager as grouped JSON
FLY_APP="my-api"
PROJECT="myproject"
ENV="prod"

flyctl ssh console -a $FLY_APP -C "env" > /tmp/fly-env.txt
# (Cleanly extract only your app secrets, not Fly system vars)

# For each group, build a JSON blob and put it
LLM_SECRETS='{"OPENAI_API_KEY":"sk-...", "ANTHROPIC_API_KEY":"sk-ant-..."}'
aws secretsmanager create-secret \
  --name "$PROJECT/$ENV/llm" \
  --secret-string "$LLM_SECRETS"

# In your ECS task definition, reference them like:
# {
#   "secrets": [
#     {"name": "OPENAI_API_KEY", "valueFrom": "arn:aws:secretsmanager:...:llm-xyz:OPENAI_API_KEY::"},
#     {"name": "ANTHROPIC_API_KEY", "valueFrom": "arn:aws:secretsmanager:...:llm-xyz:ANTHROPIC_API_KEY::"}
#   ]
# }
```

**Database migration:**

```bash
# Option A: pg_dump + restore (REQUIRES downtime equal to dump+restore duration)
# (flyctl postgres connect has no command flag — tunnel with flyctl proxy instead)
flyctl proxy 5433:5432 -a <db-app> &
# PGPASSWORD keeps the credential out of argv (ps-visible otherwise)
PGSSLMODE=prefer PGPASSWORD=$FLY_PG_PASSWORD pg_dump "postgresql://postgres@localhost:5433/<db-name>" \
  --no-owner --no-acl --schema=public > /tmp/fly-dump.sql

# Get Aurora endpoint
AURORA_ENDPOINT=$(aws rds describe-db-clusters --db-cluster-identifier $PROJECT-$ENV-aurora \
  | jq -r '.DBClusters[0].Endpoint')

# Restore (use a bastion or run from inside VPC)
psql "postgresql://admin:$AURORA_PW@$AURORA_ENDPOINT/postgres" -f /tmp/fly-dump.sql

# Option B: logical replication (zero downtime, more complex)
# pglogical setup — see references/db-replication.md if needed

# Verification: row counts must match
psql "postgresql://admin:$AURORA_PW@$AURORA_ENDPOINT/$DB_NAME" -c "
  SELECT schemaname, tablename, n_live_tup
  FROM pg_stat_user_tables
  ORDER BY n_live_tup DESC;
" > /tmp/aurora-rowcounts.txt

diff /tmp/fly-rowcounts.txt /tmp/aurora-rowcounts.txt
# Expected: empty diff (or only +/- a few rows if traffic is live during dump)
```

**Critical singleton check** — if your app has any background task that uses "primary machine" logic:

```bash
# On Fly, the singleton machine ID is exposed as FLY_MACHINE_ID
# On ECS, no equivalent. You need to either:
#   1. Run a separate scheduler service with desired_count=1, OR
#   2. Use task placement constraints to force singleton, OR
#   3. Add PRIMARY_MACHINE_ID env var that matches a task ID at boot

# Without this, you'll get duplicate scanner runs / duplicate cron jobs.
```

**PR title:** `feat(aws-migration): Phase 3 — secrets migration + Aurora schema + data import`

**Rollback:** Drop Aurora database, recreate from snapshot. Fly is still authoritative.

---

# Phase 4+5: API production cutover (30 min, ≤9 min user-facing downtime)

**Goal:** Flip api.yourdomain.com from Fly to AWS.

**Pre-cutover checklist:**

- [ ] AWS ECS task running successfully with latest image (`aws ecs describe-services`)
- [ ] Aurora has full data (row counts match Fly within margin)
- [ ] Secrets Manager has all required secrets
- [ ] ALB target group health: 1/1 healthy
- [ ] Test from outside via ALB DNS directly:
  ```bash
  curl https://<alb-dns>/health  # 200
  curl https://<alb-dns>/health/full  # 200 with all dependencies
  ```
- [ ] Cloudflare cert validation already passed (ACM cert in `ISSUED` state)
- [ ] Communicate maintenance window to users

**Cutover steps (in order):**

```bash
# 1. Final sync of any time-sensitive data (if Option A pg_dump was used)
# Re-dump if data has changed
flyctl postgres connect -a <db> -C "pg_dump --no-owner --no-acl --schema=public --data-only" \
  > /tmp/final-data.sql
psql "$AURORA_URL" -c "TRUNCATE ... CASCADE"  # match tables to truncate
psql "$AURORA_URL" -f /tmp/final-data.sql

# 2. Drain Fly traffic (scale Fly to 0, but DON'T destroy machines yet)
flyctl scale count 0 -a <fly-api>

# 3. Force ECS to start fresh with latest image
aws ecs update-service \
  --cluster $PROJECT-$ENV-cluster \
  --service $PROJECT-$ENV-api \
  --force-new-deployment

# Wait for healthy
aws ecs wait services-stable --cluster $PROJECT-$ENV-cluster --services $PROJECT-$ENV-api

# 4. Flip Cloudflare DNS
ZONE_ID="..."
API_RECORD_ID="..."
ALB_DNS=$(aws elbv2 describe-load-balancers --names $PROJECT-$ENV-alb \
  | jq -r '.LoadBalancers[0].DNSName')

curl -X PATCH -H "X-Auth-Email: $CLOUDFLARE_EMAIL" -H "X-Auth-Key: $CLOUDFLARE_GLOBAL_API_KEY" \
  -H "Content-Type: application/json" \
  "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records/$API_RECORD_ID" \
  -d "{\"content\":\"$ALB_DNS\",\"proxied\":true}"

# 5. Verify within 60s (Cloudflare proxied = instant)
for i in 1 2 3 4 5; do
  curl -sS https://api.yourdomain.com/health
  sleep 5
done
```

**Verification:**

```bash
# Run parity check
./scripts/verify-parity.sh https://api.yourdomain.com https://your-app.fly.dev

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
# www CNAME
curl -X PATCH ... "$ZONE/$WWW_ID" -d '{"content":"<cf-dns>"}'

# Apex — Cloudflare CNAME flattening (delete A+AAAA, create CNAME)
curl -X DELETE ... "$ZONE/$APEX_A_ID"
curl -X DELETE ... "$ZONE/$APEX_AAAA_ID"
curl -X POST ... "$ZONE/dns_records" \
  -d '{"type":"CNAME","name":"yourdomain.com","content":"<cf-dns>","proxied":true}'

# docs CNAME
curl -X PATCH ... "$ZONE/$DOCS_ID" -d '{"content":"<cf-dns>"}'
```

**Verification:** All 3 URLs return 200, hit your new content, with correct content-type and cache headers.

**PR title:** `feat(aws-migration): Phase 6 — migrate web + docs to S3/CloudFront`

**Rollback:** Reverse DNS flips. Fly static apps are still there.

---

# Phase 7: Perf tuning — Cloudflare cache layer (20 min, $0/mo)

**Goal:** Cut static-site TTFB from ~300ms to ~65ms.

**Why this matters:** Cloudflare default is `cf-cache-status: DYNAMIC` for HTML — even sitting on top of CloudFront, HTML responses go ALL the way back to S3 on every request. Adding a cache rule + tiered cache fills this gap.

```bash
# 1. Enable Tiered Cache (free)
curl -X PATCH -H "X-Auth-Email: ..." -H "X-Auth-Key: ..." \
  "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/argo/tiered_caching" \
  -d '{"value":"on"}'

# 2. Enable Smart Tiered Cache Topology
curl -X PATCH ... \
  "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/cache/tiered_cache_smart_topology_enable" \
  -d '{"value":"on"}'

# 3. Add cache rule for HTML
curl -X PUT ... \
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
curl -w "TTFB=%{time_starttransfer}s\n" https://yourdomain.com/  # ~65ms
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
