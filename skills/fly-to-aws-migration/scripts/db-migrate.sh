#!/usr/bin/env bash
# Phase 3: pg_dump from Fly → restore to Aurora.
#
# Usage:
#   ./db-migrate.sh <fly-pg-app> <aurora-secret-name>
# Example:
#   ./db-migrate.sh your-app-db your-app/prod/db

set -euo pipefail

FLY_PG="${1:?fly pg app name required}"
AURORA_SECRET="${2:?aurora secret name required}"

DUMP_FILE="/tmp/fly-dump-$(date +%Y%m%d-%H%M%S).sql"
ROW_BEFORE="/tmp/fly-rowcounts-before.txt"
ROW_AFTER="/tmp/aurora-rowcounts-after.txt"

echo "=== Step 1: Capture row counts from Fly (baseline) ==="
flyctl postgres connect -a "$FLY_PG" -- -c "
  SELECT schemaname || '.' || tablename AS table_name, n_live_tup
  FROM pg_stat_user_tables
  ORDER BY 1;
" > "$ROW_BEFORE"
echo "  Saved to $ROW_BEFORE ($(wc -l < $ROW_BEFORE) tables)"

echo ""
echo "=== Step 2: pg_dump from Fly ==="
# Run pg_dump inside Fly's container (no SSL issues)
flyctl postgres connect -a "$FLY_PG" -- -c "
  pg_dump --no-owner --no-acl --schema=public --format=plain $POSTGRES_DB
" > "$DUMP_FILE" || {
  echo "🟡 In-container pg_dump failed. Trying via SSH tunnel..."
  # Alternative: use flyctl proxy + local pg_dump
  flyctl proxy 5433:5432 -a "$FLY_PG" &
  PROXY_PID=$!
  sleep 5
  PGSSLMODE=no-verify pg_dump \
    "postgresql://postgres:$FLY_PG_PASSWORD@localhost:5433/$FLY_PG_DB" \
    --no-owner --no-acl --schema=public > "$DUMP_FILE"
  kill $PROXY_PID
}

DUMP_SIZE=$(du -h "$DUMP_FILE" | awk '{print $1}')
echo "  Dump size: $DUMP_SIZE"

echo ""
echo "=== Step 3: Get Aurora URL from Secrets Manager ==="
AURORA_URL=$(aws secretsmanager get-secret-value \
  --secret-id "$AURORA_SECRET" \
  --query 'SecretString' --output text \
  | jq -r '.DATABASE_URL')

if [ -z "$AURORA_URL" ] || [ "$AURORA_URL" = "null" ]; then
  echo "🔴 Failed to get Aurora URL. Check secret name and IAM perms."
  exit 1
fi

echo "  Aurora endpoint: $(echo $AURORA_URL | sed 's|.*@||' | cut -d/ -f1)"

echo ""
echo "=== Step 4: Restore to Aurora ==="
echo "🔴 This may take several minutes. Watch progress..."
psql "$AURORA_URL" < "$DUMP_FILE" 2>&1 | tail -20 || {
  echo "🔴 Restore failed. Investigate."
  exit 1
}

echo ""
echo "=== Step 5: Capture Aurora row counts ==="
psql "$AURORA_URL" -c "
  SELECT schemaname || '.' || tablename AS table_name, n_live_tup
  FROM pg_stat_user_tables
  ORDER BY 1;
" > "$ROW_AFTER"

echo ""
echo "=== Step 6: Diff row counts ==="
if diff <(sort "$ROW_BEFORE") <(sort "$ROW_AFTER") > /tmp/rowcount-diff.txt; then
  echo "🟢 Row counts match exactly!"
else
  echo "🟡 Row count differences:"
  cat /tmp/rowcount-diff.txt
  echo ""
  echo "  Some difference is OK if Fly is taking writes during dump."
  echo "  Review the diff above. If schema-only changes, fine."
  echo "  If significant data loss, re-run dump+restore in a maintenance window."
fi

echo ""
echo "=== Done. Dump preserved at $DUMP_FILE ==="
echo ""
echo "Next steps:"
echo "  - Run sanity queries on Aurora to verify app-specific data shape"
echo "  - Run any post-migration database migrations (Prisma, etc.)"
echo "  - Move to Phase 4+5 (API cutover)"
