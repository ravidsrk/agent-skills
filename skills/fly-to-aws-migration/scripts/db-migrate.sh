#!/usr/bin/env bash
# Phase 4 cutover window: pg_dump from Fly → restore to Aurora.
# (Run during the maintenance window — see README Phase 4+5. Phase 3 is
#  schema-only; secrets are scripts/secrets-migrate.sh.)
#
# Usage:
#   FLY_PG_PASSWORD=... ./db-migrate.sh <fly-pg-app> <aurora-secret-name> [db-name]
# Example:
#   FLY_PG_PASSWORD=... ./db-migrate.sh your-app-db your-app/prod/db your_app
#
# Args/env:
#   <db-name>          database inside the Fly PG cluster (default: postgres,
#                      or set FLY_PG_DB)
#   FLY_PG_PASSWORD    password of the 'postgres' user (printed at cluster
#                      creation; reset via 'flyctl postgres users' if lost)
#
# Everything runs over one 'flyctl proxy' WireGuard tunnel — the same local
# psql/pg_dump toolchain the restore already needs, no in-container tricks.

set -euo pipefail

FLY_PG="${1:?fly pg app name required}"
AURORA_SECRET="${2:?aurora secret name required}"
FLY_PG_DB="${3:-${FLY_PG_DB:-postgres}}"
: "${FLY_PG_PASSWORD:?FLY_PG_PASSWORD env var required (Fly 'postgres' user password)}"

command -v pg_dump >/dev/null || { echo "ERROR: pg_dump not on PATH" >&2; exit 1; }
command -v psql >/dev/null    || { echo "ERROR: psql not on PATH" >&2; exit 1; }

DUMP_FILE="/tmp/fly-dump-$(date +%Y%m%d-%H%M%S).sql"
ROW_BEFORE="/tmp/fly-rowcounts-before.txt"
ROW_AFTER="/tmp/aurora-rowcounts-after.txt"
# Password goes via PGPASSWORD, never inside the URL — a URL in argv is
# visible to every user on the box via ps during the maintenance window.
FLY_URL="postgresql://postgres@localhost:5433/${FLY_PG_DB}"
export PGPASSWORD="$FLY_PG_PASSWORD"

echo "=== Step 0: Open proxy to Fly Postgres (localhost:5433) ==="
flyctl proxy 5433:5432 -a "$FLY_PG" &
PROXY_PID=$!
trap 'kill "$PROXY_PID" 2>/dev/null || true' EXIT
sleep 5

echo ""
echo "=== Step 1: Capture row counts from Fly (baseline) ==="
PGSSLMODE=prefer psql "$FLY_URL" -c "
  SELECT schemaname || '.' || tablename AS table_name, n_live_tup
  FROM pg_stat_user_tables
  ORDER BY 1;
" > "$ROW_BEFORE"
echo "  Saved to $ROW_BEFORE ($(wc -l < $ROW_BEFORE) tables)"

echo ""
echo "=== Step 2: pg_dump from Fly ==="
PGSSLMODE=prefer pg_dump "$FLY_URL" \
  --no-owner --no-acl --schema=public --format=plain > "$DUMP_FILE"

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
