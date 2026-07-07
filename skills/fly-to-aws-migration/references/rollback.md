# Rollback procedures — every phase, <5 min recovery

Each phase has a clean rollback path. If anything goes wrong, you can always get back to Fly within a few minutes.

# Pre-flight: what to keep before each phase

| Before phase | Keep this | Purpose |
|---|---|---|
| 0 (audit) | nothing | read-only |
| 1 (foundation) | terraform.tfstate | recreate if state lost |
| 2 (code prep) | Fly app `:latest` image | restore code via `flyctl deploy` |
| 3 (secrets+DB) | Fly Postgres + Fly secrets unchanged | nothing destructive yet |
| 4+5 (API cutover) | Fly machines STOPPED not destroyed | one command to restart |
| 6 (static sites) | Fly static apps STOPPED not destroyed | one command to restart |
| 7 (cache layer) | nothing | pure additive |

# Phase 1 rollback: foundation IaC

**Trigger:** terraform apply fails or you change your mind.

```bash
cd .migration/terraform/
terraform destroy
```

🟢 No user impact. Fly is still serving everything.

# Phase 2 rollback: code prep

**Trigger:** Dockerfile changes break local dev or Fly deploy.

```bash
git revert <phase-2-commit>
flyctl deploy -a <fly-api>  # restores Fly with previous Dockerfile
```

🟢 ECR images can stay (cost is negligible).

# Phase 3 rollback: secrets + DB

**Trigger:** Aurora data import has issues, schema doesn't match, etc.

```bash
# Drop and recreate Aurora database (data is gone, Fly is untouched)
psql "$AURORA_URL/postgres" -c "DROP DATABASE $DB_NAME"
psql "$AURORA_URL/postgres" -c "CREATE DATABASE $DB_NAME"

# Secrets: leave them in Secrets Manager; cost $3.20/mo to retain 8 groups
# OR delete:
for SECRET in db llm email social payments data auth telemetry; do
  aws secretsmanager delete-secret --secret-id "$PROJECT/$ENV/$SECRET" --force-delete-without-recovery
done
```

🟢 No user impact. Fly DB is still authoritative.

# Phase 4+5 rollback: API cutover

🔴 **The critical one.** If AWS API is broken or behaving incorrectly:

```bash
# 1. Flip DNS back to Fly (atomic, <5s via Cloudflare proxied)
ZONE_ID="..."
API_RECORD_ID="..."
FLY_DNS="<fly-app>.fly.dev"

curl -sSf -X PATCH -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
  -H "Content-Type: application/json" \
  "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records/$API_RECORD_ID" \
  -d "{\"content\":\"$FLY_DNS\",\"proxied\":true}"

# 2. Restart Fly machines (they were just stopped, not destroyed)
flyctl scale count 2 -a <fly-api>

# 3. Verify (within 30s)
for i in 1 2 3 4 5; do
  curl -sS https://api.yourdomain.com/health
  sleep 2
done
```

**Data consideration:** If users wrote data to Aurora between cutover and rollback, you need to dump+restore that data back to Fly:

```bash
# Get the time of cutover and rollback
CUTOVER_TIME="2026-05-22 12:00:00"
ROLLBACK_TIME="2026-05-22 12:09:00"

# Dump writes from Aurora during the window
psql "$AURORA_URL" -c "
  SELECT * FROM your_table 
  WHERE created_at BETWEEN '$CUTOVER_TIME' AND '$ROLLBACK_TIME'
" > /tmp/recovered.txt

# Manually merge to Fly (or via psql COPY)
```

🟡 **If your downtime window was short and you didn't take writes** during AWS-active time, no data merge needed.

# Phase 6 rollback: static sites cutover

**Trigger:** Static sites broken on AWS, missing routes, etc.

```bash
# 1. Flip DNS for each domain back to Fly
ZONE_ID="..."

# www
curl -X PATCH ... "$ZONE_ID/dns_records/$WWW_ID" \
  -d '{"content":"<fly-web>.fly.dev"}'

# apex (recreate A + AAAA from your backup of original DNS)
curl -X POST ... "$ZONE_ID/dns_records" \
  -d '{"type":"A","name":"yourdomain.com","content":"<original-fly-ip>","proxied":true}'
curl -X POST ... "$ZONE_ID/dns_records" \
  -d '{"type":"AAAA","name":"yourdomain.com","content":"<original-fly-ipv6>","proxied":true}'

# Delete the CNAME we created at apex
curl -X DELETE ... "$ZONE_ID/dns_records/$APEX_CNAME_ID"

# docs
curl -X PATCH ... "$ZONE_ID/dns_records/$DOCS_ID" \
  -d '{"content":"<fly-docs>.fly.dev"}'

# 2. Restart Fly static apps
flyctl scale count 2 -a <fly-web>
flyctl scale count 2 -a <fly-docs>
```

🟢 **No data loss possible** — static sites are stateless.

# Phase 7 rollback: cache layer

🟢 **Pure additive change**. If you don't like it:

```bash
# Disable tiered cache
curl -X PATCH ... "$ZONE_ID/argo/tiered_caching" -d '{"value":"off"}'

# Delete cache rule (or set enabled=false in the ruleset)
curl -X DELETE ... "$ZONE_ID/rulesets/$RULESET_ID"

# OR via terraform
cd .migration/terraform/
terraform destroy -target=cloudflare_ruleset.static_sites_cache
terraform destroy -target=cloudflare_tiered_cache.main
```

Pages return to ~300ms TTFB but still work normally.

# Full migration rollback (everything → Fly)

If at any point you want to fully revert and stay on Fly indefinitely:

```bash
# 1. Flip ALL DNS records back to Fly equivalents (use the audit data from Phase 0)
cat /tmp/fly-dns.txt | while IFS='|' read RECORD_ID TYPE NAME CONTENT PROXIED; do
  # Restore each original record
  curl -X PATCH ... "$ZONE_ID/dns_records/$RECORD_ID" \
    -d "{\"content\":\"$CONTENT\"}"
done

# 2. Restart all Fly apps
flyctl scale count 2 -a <fly-api>
flyctl scale count 2 -a <fly-web>
flyctl scale count 2 -a <fly-docs>

# 3. Take final snapshot of Aurora before destroying (in case you want to come back)
aws rds create-db-cluster-snapshot \
  --db-cluster-identifier $PROJECT-$ENV-aurora \
  --db-cluster-snapshot-identifier $PROJECT-$ENV-final-$(date +%Y%m%d)

# 4. Destroy AWS infrastructure
cd .migration/terraform/
terraform destroy
```

🟢 **Total time:** 10-30 min depending on how many domains you have.

🟢 **Data preservation:** Fly Postgres has been untouched throughout. Aurora snapshot exists if you ever want to revert the data direction.

# Disaster scenarios

## Scenario A: ECS task won't start, Fly already scaled to 0

```bash
# Quick recovery
flyctl scale count 2 -a <fly-api>  # Fly machines come back in 30-60s

# Flip DNS back
curl -X PATCH ... "$ZONE_ID/dns_records/$API_RECORD_ID" \
  -d '{"content":"<fly-app>.fly.dev"}'

# Total recovery: ~2 min
```

## Scenario B: Aurora is corrupted after Phase 3 data load

```bash
# Restore from snapshot (you took one before the load, right?)
aws rds restore-db-cluster-from-snapshot \
  --db-cluster-identifier $PROJECT-$ENV-aurora-restored \
  --snapshot-identifier <snapshot-id>

# OR re-dump from Fly (Fly Postgres is still authoritative until Phase 4+5).
# `flyctl postgres connect` opens psql — it can't run pg_dump. Use flyctl proxy
# + local pg_dump instead. scripts/db-migrate.sh does this end-to-end:
scripts/db-migrate.sh --schema-only \
  --fly-app <fly-db-app> \
  --aurora-secret $PROJECT/$ENV/db
```

## Scenario C: Bun + Prisma WASM silent outage (Gotcha #4)

```bash
# Get the CURRENT task definition revision (the one you want to roll back FROM).
CURRENT=$(aws ecs describe-task-definition \
  --task-definition $PROJECT-$ENV-api \
  --query 'taskDefinition.revision' --output text)

if ! [[ "$CURRENT" =~ ^[0-9]+$ ]]; then
  echo "🔴 Couldn't read current revision (got: $CURRENT). Aborting."
  exit 1
fi
if [ "$CURRENT" -le 1 ]; then
  echo "🔴 Current revision is $CURRENT — no prior revision to roll back to."
  echo "   Deploy a good image via 'aws ecs update-service --force-new-deployment' instead."
  exit 1
fi

PREV=$((CURRENT - 1))

# Verify the previous revision still exists (some accounts prune revisions).
if ! aws ecs describe-task-definition \
     --task-definition "$PROJECT-$ENV-api:$PREV" >/dev/null 2>&1; then
  echo "🔴 Revision $PREV was pruned. Pick a specific revision from:"
  aws ecs list-task-definitions --family-prefix "$PROJECT-$ENV-api" \
    --sort DESC --max-items 10
  exit 1
fi

aws ecs update-service \
  --cluster $CLUSTER \
  --service $SERVICE \
  --task-definition $PROJECT-$ENV-api:$PREV \
  --force-new-deployment

# Recovery: ~2 min
```

## Scenario D: Cloudflare API outage during cutover

🟡 If Cloudflare API is down, you can't flip DNS. Options:

1. **Wait** — Cloudflare outages are usually <30 min
2. **Use AWS Route 53** as backup DNS (have it pre-configured with same records, point NS records at it from registrar — but this is a big change for a small risk)
3. **Bypass Cloudflare temporarily** — direct CNAME from your domain registrar to the ALB DNS (loses DDoS protection but works)

## Scenario E: ALB cert hasn't validated yet

```bash
# Check ACM validation
aws acm describe-certificate --certificate-arn $CERT_ARN \
  | jq '.Certificate | {Status, DomainValidationOptions}'

# If status is PENDING_VALIDATION, check Cloudflare for the validation records
# Common cause: Cloudflare proxy enabled on the validation CNAME (needs proxied=false)

# Force re-validation by deleting/recreating the records
```

# The golden rule

🔴 **Do NOT run `flyctl apps destroy` until at least 48h of stable AWS production.** Until you run that command, rollback is always one DNS flip + one `flyctl scale count 2` away.
