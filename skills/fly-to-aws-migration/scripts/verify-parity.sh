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
# endpoints-file: newline-separated list of paths to test (default: just /health)

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

  # Get both responses
  AWS_BODY=$(curl -sS "$AWS_URL$ENDPOINT" || echo "ERROR")
  FLY_BODY=$(curl -sS "$FLY_URL$ENDPOINT" || echo "ERROR")

  AWS_STATUS=$(curl -sS -o /dev/null -w "%{http_code}" "$AWS_URL$ENDPOINT" || echo "FAIL")
  FLY_STATUS=$(curl -sS -o /dev/null -w "%{http_code}" "$FLY_URL$ENDPOINT" || echo "FAIL")

  AWS_TIME=$(curl -sS -o /dev/null -w "%{time_starttransfer}" "$AWS_URL$ENDPOINT" || echo "0")
  FLY_TIME=$(curl -sS -o /dev/null -w "%{time_starttransfer}" "$FLY_URL$ENDPOINT" || echo "0")

  echo "  AWS: $AWS_STATUS in ${AWS_TIME}s" | tee -a "$REPORT"
  echo "  Fly: $FLY_STATUS in ${FLY_TIME}s" | tee -a "$REPORT"

  if [ "$AWS_STATUS" != "$FLY_STATUS" ]; then
    echo "  🔴 STATUS MISMATCH" | tee -a "$REPORT"
    FAILURES=$((FAILURES + 1))
    DRIFT_LINES+=("$ENDPOINT: AWS $AWS_STATUS vs Fly $FLY_STATUS")
    continue
  fi

  # For JSON responses, compare structure (sorted keys)
  if echo "$AWS_BODY" | jq -e . > /dev/null 2>&1 && echo "$FLY_BODY" | jq -e . > /dev/null 2>&1; then
    AWS_KEYS=$(echo "$AWS_BODY" | jq -S 'paths(scalars) | join(".")' | sort -u)
    FLY_KEYS=$(echo "$FLY_BODY" | jq -S 'paths(scalars) | join(".")' | sort -u)

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
    # Non-JSON, compare byte lengths
    AWS_LEN=$(echo -n "$AWS_BODY" | wc -c)
    FLY_LEN=$(echo -n "$FLY_BODY" | wc -c)
    DIFF=$((AWS_LEN - FLY_LEN))
    DIFF_PCT=$(python3 -c "print(abs($DIFF) / max($FLY_LEN, 1) * 100)" 2>/dev/null || echo "0")

    if (( $(echo "$DIFF_PCT < 5" | bc -l 2>/dev/null || echo "0") )); then
      echo "  🟢 Body size within 5% ($AWS_LEN vs $FLY_LEN)" | tee -a "$REPORT"
      PASSES=$((PASSES + 1))
    else
      echo "  🟡 Body size differs by ${DIFF_PCT}% ($AWS_LEN vs $FLY_LEN)" | tee -a "$REPORT"
      DRIFT_LINES+=("$ENDPOINT: body size $AWS_LEN vs $FLY_LEN")
      FAILURES=$((FAILURES + 1))
    fi
  fi

  # Latency check
  AWS_FASTER=$(python3 -c "print(1 if $AWS_TIME < $FLY_TIME else 0)" 2>/dev/null || echo "0")
  if [ "$AWS_FASTER" = "1" ]; then
    SPEEDUP=$(python3 -c "print(round($FLY_TIME / $AWS_TIME, 1))" 2>/dev/null || echo "?")
    echo "  🚀 AWS ${SPEEDUP}x faster" | tee -a "$REPORT"
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
