# Gotchas — every trap we hit, with fix

Read this BEFORE starting any phase. Each item cost real time in production.

---

# 🔴 1. `bun run build` hangs on Next.js 16

**Symptom:** `next build` gets stuck at "Creating an optimized production build..." indefinitely. No error, no progress. CPU usage normal. Memory normal.

**Where:** apps/web, apps/docs in Phase 6 (static site builds in CI).

**Root cause:** Bun + Next.js 16 + Turbopack interaction. Confirmed both inside containers and bare-metal.

**Fix:** Use `npm` for builds in CI, even if dev uses bun.

```yaml
# .github/workflows/deploy-static-sites.yml
- uses: actions/setup-node@v4
  with:
    node-version: '22'
- run: npm install --ignore-scripts
- run: npm run build
```

Both Dockerfiles for your-web-app and your-docs-app already used npm in builder stage. Bun was only for local dev. The Phase 6 CI workflow matches.

---

# 🔴 2. Fumadocs + Shiki = SIGABRT at 2 GB heap

**Symptom:** Docs build crashes with `Next.js build worker exited with code: null and signal: SIGABRT` during "Running TypeScript..." phase.

**Where:** Phase 6 docs build.

**Root cause:** Fumadocs loads all Shiki language bundles for syntax highlighting; TypeScript checker holds the full type graph. Combined > 2 GB heap.

**Fix:** `NODE_OPTIONS="--max-old-space-size=4096"` for the docs build.

```yaml
- name: Build static export
  working-directory: apps/docs
  env:
    NODE_OPTIONS: '--max-old-space-size=4096'
  run: npm run build
```

---

# 🔴 3. CloudFront cert MUST be in us-east-1

**Symptom:** Terraform apply fails with `InvalidViewerCertificate: The specified SSL certificate doesn't exist`.

**Where:** Phase 6 — CloudFront distribution creation.

**Root cause:** Hard AWS constraint. CloudFront only reads certs from us-east-1, regardless of where the rest of your stack lives.

**Fix:** Add a second provider alias and use it for ONE cert.

```hcl
provider "aws" {
  alias  = "us-east-1"
  region = "us-east-1"
}

resource "aws_acm_certificate" "cloudfront" {
  provider          = aws.us-east-1  # ← critical
  domain_name       = "yourdomain.com"
  subject_alternative_names = ["www.yourdomain.com", "docs.yourdomain.com"]
  validation_method = "DNS"
}
```

---

# 🔴 4. Bun + Prisma WASM crash class (singleton silent outage)

**Symptom:** After API deploy, all singleton background tasks (scanner, scheduler, cron jobs) STOP writing to DB. `/health` returns 200. CloudWatch logs show:
```
PrismaClientUnknownRequestError
Out of bounds memory access (evaluating 'o.querycompiler_compile(this.__wbg_ptr, n, _)')
```

**Where:** Phase 4+5 or any subsequent API deploy. Hit on a production deploy an internal cutover incident — 15-min silent outage.

**Root cause:** Bun's JSC/WASM JIT compiles Prisma's WASM compiler into a bad state. Non-deterministic — same Bun version, same Prisma version, different app code revisions can trigger or not.

References: oven-sh/bun#17146, oven-sh/bun#22269.

**Fix (verification):** After EVERY API deploy that touches signals/, alpha/, agents/, mastra/, scanner code, or provider keys, wait 5 min then run:

```sql
SELECT (SELECT COUNT(*) FROM your_write_heavy_table 
        WHERE created_at > NOW() - INTERVAL '5 minutes')::int AS recent_writes;
```

If `recent_writes == 0`:
```bash
# Check logs
flyctl logs --instance <primary> | grep -iE "out of bounds|wasm|querycompiler"
# (replace with aws logs tail for AWS)

# If WASM errors found → immediate rollback
aws ecs update-service --task-definition $PROJECT-$ENV-api:<prior-revision> --force-new-deployment
```

**Long-term fix:** Migrate off Bun for production OR ensure your test suite includes a long-running singleton task that catches this in CI (not just `/health`).

---

# 🔴 5. Cloudflare ruleset entrypoints MUST be named "default"

**Symptom:** `terraform apply` wants to destroy and recreate the cache ruleset because `name` differs.

**Where:** Phase 7 — codifying the cache rule.

**Root cause:** Cloudflare API treats `phases/<phase>/entrypoint` as a singleton per zone. The name field is locked to `"default"`.

**Fix:**
```hcl
resource "cloudflare_ruleset" "static_sites_cache" {
  name = "default"  # NOT a descriptive name
  description = "Edge-cache HTML for static sites"  # ← descriptive label goes here
  ...
}
```

---

# 🔴 6. `cloudflare_argo` is deprecated AND requires paid subscription

**Symptom:** `terraform apply` fails with `failed to update smart routing setting: The request is not authorized to access this setting. Cause(s): smart_routing (1015)`.

**Where:** Phase 7.

**Root cause:** The Cloudflare provider's older `cloudflare_argo` resource still tries to manage `smart_routing`, which requires a $5/mo Argo subscription. The dedicated `cloudflare_tiered_cache` resource is the modern, free replacement.

**Fix:** Don't use `cloudflare_argo`. Use `cloudflare_tiered_cache` alone:

```hcl
resource "cloudflare_tiered_cache" "main" {
  zone_id    = var.cloudflare_zone_id
  cache_type = "smart"
}
```

This handles enabling + topology in one resource with zero paid features.

---

# 🔴 7. Singleton job race when Fly → ECS

**Symptom:** Cron jobs run twice. Scanner picks up the same row twice. Two emails sent to each user.

**Where:** Phase 4+5 if your code uses `process.env.FLY_MACHINE_ID` to elect a leader.

**Root cause:** Fly auto-injects `FLY_MACHINE_ID`. ECS doesn't. Without changes, every task thinks it's the singleton.

**Fix options (pick one):**

A. **Separate ECS service with `desired_count=1`** — the recommended path.

```hcl
resource "aws_ecs_service" "scheduler" {
  desired_count = 1
  deployment_minimum_healthy_percent = 0
  deployment_maximum_percent = 100
  # ← ensures only 1 task during deploys
}
```

🔴 **Don't try env-var-based election on Fargate.** Every task in the same service reads the same task-definition environment, so there is no per-task stable identity to key on. Any code of the form `if (process.env.X === "primary") runScheduler()` runs on every replica → duplicate cron jobs. If you need per-task election on shared tasks (rare), use a DB advisory lock or DynamoDB conditional-put as the coordinator.

B. **Use EventBridge Scheduler → ECS RunTask** for cron jobs instead of in-process scheduling.

---

# 🔴 8. Aurora Serverless v2 minimum 0.5 ACU = $58/mo floor

**Symptom:** Even at 1 req/min, Aurora bill is ~$58/mo for compute alone.

**Where:** Phase 1 + ongoing.

**Root cause:** Aurora Serverless v2 doesn't go below 0.5 ACU (until newly announced 0 ACU "auto-pause", region-by-region rollout).

**Fix options:**

- For dev/staging: use RDS `db.t4g.micro` instance class (~$15/mo)
- For prod with traffic: keep Aurora; the auto-scaling is worth it
- For prod with traffic patterns (e.g. 9-5 only): manually scale at off-hours via Lambda
- Check your region for Aurora Serverless v2 0 ACU auto-pause (some regions only as of 2025)

---

# 🔴 9. Migrate task can't read Secrets Manager

**Symptom:** ECS migrate task fails with `Unable to access valueFrom secret`.

**Where:** Phase 3 or Phase 4+5, running DB migrations as a one-off ECS task.

**Root cause:** Migrate task uses `task-execution-role` only (no `task-role`). Execution role can pull image + push logs but CAN'T read secrets at runtime.

**Fix:** Set BOTH roles in the task definition, OR add Secrets Manager read perms to the execution role:

```hcl
resource "aws_ecs_task_definition" "migrate" {
  execution_role_arn = aws_iam_role.task_execution.arn
  task_role_arn      = aws_iam_role.task_runtime.arn  # ← runtime AWS calls
  ...
}
```

The execution role is for ECS-internal calls (pull image, fetch secrets at task-launch). The task role is for application-level AWS calls (S3, SQS, additional Secrets reads).

For secrets injected as env vars via `secrets:` block in task def, the EXECUTION role needs `secretsmanager:GetSecretValue`. We hit this and added it.

---

# 🔴 10. VPC endpoints × 3 AZ = $171/mo (unexpected)

**Symptom:** Monthly bill is $100+ higher than expected.

**Where:** Phase 1.

**Root cause:** 6 interface VPC endpoints × 3 AZs × $0.013/hr × 730hr/mo = $170.82/mo. Each endpoint runs an ENI per AZ.

**Fix options:**

A. **Deploy endpoints in only 1 AZ** if you're running a single ECS task anyway (saves $114/mo):
```hcl
resource "aws_vpc_endpoint" "secrets_manager" {
  subnet_ids = [aws_subnet.private[0].id]  # only 1 AZ
}
```

B. **Skip endpoints entirely, use NAT for everything** (saves $170/mo, adds ~$20/mo of NAT traffic):
```hcl
# Just delete the aws_vpc_endpoint resources
# All AWS API calls go via NAT GW → public AWS endpoints
```

C. **Keep multi-AZ for HA** — what we did in production. Worth it if production resilience matters more than $115/mo savings.

---

# 🔴 11. `:latest` doesn't auto-update in ECS

**Symptom:** Pushed new image to ECR tagged `:latest`. ECS service still runs old code.

**Where:** Phase 2 + every subsequent deploy.

**Root cause:** ECS doesn't poll ECR. The `:latest` tag is a static reference at task launch time. To pick up a new image, you need to force a new deployment.

**Fix:** Always end your CI workflow with:

```bash
aws ecs update-service \
  --cluster $CLUSTER \
  --service $SERVICE \
  --force-new-deployment
```

🟢 This is non-destructive — ECS does rolling replacement with health checks.

---

# 🔴 12. ALB target group default health check is too strict for slow boot

**Symptom:** New ECS tasks marked unhealthy → killed → restart loop. Service never reaches steady state.

**Where:** Phase 4+5.

**Root cause:** ALB target group defaults: 30s interval, 5s timeout, 2 healthy / 3 unhealthy. If your app takes >35s to start (e.g. running migrations on boot), you'll die.

**Fix:**

```hcl
resource "aws_lb_target_group" "api" {
  health_check {
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 5  # more lenient
    path                = "/health"
  }
}

resource "aws_ecs_service" "api" {
  health_check_grace_period_seconds = 120  # ← give boot time
}
```

---

# 🟡 13. Cloudflare apex CNAME flattening

**Symptom:** Trying to point `yourdomain.com` (apex) to CloudFront with `A`/`AAAA` records is painful — CloudFront DNS rotates.

**Where:** Phase 6.

**Root cause:** Apex domains can't normally have CNAME records.

**Fix:** Cloudflare supports "CNAME flattening" at the zone apex if the record is proxied (orange cloud):

```bash
# Delete A + AAAA records
curl -X DELETE ... "$ZONE/$APEX_A_ID"
curl -X DELETE ... "$ZONE/$APEX_AAAA_ID"

# Create CNAME at apex (proxied=true)
curl -X POST ... "$ZONE/dns_records" \
  -d '{"type":"CNAME","name":"yourdomain.com","content":"<cf-dns>","proxied":true}'
```

🟡 If you ever disable Cloudflare proxy, this breaks. Switch to ALIAS-style record then.

---

# 🟡 14. pg_dump SSL cert error from Fly

**Symptom:** `pg_dump` from Fly Postgres fails with `SSL error: tlsv1 alert internal error`.

**Where:** Phase 3.

**Root cause:** Fly's Postgres SSL cert chain isn't recognized by some `pg_dump` versions.

**Fix:** Use `PGSSLMODE=no-verify` or connect via Fly's internal hostname through `flyctl ssh`:

```bash
PGSSLMODE=no-verify pg_dump postgresql://...
# OR
flyctl ssh console -a <db> -C "pg_dump --no-owner --no-acl --schema=public"
```

---

# 🟡 15. Bun base image size + cold start

**Symptom:** ECS task takes 40s+ to start on first deploy.

**Where:** Phase 4+5.

**Root cause:** Bun's official `oven/bun:1.2` image is 387 MB. Pull from ECR + extract = 20-30s on Fargate.

**Fix options:**

- Use `oven/bun:1.2-alpine` (much smaller) if your deps work on alpine
- Set `health_check_grace_period_seconds = 120` so health checks don't kill task during boot
- Use VPC endpoints for ECR (much faster pull than via NAT)

---

# 🟡 16. ECS task `cpuArchitecture` mismatch

**Symptom:** Task fails to start with `image manifest schema 2 not supported` or `exec format error`.

**Where:** Phase 2 + Phase 4+5.

**Root cause:** You built `--platform linux/amd64` image but task definition says `ARM64`, or vice versa.

**Fix:** Either:

A. **Build multi-arch in CI:**
```yaml
- uses: docker/build-push-action@v5
  with:
    platforms: linux/amd64,linux/arm64
```

B. **Match arch explicitly in task definition:**
```hcl
runtime_platform {
  cpu_architecture        = "ARM64"  # or "X86_64"
  operating_system_family = "LINUX"
}
```

ARM64 is ~20% cheaper on Fargate. Recommended if your stack supports it (most Node/Bun/Go does).

---

# 🟡 17. Cloudflare default cache skips HTML

**Symptom:** Static site TTFB is 300ms even with CloudFront in front. `cf-cache-status: DYNAMIC` on every response.

**Where:** Phase 7.

**Root cause:** Cloudflare default cache config is "Cache everything except HTML." Even with proxy enabled, HTML responses always go to origin.

**Fix:** Add a cache rule (see Phase 7 in `phases.md`). Cuts TTFB from ~300ms to ~65ms. Free.

---

# 🟢 18. Cloudflare proxied = instant DNS propagation

**Symptom:** None — this is a feature, not a bug.

**Where:** Phase 4+5 + Phase 6 cutovers.

**Why this matters:** Cloudflare keeps proxied records' TTL effectively at 60s server-side, but propagation through their edge is <5s in practice. This is why we use Cloudflare instead of Route 53 for the cutover record — flips are atomic.

```bash
# Time the cutover
date +%s%N > /tmp/before.txt
curl -X PATCH ... # flip
for i in $(seq 1 60); do
  RESULT=$(curl -sS https://api.yourdomain.com/health)
  date +%s%N > /tmp/after-$i.txt
  echo "Got: $RESULT at $(cat /tmp/after-$i.txt)"
  sleep 1
done
```

Typical observation: new backend serving within 2-5s.

---

# 🔴 19. Cloudflare auto-injected CAA records block ACM cert issuance

**Symptom:** `aws_acm_certificate_validation` waits forever then fails with `CAA_ERROR`. ACM cert stays `PENDING_VALIDATION` for ~5 min then flips to `FAILED`. The Cloudflare CNAME validation record is correct, the DNS resolves, but Amazon refuses to issue.

**Where:** Phase 1 ALB cert provisioning, ONLY when the apex domain is on Cloudflare with universal SSL active.

**Why this happens:** Cloudflare's universal SSL silently injects hidden CAA records that authorize their own CAs (DigiCert, Let's Encrypt) but NOT Amazon. The CAA RR set looks like:

```
example.com. CAA 0 issuewild "digicert.com; cansignhttpexchanges=yes"
example.com. CAA 0 issuewild "letsencrypt.org"
example.com. CAA 0 iodef "mailto:postmaster@example.com"
```

These don't appear in the Cloudflare DNS dashboard. Only visible via DNS query (`dig CAA example.com @1.1.1.1` or the Google DoH endpoint).

When CAA says `issuewild "letsencrypt.org"`, **only Let's Encrypt can issue wildcards**. Amazon = denied.

**Fix:** add explicit Amazon CAA records BEFORE creating the cert. Both `issue` AND `issuewild` for both `amazon.com` AND `amazontrust.com`:

```bash
ZONE=<cloudflare-zone-id>
for tag in issue issuewild; do
  for value in amazon.com amazontrust.com; do
    curl -sSf -X POST \
      -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
      -H "Content-Type: application/json" \
      "https://api.cloudflare.com/client/v4/zones/$ZONE/dns_records" \
      -d "{\"type\":\"CAA\",\"name\":\"$ZONE_DOMAIN\",\"data\":{\"flags\":0,\"tag\":\"$tag\",\"value\":\"$value\"},\"ttl\":300,\"proxied\":false}"
  done
done
```

**Preflight check** to add at the very top of `01-foundation/`:

```bash
# Before ACM cert, verify CAA allows Amazon (or absent = allow all)
CAA=$(curl -sS -H "accept: application/dns-json" "https://dns.google/resolve?name=$DOMAIN&type=CAA" | jq -r '.Answer[]? | .data')
if echo "$CAA" | grep -qE "^0 (issue|issuewild)" && ! echo "$CAA" | grep -qE "(amazon|amazontrust)\\.com"; then
  echo "🐛 CAA records present but Amazon not authorized — cert issuance WILL fail"
  echo "Add CAA records for amazon.com + amazontrust.com (issue + issuewild) first"
  exit 1
fi
```

**Time wasted on this:** ~25 min (the test project migration). Two failed cert issuances before the CAA records propagated.

---

# 🔴 20. Mastra PgDB rejects RDS cert: `self-signed certificate in certificate chain`

**Symptom:** ECS task crashes at boot, container exits within 5 seconds. CloudWatch logs show:

```
MastraError: self-signed certificate in certificate chain: self-signed certificate in certificate chain
  at PgDB.createTable (file:///app/node_modules/@mastra/pg/dist/index.js:2650:13)
```

repeated 20-30+ times (once per workflow registered in `apps/api/agent/workflows/`).

**Where:** Phase 4 first task launch, ONLY when migrating a Mastra-using app from Fly internal Postgres (WireGuard `.flycast`) to RDS.

**Why this happens:**
- Fly's internal Postgres used WireGuard tunnel, so DATABASE_URL never needed TLS
- RDS forces TLS, default DATABASE_URL has `?sslmode=require`
- Mastra's PgDB driver (under the hood: `node-postgres` `pg`) does full chain verification
- Amazon's RDS cert chain (`rds-ca-rsa2048-g1`) is NOT in Node's default trust store
- Verification fails with the misleading "self-signed" error

**Fix #1 (fast, what the test project did):** change `sslmode=require` → `sslmode=no-verify` in DATABASE_URL. Connection is still TLS-encrypted, just doesn't verify chain. Safe inside VPC where ECS and RDS share private subnets — no MitM possible.

```bash
# Update secret value
CURRENT=$(aws secretsmanager get-secret-value --secret-id $SECRET --query SecretString --output text)
NEW=$(echo "$CURRENT" | jq --arg url "$(echo "$CURRENT" | jq -r '.DATABASE_URL' | sed 's|sslmode=require|sslmode=no-verify|')" '.DATABASE_URL = $url')
aws secretsmanager put-secret-value --secret-id $SECRET --secret-string "$NEW"

# Force task restart to re-fetch secret
aws ecs update-service --cluster $CLUSTER --service $SERVICE --force-new-deployment
```

**Fix #2 (proper, do this when time permits):** mount RDS CA bundle in the Dockerfile, set `NODE_EXTRA_CA_CERTS`, restore `sslmode=verify-full`:

```dockerfile
RUN curl -fsSL -o /etc/ssl/rds-ca-rsa2048-g1.pem \
  https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem
ENV NODE_EXTRA_CA_CERTS=/etc/ssl/rds-ca-rsa2048-g1.pem
```

Then DATABASE_URL stays `sslmode=verify-full`.

**Preflight check** to add at the top of Phase 4:

```bash
# If app uses Mastra + Postgres, document the sslmode choice up front
if grep -qE "@mastra/pg" $PROJECT/package.json 2>/dev/null; then
  echo "🟡 Mastra detected — DATABASE_URL must use sslmode=no-verify"
  echo "   OR Dockerfile must mount RDS CA bundle. Choose now."
fi
```

**Time wasted on this:** ~10 min. Caught quickly because the crash happens in first 5s of boot, very obvious in CloudWatch.

---

# 🟡 21. RDS `publicly-accessible=true` is a no-op if subnet group has no public subnets

**Symptom:** You set `publicly_accessible = true` on the RDS instance to enable a one-shot restore from your sandbox. AWS accepts the change. Modify completes. But the instance still has no public endpoint, no public DNS, can't be reached from outside the VPC.

**Where:** Phase 3 DB restore, when trying to do it from outside the VPC.

**Why this happens:** `PubliclyAccessible` only ENABLES the feature. The DB still uses its **subnet group** for placement. If the subnet group only contains private subnets (no IGW route), there's no public IP to assign. AWS doesn't error — just silently does nothing.

**Fix:** don't try to make RDS public. Instead, run a one-shot ECS Fargate task in the **private subnets with the ECS SG** (which already has ingress to RDS). The task pulls the dump from S3 and runs pg_restore in-VPC.

This is what the test project ended up doing (Phase 3 Option A). Total task time ~3 min, cost <$0.01.

**Code:**
```bash
# Upload dump to S3
aws s3 cp your-app.dump s3://your-migrate-tmp/your-app.dump

# Register one-shot task def
aws ecs register-task-definition --cli-input-json '{
  "family": "your-prod-db-migrate",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "1024", "memory": "2048",
  "executionRoleArn": "<task-exec-role>",
  "taskRoleArn": "<task-runtime-role-with-s3-read>",
  "containerDefinitions": [{
    "name": "restore",
    "image": "public.ecr.aws/docker/library/postgres:17",
    "essential": true,
    "command": ["sh", "-c", "apt-get update && apt-get install -y curl awscli && aws s3 cp s3://your-migrate-tmp/your-app.dump /tmp/dump && PGPASSWORD=$DB_PASS pg_restore -h $DB_HOST -U $DB_USER -d your-app --no-owner --no-acl --jobs=4 /tmp/dump"],
    "secrets": [...DB creds from Secrets Manager...]
  }]
}'

# Run it in private subnets with ECS SG (which can reach RDS)
aws ecs run-task --cluster $CLUSTER --task-definition your-prod-db-migrate \
  --launch-type FARGATE \
  --network-configuration "awsvpcConfiguration={subnets=[...private...],securityGroups=[$ECS_SG],assignPublicIp=DISABLED}"
```

**Time wasted on this:** ~15 min (the test project Phase 3, attempted Option B before pivoting to Option A).

---

# 🔴 22. Prisma DATABASE_URL params + sslmode values libpq rejects

**Symptom:** Postgres backups fail every hour with sequential errors:
```
# First failure mode:
pg_dump: error: invalid URI query parameter: "schema"

# After stripping schema, you'll then hit:
pg_dump: error: invalid sslmode value: "no-verify"
```

**Where:** Phase 3+ (any time pg_dump uses the DATABASE_URL stored in Secrets Manager). Surfaces hours/days after migration when scheduled backups start running. Two-stage failure — fixing the first reveals the second.

**Root cause:**

Prisma's connection string accepts:
- Query params libpq doesn't know: `schema`, `connection_limit`, `pool_timeout`, `socket_timeout`, `statement_cache_size`, `pgbouncer`
- `sslmode=no-verify` (TLS without cert validation — Prisma-specific synonym)

libpq's allowed sslmode values are ONLY: `disable`, `allow`, `prefer`, `require`, `verify-ca`, `verify-full`.

On Fly, the DATABASE_URL was set by the Fly Postgres provisioner without these Prisma-isms. On AWS Phase 3, we wrote the Secrets Manager entry with `?schema=public&sslmode=no-verify` because it's explicit/good-practice. Bites us when any libpq tool runs.

**Fix (both required):**

```typescript
// 1. Strip Prisma-only params
const PRISMA_ONLY_QUERY_PARAMS = new Set([
  "schema",
  "connection_limit",
  "pool_timeout",
  "socket_timeout",
  "statement_cache_size",
  "pgbouncer",
]);

// 2. Translate Prisma sslmode synonyms
const SSLMODE_TRANSLATIONS: Record<string, string> = {
  "no-verify": "require", // TLS connect but skip CA chain check
};

function cleanUrlForLibpq(url: string): string {
  const u = new URL(url);
  for (const key of [...u.searchParams.keys()]) {
    if (PRISMA_ONLY_QUERY_PARAMS.has(key)) u.searchParams.delete(key);
  }
  const sslmode = u.searchParams.get("sslmode");
  if (sslmode && SSLMODE_TRANSLATIONS[sslmode]) {
    u.searchParams.set("sslmode", SSLMODE_TRANSLATIONS[sslmode]);
  }
  return u.toString();
}
```

Apply to ANY tool using libpq directly: `pg_dump`, `pg_restore`, `psql`, `pg_basebackup`, `pgcli`, `pg_repack`. Prisma is the only place these synonyms belong.

🔴 **Watch for this immediately after Phase 3.** Trigger a manual backup right after secrets are loaded — don't wait for the first cron to find out hours later.

References:
- https://www.postgresql.org/docs/current/libpq-connect.html#LIBPQ-PARAMKEYWORDS
- https://www.prisma.io/docs/orm/reference/connection-urls
- Real incidents from production: schema= strip + sslmode translate

---

# 🔴 23. ECS doesn't auto-poll ECR — push ≠ deploy

**Symptom:** Pushed new image to ECR `:latest` tag, image is visible in registry, but the running ECS task is still using the OLD code. New bug-fix doesn't take effect even minutes after CI shows green.

**Where:** Every CI/CD workflow after Phase 4+5 that pushes to ECR without also calling `aws ecs update-service`.

**Root cause:** ECS task definitions reference image tags by name (`:latest`), but the task uses whatever **digest** was current at task LAUNCH time. ECR tag mutability doesn't propagate to running tasks. No background poller, no webhook, nothing — ECS is a static reference until you explicitly tell it to swap.

**The classic anti-pattern:**

```yaml
# .github/workflows/aws-build.yml (Phase 2 version)
- name: Build + push to ECR
  uses: docker/build-push-action@v6
  with:
    push: true
    tags: ${{ env.ECR }}/api:latest

- name: Summary
  run: echo "Image pushed. Ready for ECS to pick up." # 🔴 IT WON'T
```

**Symptom in real life:**

Bug fix merged at 13:30. CI workflow "AWS Build & Push to ECR" goes green at 13:33. You celebrate. Three hours later, the bug is STILL biting production because the ECS task launched on 2026-05-22 13:20 and hasn't restarted.

**Fix:** Every CI workflow that pushes `:latest` MUST follow with:

```bash
# 1. Force ECS to do a rolling deploy with the new :latest
aws ecs update-service \
  --cluster $CLUSTER \
  --service $SERVICE \
  --force-new-deployment \
  --no-cli-pager

# 2. Wait for stabilization
aws ecs wait services-stable \
  --cluster $CLUSTER \
  --services $SERVICE

# 3. 🔴 VERIFY the digest actually swapped (catches edge cases
#    where force-new-deployment claims success but didn't swap)
EXPECTED=$(aws ecr describe-images \
  --repository-name $REPO --image-ids imageTag=latest \
  --query 'imageDetails[0].imageDigest' --output text)

TASK=$(aws ecs list-tasks --cluster $CLUSTER --service-name $SERVICE \
  --query 'taskArns[0]' --output text)

RUNNING=$(aws ecs describe-tasks --cluster $CLUSTER --tasks $TASK \
  --query 'tasks[0].containers[0].imageDigest' --output text)

[[ "$RUNNING" == "$EXPECTED" ]] || { echo "❌ digest mismatch"; exit 1; }
```

🟡 **The Phase 2 template in this skill** (templates/github-workflows/deploy-api.yml) DOES include the force-new-deployment step. Make sure any project-specific workflow inherits it.

🟡 **Deploy to multiple services if image is shared.** If api + scheduler both use the same image, deploy both. They can have separate task definitions but pull from the same ECR repo.

References:
- AWS docs: https://docs.aws.amazon.com/AmazonECS/latest/developerguide/deployment-type-ecs.html#deployment-type-ecs-rolling-update
- Real incident: backup fix sat in ECR for hours before manual force-deploy

---

# Summary: what to copy-paste into every migration

```bash
# Pre-deploy verification template
echo "=== Pre-deploy checks ==="
echo "1. ECR image"
aws ecr describe-images --repository-name $REPO --image-ids imageTag=latest

echo "2. Task def revision"
aws ecs describe-task-definition --task-definition $PROJECT-$ENV-api | jq '.taskDefinition.revision'

echo "3. Service health"
aws ecs describe-services --cluster $CLUSTER --services $SERVICE \
  | jq '.services[0] | {running: .runningCount, desired: .desiredCount, deployments: (.deployments | length)}'

echo "4. ALB target health"
aws elbv2 describe-target-health --target-group-arn $TG_ARN

echo "5. Aurora status"
aws rds describe-db-clusters --db-cluster-identifier $CLUSTER_ID | jq '.DBClusters[0].Status'
```

Run this before AND after every cutover.
