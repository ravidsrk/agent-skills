#!/usr/bin/env bash
# Phase 0: Audit Fly setup. Outputs to <output-dir>/00-audit.md
#
# Usage: ./audit-fly.sh [output-dir]
# Example: ./audit-fly.sh myproject/.migration/
#
# Optional env (for the DNS-inventory section):
#   CLOUDFLARE_API_TOKEN  scoped token (Zone:DNS:Read); global key also accepted
#   CLOUDFLARE_ZONE_ID    zone whose records you want dumped

set -euo pipefail

OUTPUT_DIR="${1:-.migration}"
mkdir -p "$OUTPUT_DIR"

OUT="$OUTPUT_DIR/00-audit.md"

cat > "$OUT" <<EOF
# Phase 0: Fly Inventory

Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)

EOF

echo "=== Listing Fly apps ==="
{
  echo "## Fly apps"
  echo '```'
  flyctl apps list || echo "(error listing apps)"
  echo '```'
  echo ""
} >> "$OUT"

# For each app, capture details.
# Don't merge stderr into stdout here — jq must see clean JSON only.
if ! APPS_JSON=$(flyctl apps list -j); then
  echo "🔴 flyctl apps list -j failed. Auth or network?" >&2
  APPS=""
else
  APPS=$(echo "$APPS_JSON" | jq -r '.[].Name')
fi

for APP in $APPS; do
  {
    echo ""
    echo "## App: $APP"

    echo "### Machines"
    echo '```'
    flyctl machines list -a "$APP" 2>&1 || echo "(error)"
    echo '```'

    echo "### Scale"
    echo '```'
    flyctl scale show -a "$APP" 2>&1 || echo "(error)"
    echo '```'

    echo "### Secrets (names only — values are not exposed)"
    echo '```'
    flyctl secrets list -a "$APP" 2>&1 || echo "(error)"
    echo '```'

    echo "### IPs"
    echo '```'
    flyctl ips list -a "$APP" 2>&1 || echo "(error)"
    echo '```'

    echo "### Volumes"
    echo '```'
    flyctl volumes list -a "$APP" 2>&1 || echo "(error)"
    echo '```'

    echo ""
  } >> "$OUT"
done

# Database inventory.
# flyctl postgres list emits a table on stdout; we grep app names conservatively.
if PG_APPS_RAW=$(flyctl postgres list); then
  PG_APPS=$(echo "$PG_APPS_RAW" | awk 'NR>1 && $1 ~ /^[a-z0-9-]+$/ {print $1}' | head -20)
else
  PG_APPS=""
fi

{
  echo ""
  echo "## Postgres databases"
} >> "$OUT"

for PG in $PG_APPS; do
  {
    echo ""
    echo "### $PG"

    echo "#### Database size + table count"
    echo '```sql'
    flyctl postgres connect -a "$PG" -- -c "
      SELECT
        pg_size_pretty(pg_database_size(current_database())) AS db_size,
        (SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='public') AS table_count;
    " 2>&1 || echo "(error connecting)"
    echo '```'

    echo "#### Top 10 tables by row count (statistic, not real COUNT(*))"
    echo '```sql'
    flyctl postgres connect -a "$PG" -- -c "
      SELECT schemaname, tablename, n_live_tup
      FROM pg_stat_user_tables
      ORDER BY n_live_tup DESC
      LIMIT 10;
    " 2>&1 || echo "(error)"
    echo '```'
  } >> "$OUT"

  # Save full stat snapshot for later comparison sizing (NOT parity — see db-migrate.sh).
  flyctl postgres connect -a "$PG" -- -c "
    SELECT schemaname, tablename, n_live_tup
    FROM pg_stat_user_tables
    ORDER BY tablename;
  " > "$OUTPUT_DIR/fly-rowcounts-$PG.txt" 2>&1 || echo "(error)" > "$OUTPUT_DIR/fly-rowcounts-$PG.txt"
done

# DNS records from Cloudflare (if creds available).
# Prefer scoped API token; fall back to legacy global key if it's the only thing set.
if [ -n "${CLOUDFLARE_ZONE_ID:-}" ]; then
  AUTH_HEADER=()
  if [ -n "${CLOUDFLARE_API_TOKEN:-}" ]; then
    AUTH_HEADER=("-H" "Authorization: Bearer $CLOUDFLARE_API_TOKEN")
  elif [ -n "${CLOUDFLARE_EMAIL:-}" ] && [ -n "${CLOUDFLARE_GLOBAL_API_KEY:-}" ]; then
    AUTH_HEADER=("-H" "X-Auth-Email: $CLOUDFLARE_EMAIL" "-H" "X-Auth-Key: $CLOUDFLARE_GLOBAL_API_KEY")
    echo "🟡 Using legacy Cloudflare global API key. Prefer CLOUDFLARE_API_TOKEN (scoped)." >&2
  fi

  if [ ${#AUTH_HEADER[@]} -gt 0 ]; then
    {
      echo ""
      echo "## Cloudflare DNS records"
      echo '```'
      # -f makes curl exit non-zero on 4xx/5xx; keep stderr on the terminal.
      if RESP=$(curl -sSf "${AUTH_HEADER[@]}" \
        "https://api.cloudflare.com/client/v4/zones/$CLOUDFLARE_ZONE_ID/dns_records?per_page=100"); then
        echo "$RESP" | jq -r '.result[] | "\(.type) | \(.name) → \(.content) | proxied=\(.proxied)"'
      else
        echo "(curl to Cloudflare failed — check token/zone id)"
      fi
      echo '```'
    } >> "$OUT"
  fi
fi

{
  echo ""
  echo "## Next steps"
  echo "- Estimate AWS sizing based on Fly machine sizes"
  echo "- Plan secret groupings (8-10 groups by category)"
  echo "- Pick maintenance window for API cutover"
  echo "- Read references/phases.md → Phase 1"
} >> "$OUT"

echo ""
echo "=== Audit complete ==="
echo "Output: $OUT"
echo "Row counts saved: $OUTPUT_DIR/fly-rowcounts-*.txt"
