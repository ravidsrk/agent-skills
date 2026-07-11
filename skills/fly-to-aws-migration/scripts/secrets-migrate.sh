#!/usr/bin/env bash
# secrets-migrate.sh — map Fly app secrets → grouped AWS Secrets Manager entries.
#
# Usage:
#   ./secrets-migrate.sh <fly-app> <aws-secret-prefix> [--dry-run]
# Example:
#   ./secrets-migrate.sh my-api myapp/prod
#   ./secrets-migrate.sh my-api myapp/prod --dry-run
#
# Groups secrets by category (db, llm, social, email, app, other) to reduce
# Secrets Manager cost (per-secret monthly fee) and simplify ECS task roles.
#
# Requires: flyctl, aws CLI, jq
# Env: AWS_PROFILE / AWS credentials, FLY_API_TOKEN if needed by flyctl
set -euo pipefail

FLY_APP="${1:?usage: secrets-migrate.sh <fly-app> <aws-secret-prefix> [--dry-run]}"
PREFIX="${2:?usage: secrets-migrate.sh <fly-app> <aws-secret-prefix> [--dry-run]}"
DRY_RUN=0
[[ "${3:-}" == "--dry-run" ]] && DRY_RUN=1

command -v flyctl >/dev/null || { echo "ERROR: flyctl not on PATH" >&2; exit 1; }
command -v aws >/dev/null || { echo "ERROR: aws CLI not on PATH" >&2; exit 1; }
command -v jq >/dev/null || { echo "ERROR: jq not on PATH" >&2; exit 1; }

echo "=== Export Fly secrets for app: $FLY_APP ==="
# fly secrets list shows names only; values need secrets deploy export or stage
# Prefer JSON stage if available; fall back to list + warn for values.
RAW_JSON=""
if RAW_JSON=$(flyctl secrets list -a "$FLY_APP" --json 2>/dev/null); then
  :
else
  echo "ERROR: could not list Fly secrets for $FLY_APP" >&2
  exit 1
fi

# Build name→placeholder map from list. Values: try `flyctl ssh console` is too invasive.
# Documented approach: user supplies a dump, or we create secret *shells* with names
# and instruct to fill from a local export.
NAMES=$(echo "$RAW_JSON" | jq -r 'if type=="array" then .[].Name // .[].name else empty end' 2>/dev/null || true)
if [ -z "$NAMES" ]; then
  # alternate shapes
  NAMES=$(echo "$RAW_JSON" | jq -r 'keys[]?' 2>/dev/null || true)
fi

if [ -z "$NAMES" ]; then
  echo "No secret names found. Raw:"
  echo "$RAW_JSON" | head -c 500
  echo
  echo "Tip: run 'flyctl secrets list -a $FLY_APP' and pass values via a local env file:"
  echo "  FLY_SECRETS_FILE=/path/to/export.env $0 $FLY_APP $PREFIX"
  exit 1
fi

# Optional: load values from FLY_SECRETS_FILE (KEY=VALUE lines, never commit)
declare -A VALS=()
if [ -n "${FLY_SECRETS_FILE:-}" ] && [ -f "$FLY_SECRETS_FILE" ]; then
  while IFS= read -r line || [ -n "$line" ]; do
    [[ -z "$line" || "$line" =~ ^# ]] && continue
    key="${line%%=*}"
    val="${line#*=}"
    VALS["$key"]="$val"
  done <"$FLY_SECRETS_FILE"
  echo "Loaded values from FLY_SECRETS_FILE (${#VALS[@]} keys)"
else
  echo "🟡 FLY_SECRETS_FILE not set — will create AWS secrets with PLACEHOLDER values."
  echo "   Export Fly secrets offline (never log them), then re-run with FLY_SECRETS_FILE=..."
fi

categorize() {
  local k
  k=$(echo "$1" | tr '[:lower:]' '[:upper:]')
  case "$k" in
    *DATABASE*|*POSTGRES*|*MYSQL*|*REDIS*|*MONGO*|*DB_*|*_DB|DATABASE_URL|DIRECT_URL) echo db ;;
    *OPENAI*|*ANTHROPIC*|*GEMINI*|*LLM*|*AI_*|*GROQ*|*MISTRAL*) echo llm ;;
    *TWITTER*|*X_*|*LINKEDIN*|*DISCORD*|*SLACK*|*SOCIAL*|*TELEGRAM*) echo social ;;
    *SMTP*|*SENDGRID*|*RESEND*|*MAIL*|*EMAIL*|*POSTMARK*) echo email ;;
    *SECRET*|*JWT*|*SESSION*|*COOKIE*|*AUTH*|*API_KEY*|*TOKEN*|NODE_ENV|PORT|HOST|APP_*) echo app ;;
    *) echo other ;;
  esac
}

declare -A GROUPS=()
while IFS= read -r name; do
  [ -z "$name" ] && continue
  catg=$(categorize "$name")
  val="${VALS[$name]:-PLACEHOLDER_SET_ME}"
  # accumulate as JSON fragments per group
  if [ -z "${GROUPS[$catg]:-}" ]; then
    GROUPS[$catg]="\"$name\": $(jq -Rn --arg v "$val" '$v')"
  else
    GROUPS[$catg]="${GROUPS[$catg]}, \"$name\": $(jq -Rn --arg v "$val" '$v')"
  fi
done <<<"$NAMES"

echo ""
echo "=== Groups ==="
for catg in db llm social email app other; do
  [ -z "${GROUPS[$catg]:-}" ] && continue
  SECRET_ID="${PREFIX}/${catg}"
  BODY="{ ${GROUPS[$catg]} }"
  COUNT=$(echo "$BODY" | jq 'length')
  echo "  $SECRET_ID  ($COUNT keys)"
  if [ "$DRY_RUN" -eq 1 ]; then
    echo "$BODY" | jq 'keys'
    continue
  fi
  if aws secretsmanager describe-secret --secret-id "$SECRET_ID" >/dev/null 2>&1; then
    aws secretsmanager put-secret-value \
      --secret-id "$SECRET_ID" \
      --secret-string "$BODY" >/dev/null
    echo "    updated"
  else
    aws secretsmanager create-secret \
      --name "$SECRET_ID" \
      --secret-string "$BODY" \
      --description "Migrated from Fly app $FLY_APP ($catg)" >/dev/null
    echo "    created"
  fi
done

echo ""
echo "Done. Wire ECS task definitions to these secret ARNs (task role needs secretsmanager:GetSecretValue)."
echo "If placeholders remain, re-run with FLY_SECRETS_FILE pointing at a local KEY=VALUE export."
