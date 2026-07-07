#!/usr/bin/env bash
# Phase 3 / Phase 4: dump from Fly Postgres → restore to Aurora with real parity.
#
# Modes:
#   --schema-only   (default) Phase 3. Restores schema, no data. Safe to run
#                   with production traffic on Fly.
#   --data-only     Phase 4 delta window. Requires --i-have-frozen-writes and
#                   an already-loaded schema on Aurora.
#   --full          Alternative single-shot (Phase 3 collapsed with Phase 4).
#                   Requires --i-have-frozen-writes.
#
# Usage:
#   ./db-migrate.sh --schema-only \
#     --fly-app <fly-pg-app> \
#     --aurora-secret <secretsmanager-secret-name>
#
#   ./db-migrate.sh --data-only \
#     --fly-app <fly-pg-app> \
#     --aurora-secret <aurora-secret-name> \
#     --i-have-frozen-writes
#
# Required env (validated up front, no undefined-var crashes under set -u):
#   FLY_DB_USER      Postgres user on the Fly source (typically 'postgres')
#   FLY_DB_NAME      Database name on Fly (defaults to FLY_DB_USER if unset)
#
# Optional env:
#   PROXY_LOCAL_PORT Local port used by `flyctl proxy` (default 5433)
#   FLY_DB_PASSWORD  Overrides interactive prompt for the Fly proxy pg_dump path.
#                    If unset, you'll be prompted (avoids leaking into argv/logs).

set -euo pipefail

MODE="--schema-only"
FLY_PG=""
AURORA_SECRET=""
FROZEN="no"

usage() {
  sed -n '2,30p' "$0" | sed 's/^# //; s/^#//'
  exit "${1:-1}"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --schema-only|--data-only|--full)   MODE="$1"; shift ;;
    --fly-app)                          FLY_PG="${2:?}"; shift 2 ;;
    --aurora-secret)                    AURORA_SECRET="${2:?}"; shift 2 ;;
    --i-have-frozen-writes)             FROZEN="yes"; shift ;;
    -h|--help)                          usage 0 ;;
    *)                                  echo "unknown arg: $1" >&2; usage 1 ;;
  esac
done

[ -n "$FLY_PG" ]        || { echo "🔴 --fly-app required" >&2; exit 2; }
[ -n "$AURORA_SECRET" ] || { echo "🔴 --aurora-secret required" >&2; exit 2; }
: "${FLY_DB_USER:?FLY_DB_USER env var required (Postgres user on the Fly source)}"
FLY_DB_NAME="${FLY_DB_NAME:-$FLY_DB_USER}"
PROXY_LOCAL_PORT="${PROXY_LOCAL_PORT:-5433}"

TS="$(date +%Y%m%d-%H%M%S)"
DUMP_FILE="/tmp/fly-dump-$MODE-$TS.sql"
RESTORE_LOG="/tmp/aurora-restore-$MODE-$TS.log"
ROW_BEFORE="/tmp/fly-counts-$TS.txt"
ROW_AFTER="/tmp/aurora-counts-$TS.txt"

# ── Refuse to touch data without an explicit confirmation ──
if { [ "$MODE" = "--data-only" ] || [ "$MODE" = "--full" ]; } && [ "$FROZEN" != "yes" ]; then
  cat >&2 <<EOF
🔴 --data-only and --full move production data.
   Refusing to proceed without --i-have-frozen-writes.

   Before you pass that flag, make sure:
     1. Fly API app is scaled to 0 (or read-only), so no new writes hit Fly.
     2. Users are in a maintenance window.
     3. You've read references/phases.md → Phase 4 (pre-warm ECS first).
EOF
  exit 3
fi

echo "=== Mode: $MODE  |  Fly app: $FLY_PG  |  Aurora secret: $AURORA_SECRET ==="

# ── Real per-table row count. Uses query_to_xml + xpath so we don't have to
#    trust n_live_tup (a statistic that is 0 immediately after pg_restore). ──
row_counts() {
  # Args: <connection-arg>...
  # Emits: schema.table<TAB>count, sorted.
  psql "$@" -X -A -F $'\t' -t -c "
    SELECT
      n.nspname || '.' || c.relname AS table_name,
      (xpath('/row/c/text()',
             query_to_xml(
               format('SELECT count(*) AS c FROM %I.%I', n.nspname, c.relname),
               false, false, ''
             ))
      )[1]::text::bigint AS row_count
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE c.relkind = 'r'
      AND n.nspname NOT IN ('pg_catalog','information_schema')
    ORDER BY 1;
  " | sort
}

# ── Get the Aurora URL (LIBPQ variant — libpq-compatible sslmode). ──
echo ""
echo "=== Fetching Aurora URL from Secrets Manager ==="
SECRET_JSON=$(aws secretsmanager get-secret-value \
  --secret-id "$AURORA_SECRET" \
  --query 'SecretString' --output text)
AURORA_URL=$(echo "$SECRET_JSON" | jq -r '.DATABASE_URL_LIBPQ // .DATABASE_URL')

if [ -z "$AURORA_URL" ] || [ "$AURORA_URL" = "null" ]; then
  echo "🔴 Failed to read DATABASE_URL / DATABASE_URL_LIBPQ from $AURORA_SECRET." >&2
  exit 4
fi

# libpq rejects sslmode=no-verify (Prisma-only). Translate on the fly.
if echo "$AURORA_URL" | grep -q "sslmode=no-verify"; then
  AURORA_URL=$(echo "$AURORA_URL" | sed 's|sslmode=no-verify|sslmode=require|')
  echo "🟡 Translated sslmode=no-verify → sslmode=require for libpq"
fi

echo "  Aurora endpoint: $(echo "$AURORA_URL" | sed 's|.*@||' | cut -d/ -f1)"

# ── Dump from Fly. We use `flyctl proxy` (local pg_dump) rather than
#    `flyctl postgres connect` — the latter opens a psql shell and cannot run
#    pg_dump. Requires local pg_dump on PATH. ──
echo ""
echo "=== Dumping from Fly ($MODE) via flyctl proxy → local pg_dump ==="

if [ -z "${FLY_DB_PASSWORD:-}" ]; then
  read -r -s -p "Fly Postgres password for user '$FLY_DB_USER' (input hidden): " FLY_DB_PASSWORD
  echo ""
fi

flyctl proxy "$PROXY_LOCAL_PORT:5432" -a "$FLY_PG" >/tmp/flyctl-proxy.log 2>&1 &
PROXY_PID=$!
trap 'kill $PROXY_PID 2>/dev/null || true' EXIT

# Wait for the proxy to open the local port. Poll instead of a fixed sleep.
for _ in $(seq 1 30); do
  if (echo > "/dev/tcp/127.0.0.1/$PROXY_LOCAL_PORT") 2>/dev/null; then break; fi
  sleep 1
done

# Assemble the pg_dump command. The password is passed via PGPASSWORD (env,
# not argv, so it doesn't leak into ps output). --no-owner --no-acl keep the
# dump target-agnostic.
DUMP_OPTS=(--no-owner --no-acl)
case "$MODE" in
  --schema-only) DUMP_OPTS+=(--schema-only) ;;
  --data-only)   DUMP_OPTS+=(--data-only --disable-triggers) ;;
  --full)        : ;;  # both
esac

FLY_CONN="host=127.0.0.1 port=$PROXY_LOCAL_PORT user=$FLY_DB_USER dbname=$FLY_DB_NAME sslmode=disable"

echo "  Running pg_dump ${DUMP_OPTS[*]} …"
PGPASSWORD="$FLY_DB_PASSWORD" pg_dump "${DUMP_OPTS[@]}" "$FLY_CONN" > "$DUMP_FILE"
DUMP_SIZE=$(du -h "$DUMP_FILE" | awk '{print $1}')
echo "  Dump size: $DUMP_SIZE ($DUMP_FILE)"

# Capture Fly row counts for post-restore parity (only for data phases).
if [ "$MODE" != "--schema-only" ]; then
  echo ""
  echo "=== Capturing Fly row counts (real COUNT(*), not n_live_tup) ==="
  PGPASSWORD="$FLY_DB_PASSWORD" row_counts "$FLY_CONN" > "$ROW_BEFORE"
  echo "  $(wc -l < "$ROW_BEFORE") tables snapshotted"
fi

# Drop the proxy — done reading.
kill "$PROXY_PID" 2>/dev/null || true
trap - EXIT

# ── Restore into Aurora. Single transaction, abort on first error. ──
echo ""
echo "=== Restoring into Aurora ==="
if psql -v ON_ERROR_STOP=1 -1 -f "$DUMP_FILE" "$AURORA_URL" > "$RESTORE_LOG" 2>&1; then
  echo "🟢 Restore succeeded (log: $RESTORE_LOG)"
else
  echo "🔴 Restore FAILED. Last 40 lines of $RESTORE_LOG:" >&2
  tail -40 "$RESTORE_LOG" >&2
  exit 5
fi

# ── Parity check. ──
if [ "$MODE" = "--schema-only" ]; then
  # After --schema-only, both sides must report 0 rows for every table.
  echo ""
  echo "=== Verifying schema-only restore ==="
  psql "$AURORA_URL" -X -A -t -c \
    "SELECT COUNT(*) FROM pg_tables WHERE schemaname NOT IN ('pg_catalog','information_schema');" \
    | tr -d ' ' > /tmp/aurora-table-count.txt
  echo "  Aurora user-tables: $(cat /tmp/aurora-table-count.txt)"
  echo "🟢 Schema loaded. Data goes in Phase 4 (--data-only)."
else
  echo ""
  echo "=== Verifying data parity (real COUNT(*) per table) ==="
  # ANALYZE so pg_stat_user_tables would agree, but we don't rely on it.
  psql "$AURORA_URL" -X -A -c "ANALYZE;" > /dev/null
  row_counts "$AURORA_URL" > "$ROW_AFTER"

  if diff -u "$ROW_BEFORE" "$ROW_AFTER" > /tmp/rowcount-diff-"$TS".txt; then
    echo "🟢 Row counts match exactly across $(wc -l < "$ROW_BEFORE") tables"
  else
    echo "🔴 Row count DRIFT — review /tmp/rowcount-diff-$TS.txt:" >&2
    head -40 /tmp/rowcount-diff-"$TS".txt >&2
    exit 6
  fi
fi

echo ""
echo "=== Done ==="
echo "  Dump: $DUMP_FILE"
echo "  Restore log: $RESTORE_LOG"
[ "$MODE" != "--schema-only" ] && echo "  Row counts: $ROW_BEFORE  vs  $ROW_AFTER"
echo ""
case "$MODE" in
  --schema-only) echo "Next: proceed to Phase 4 (see references/phases.md). Warm ECS first, then run --data-only." ;;
  --data-only)   echo "Next: aws ecs update-service --force-new-deployment; then scripts/cutover-dns.sh." ;;
  --full)        echo "Next: aws ecs update-service --force-new-deployment; then scripts/cutover-dns.sh." ;;
esac
