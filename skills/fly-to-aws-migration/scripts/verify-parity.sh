#!/usr/bin/env bash
# Phase 4+5 post-cutover: verify Fly and AWS production responses match.
# Run for ≥24h before destroying Fly resources.
#
# Usage:
#   ./verify-parity.sh <new-aws-url> <old-fly-url> [endpoints-file]
# Example:
#   ./verify-parity.sh https://api.example.com https://your-app.fly.dev \
#     ./parity-endpoints.txt
#
# endpoints-file: newline-separated list of paths to test (default: just /health).

set -euo pipefail

AWS_URL="${1:?AWS URL required}"
FLY_URL="${2:?Fly URL required (for comparison)}"
ENDPOINTS_FILE="${3:-}"

if [ -z "$ENDPOINTS_FILE" ]; then
  ENDPOINTS_FILE="/tmp/default-parity-endpoints.txt"
  cat > "$ENDPOINTS_FILE" <<EOF
/health
/health/full
EOF
fi

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
REPORT="/tmp/parity-report-$TIMESTAMP.txt"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# fetch <origin> <endpoint> <out-body-file> <out-meta-file>
# Emits status + time_starttransfer to the meta file. Body to the body file.
# Single HTTP request — no double-fetch races.
fetch() {
  local origin="$1" endpoint="$2" body="$3" meta="$4"
  # -sS: silent + show errors. No -f so we still capture the body of a 4xx/5xx.
  # -w gives us http_code and TTFB from the SAME request that filled body.
  curl -sS -o "$body" -w "%{http_code} %{time_starttransfer}\n" \
    --max-time 15 "$origin$endpoint" > "$meta" || echo "000 0" > "$meta"
}

echo "=== Parity check ===" | tee "$REPORT"
echo "AWS: $AWS_URL" | tee -a "$REPORT"
echo "Fly: $FLY_URL" | tee -a "$REPORT"
echo "Started: $(date -u +%Y-%m-%dT%H:%M:%SZ)" | tee -a "$REPORT"
echo "" | tee -a "$REPORT"

PASSES=0
FAILURES=0
DRIFT_LINES=()

while read -r ENDPOINT; do
  [ -z "$ENDPOINT" ] && continue
  [ "${ENDPOINT:0:1}" = "#" ] && continue

  echo "--- $ENDPOINT ---" | tee -a "$REPORT"

  AWS_BODY="$WORK/aws.body"
  AWS_META="$WORK/aws.meta"
  FLY_BODY="$WORK/fly.body"
  FLY_META="$WORK/fly.meta"

  fetch "$AWS_URL" "$ENDPOINT" "$AWS_BODY" "$AWS_META"
  fetch "$FLY_URL" "$ENDPOINT" "$FLY_BODY" "$FLY_META"

  AWS_STATUS=$(awk '{print $1}' "$AWS_META")
  AWS_TIME=$(awk '{print $2}' "$AWS_META")
  FLY_STATUS=$(awk '{print $1}' "$FLY_META")
  FLY_TIME=$(awk '{print $2}' "$FLY_META")

  echo "  AWS: $AWS_STATUS in ${AWS_TIME}s" | tee -a "$REPORT"
  echo "  Fly: $FLY_STATUS in ${FLY_TIME}s" | tee -a "$REPORT"

  if [ "$AWS_STATUS" != "$FLY_STATUS" ]; then
    echo "  🔴 STATUS MISMATCH" | tee -a "$REPORT"
    FAILURES=$((FAILURES + 1))
    DRIFT_LINES+=("$ENDPOINT: AWS $AWS_STATUS vs Fly $FLY_STATUS")
    continue
  fi

  # For JSON responses, compare structure (sorted paths). For non-JSON, byte
  # length within 5%.
  if jq -e . "$AWS_BODY" > /dev/null 2>&1 && jq -e . "$FLY_BODY" > /dev/null 2>&1; then
    AWS_KEYS=$(jq -S 'paths(scalars) | join(".")' "$AWS_BODY" | sort -u)
    FLY_KEYS=$(jq -S 'paths(scalars) | join(".")' "$FLY_BODY" | sort -u)
    if [ "$AWS_KEYS" = "$FLY_KEYS" ]; then
      echo "  🟢 JSON structure matches" | tee -a "$REPORT"
      PASSES=$((PASSES + 1))
    else
      echo "  🟡 JSON structure differs:" | tee -a "$REPORT"
      diff <(echo "$AWS_KEYS") <(echo "$FLY_KEYS") | head -10 | tee -a "$REPORT"
      DRIFT_LINES+=("$ENDPOINT: JSON shape diff")
      FAILURES=$((FAILURES + 1))
    fi
  else
    AWS_LEN=$(wc -c < "$AWS_BODY")
    FLY_LEN=$(wc -c < "$FLY_BODY")
    DIFF=$((AWS_LEN - FLY_LEN))
    DIFF_PCT=$(python3 -c "print(abs($DIFF) / max($FLY_LEN, 1) * 100)" 2>/dev/null || echo "999")

    # Prefer python3 over bc (bc is not always installed).
    if [ "$(python3 -c "print(1 if float('$DIFF_PCT') < 5 else 0)" 2>/dev/null || echo 0)" = "1" ]; then
      echo "  🟢 Body size within 5% ($AWS_LEN vs $FLY_LEN)" | tee -a "$REPORT"
      PASSES=$((PASSES + 1))
    else
      echo "  🟡 Body size differs by ${DIFF_PCT}% ($AWS_LEN vs $FLY_LEN)" | tee -a "$REPORT"
      DRIFT_LINES+=("$ENDPOINT: body size $AWS_LEN vs $FLY_LEN")
      FAILURES=$((FAILURES + 1))
    fi
  fi

  # Latency note (single-request, so timings are apples-to-apples).
  if [ "$(python3 -c "print(1 if float('$AWS_TIME') < float('$FLY_TIME') else 0)" 2>/dev/null || echo 0)" = "1" ]; then
    SPEEDUP=$(python3 -c "print(round(float('$FLY_TIME') / float('$AWS_TIME'), 1))" 2>/dev/null || echo "?")
    echo "  🚀 AWS ${SPEEDUP}x faster on this hit" | tee -a "$REPORT"
  fi

  echo "" | tee -a "$REPORT"
done < "$ENDPOINTS_FILE"

echo "" | tee -a "$REPORT"
echo "=== Summary ===" | tee -a "$REPORT"
echo "Pass: $PASSES" | tee -a "$REPORT"
echo "Fail: $FAILURES" | tee -a "$REPORT"

if [ ${#DRIFT_LINES[@]} -gt 0 ]; then
  echo "" | tee -a "$REPORT"
  echo "Drift details:" | tee -a "$REPORT"
  for LINE in "${DRIFT_LINES[@]}"; do
    echo "  - $LINE" | tee -a "$REPORT"
  done
fi

echo ""
echo "Full report: $REPORT"

if [ "$FAILURES" -gt 0 ]; then
  exit 1
fi

echo "🟢 All endpoints match. Safe to destroy Fly after T+24h+."
