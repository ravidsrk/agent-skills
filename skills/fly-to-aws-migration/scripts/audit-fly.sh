#!/usr/bin/env bash
# Phase 0: Audit Fly setup. Outputs to .migration/00-audit.md
#
# Usage: ./audit-fly.sh <output-dir>
# Example: ./audit-fly.sh myproject/.migration/

set -euo pipefail

OUTPUT_DIR="${1:-.the skill/migration}"
mkdir -p "$OUTPUT_DIR"

OUT="$OUTPUT_DIR/00-audit.md"

cat > "$OUT" <<EOF
# Phase 0: Fly Inventory

Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)

EOF

echo "=== Listing Fly apps ==="
echo "## Fly apps" >> "$OUT"
echo '```' >> "$OUT"
flyctl apps list 2>&1 | tee -a "$OUT"
echo '```' >> "$OUT"
echo "" >> "$OUT"

# For each app, capture details
APPS=$(flyctl apps list -j 2>&1 | jq -r '.[].Name')

for APP in $APPS; do
  echo "" >> "$OUT"
  echo "## App: $APP" >> "$OUT"

  echo "### Machines" >> "$OUT"
  echo '```' >> "$OUT"
  flyctl machines list -a "$APP" 2>&1 | tee -a "$OUT" || echo "(error)"
  echo '```' >> "$OUT"

  echo "### Scale" >> "$OUT"
  echo '```' >> "$OUT"
  flyctl scale show -a "$APP" 2>&1 | tee -a "$OUT" || echo "(error)"
  echo '```' >> "$OUT"

  echo "### Secrets (names only — values are not exposed)" >> "$OUT"
  echo '```' >> "$OUT"
  flyctl secrets list -a "$APP" 2>&1 | tee -a "$OUT" || echo "(error)"
  echo '```' >> "$OUT"

  echo "### IPs" >> "$OUT"
  echo '```' >> "$OUT"
  flyctl ips list -a "$APP" 2>&1 | tee -a "$OUT" || echo "(error)"
  echo '```' >> "$OUT"

  echo "### Volumes" >> "$OUT"
  echo '```' >> "$OUT"
  flyctl volumes list -a "$APP" 2>&1 | tee -a "$OUT" || echo "(error)"
  echo '```' >> "$OUT"

  echo "" >> "$OUT"
done

# Database inventory
echo "" >> "$OUT"
echo "## Postgres databases" >> "$OUT"

PG_APPS=$(flyctl postgres list 2>&1 | grep -oE '^[a-z0-9-]+' | head -20 || echo "")

for PG in $PG_APPS; do
  echo "" >> "$OUT"
  echo "### $PG" >> "$OUT"

  echo "#### Database size + table count" >> "$OUT"
  echo '```sql' >> "$OUT"
  flyctl postgres connect -a "$PG" -- -c "
    SELECT
      pg_size_pretty(pg_database_size(current_database())) AS db_size,
      (SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='public') AS table_count;
  " 2>&1 | tee -a "$OUT" || echo "(error connecting)"
  echo '```' >> "$OUT"

  echo "#### Top 10 tables by row count" >> "$OUT"
  echo '```sql' >> "$OUT"
  flyctl postgres connect -a "$PG" -- -c "
    SELECT schemaname, tablename, n_live_tup
    FROM pg_stat_user_tables
    ORDER BY n_live_tup DESC
    LIMIT 10;
  " 2>&1 | tee -a "$OUT" || echo "(error)"
  echo '```' >> "$OUT"

  # Save full row counts for later parity check
  flyctl postgres connect -a "$PG" -- -c "
    SELECT schemaname, tablename, n_live_tup
    FROM pg_stat_user_tables
    ORDER BY tablename;
  " > "$OUTPUT_DIR/fly-rowcounts-$PG.txt" 2>&1 || echo "(error)"
done

# DNS records from Cloudflare (if zone info available)
if [ -n "${CLOUDFLARE_ZONE_ID:-}" ] && [ -n "${CLOUDFLARE_EMAIL:-}" ] && [ -n "${CLOUDFLARE_GLOBAL_API_KEY:-}" ]; then
  echo "" >> "$OUT"
  echo "## Cloudflare DNS records" >> "$OUT"
  echo '```' >> "$OUT"
  curl -sS -H "X-Auth-Email: $CLOUDFLARE_EMAIL" -H "X-Auth-Key: $CLOUDFLARE_GLOBAL_API_KEY" \
    "https://api.cloudflare.com/client/v4/zones/$CLOUDFLARE_ZONE_ID/dns_records?per_page=100" \
    | jq -r '.result[] | "\(.type) | \(.name) → \(.content) | proxied=\(.proxied)"' \
    | tee -a "$OUT"
  echo '```' >> "$OUT"
fi

echo "" >> "$OUT"
echo "## Next steps" >> "$OUT"
echo "- Estimate AWS sizing based on Fly machine sizes" >> "$OUT"
echo "- Plan secret groupings (8-10 groups by category)" >> "$OUT"
echo "- Pick maintenance window for API cutover" >> "$OUT"
echo "- Read references/phases.md → Phase 1" >> "$OUT"

echo ""
echo "=== Audit complete ==="
echo "Output: $OUT"
echo "Row counts saved: $OUTPUT_DIR/fly-rowcounts-*.txt"
