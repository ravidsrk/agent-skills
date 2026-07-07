#!/usr/bin/env bash
# Phase 3: map Fly secrets → 8 grouped AWS Secrets Manager entries.
# Dry-run by default; add --apply to actually write.
#
# Usage:
#   ./secrets-migrate.sh <fly-app>              # dry-run (no writes)
#   ./secrets-migrate.sh <fly-app> --apply      # write grouped secrets
#
# Env (required):
#   PROJECT   AWS Secrets Manager path prefix, e.g. "myproject"
#   ENV       "prod", "staging", etc.
#
# Env (optional):
#   AWS_REGION   defaults to $AWS_DEFAULT_REGION or ap-southeast-1
#
# Groupings (each Secrets Manager entry costs $0.40/mo — grouping saves ~$16/mo):
#
#   db            DATABASE_URL, DATABASE_URL_LIBPQ, REDIS_URL
#   llm           OPENAI_*, ANTHROPIC_*, GOOGLE_AI_*, GEMINI_*, MISTRAL_*, COHERE_*
#   email         RESEND_*, SENDGRID_*, POSTMARK_*, MAILGUN_*, SMTP_*
#   social        TWITTER_*, DISCORD_*, SLACK_*, TELEGRAM_*
#   payments      STRIPE_*, PAYPAL_*, LEMONSQUEEZY_*
#   data          Anything matching *_API_KEY / *_TOKEN not caught above
#   auth          JWT_*, OAUTH_*, CLERK_*, AUTH_*, SESSION_*, COOKIE_*
#   telemetry     SENTRY_*, POSTHOG_*, DATADOG_*, HONEYCOMB_*
#
# Secrets whose VALUES are not exposed by `flyctl secrets list` — this script
# needs the VALUES too. Two options:
#   1. Pull from a local .env that mirrors production (default; see FLY_ENV_FILE)
#   2. `flyctl ssh console -a <fly-app> -C env` and paste into a temp file.
#
# Never let this script log values to stdout in --apply mode. Names only.

set -euo pipefail

FLY_APP=""
APPLY="no"

while [ $# -gt 0 ]; do
  case "$1" in
    --apply)         APPLY="yes"; shift ;;
    --dry-run)       APPLY="no"; shift ;;
    -h|--help)
      sed -n '2,40p' "$0" | sed 's/^# //; s/^#//'
      exit 0 ;;
    -*)              echo "unknown flag: $1" >&2; exit 1 ;;
    *)               FLY_APP="$1"; shift ;;
  esac
done

[ -n "$FLY_APP" ]        || { echo "🔴 fly-app arg required" >&2; exit 2; }
: "${PROJECT:?PROJECT env var required}"
: "${ENV:?ENV env var required}"
AWS_REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-ap-southeast-1}}"
FLY_ENV_FILE="${FLY_ENV_FILE:-.migration/fly-env.txt}"

if [ ! -f "$FLY_ENV_FILE" ]; then
  cat >&2 <<EOF
🔴 Missing $FLY_ENV_FILE (KEY=VALUE lines, one per secret).

   To capture from Fly (requires SSH to a running machine):
     flyctl ssh console -a $FLY_APP -C env > $FLY_ENV_FILE
     # then hand-edit to drop FLY_* / system vars.

   Or use your local .env if it mirrors production.
EOF
  exit 3
fi

# Also list Fly's known secret NAMES so we can warn about anything not represented
# in the env file (rotation-friendly).
FLY_NAMES=$(flyctl secrets list -a "$FLY_APP" 2>/dev/null | awk 'NR>1 {print $1}' | grep -E '^[A-Z0-9_]+$' || true)

# Classify each KEY=VALUE line into a group.
declare -A GROUP_DB GROUP_LLM GROUP_EMAIL GROUP_SOCIAL GROUP_PAYMENTS GROUP_DATA GROUP_AUTH GROUP_TELEMETRY

classify() {
  local key="$1"
  case "$key" in
    DATABASE_URL|DATABASE_URL_LIBPQ|REDIS_URL|DATABASE_*|REDIS_*)                    echo db ;;
    OPENAI_*|ANTHROPIC_*|GOOGLE_AI_*|GEMINI_*|MISTRAL_*|COHERE_*|GROQ_*|VOYAGE_*)    echo llm ;;
    RESEND_*|SENDGRID_*|POSTMARK_*|MAILGUN_*|SMTP_*|EMAIL_*|MAIL_*)                  echo email ;;
    TWITTER_*|DISCORD_*|SLACK_*|TELEGRAM_*|WHATSAPP_*|X_API_*)                       echo social ;;
    STRIPE_*|PAYPAL_*|LEMONSQUEEZY_*|POLAR_*)                                        echo payments ;;
    JWT_*|OAUTH_*|CLERK_*|AUTH_*|SESSION_*|COOKIE_*|BETTER_AUTH_*|NEXTAUTH_*)        echo auth ;;
    SENTRY_*|POSTHOG_*|DATADOG_*|HONEYCOMB_*|BUGSNAG_*|AXIOM_*)                      echo telemetry ;;
    *_API_KEY|*_TOKEN|*_SECRET)                                                      echo data ;;
    *)                                                                               echo data ;;
  esac
}

while IFS='=' read -r key value; do
  # Strip whitespace and skip comments / blank lines.
  key="${key%% *}"
  [ -z "$key" ] && continue
  case "$key" in \#*) continue;; esac
  case "$key" in FLY_*) continue;; esac      # Fly system vars — skip
  case "$key" in PORT|HOME|PATH|HOSTNAME|LANG|LC_*|PWD|USER|SHELL|TERM|OLDPWD|SHLVL|_) continue;; esac

  group=$(classify "$key")
  # Use nameref to append into the right group associative array.
  case "$group" in
    db)         GROUP_DB[$key]="$value" ;;
    llm)        GROUP_LLM[$key]="$value" ;;
    email)      GROUP_EMAIL[$key]="$value" ;;
    social)     GROUP_SOCIAL[$key]="$value" ;;
    payments)   GROUP_PAYMENTS[$key]="$value" ;;
    auth)       GROUP_AUTH[$key]="$value" ;;
    telemetry)  GROUP_TELEMETRY[$key]="$value" ;;
    data|*)     GROUP_DATA[$key]="$value" ;;
  esac
done < "$FLY_ENV_FILE"

# Warn about names in Fly that we didn't see values for.
if [ -n "$FLY_NAMES" ]; then
  echo "=== Sanity check: names known to Fly vs env file ==="
  MISSING=""
  for name in $FLY_NAMES; do
    if ! grep -qE "^${name}=" "$FLY_ENV_FILE"; then
      MISSING="$MISSING $name"
    fi
  done
  if [ -n "$MISSING" ]; then
    echo "🟡 In Fly but NOT in $FLY_ENV_FILE:$MISSING"
    echo "   Add them (or accept that they won't migrate)."
  else
    echo "🟢 All Fly secret names have values in $FLY_ENV_FILE"
  fi
fi

emit_group() {
  local name="$1"; shift
  local kv=""
  local sep=""
  for kv_pair in "$@"; do
    sep="${kv:+,}"
    kv="$kv$sep$kv_pair"
  done
  local secret_id="$PROJECT/$ENV/$name"
  echo ""
  echo "── $secret_id ──"
  if [ -z "$kv" ]; then
    echo "  (empty — skipping)"
    return
  fi
  echo "  keys:$(echo "$kv" | jq -r 'keys | .[]' 2>/dev/null | tr '\n' ' ' || echo " (jq parse fail)")"

  if [ "$APPLY" != "yes" ]; then
    echo "  🟡 dry-run — would put $(echo "$kv" | jq 'keys | length') key(s)"
    return
  fi

  if aws --region "$AWS_REGION" secretsmanager describe-secret --secret-id "$secret_id" >/dev/null 2>&1; then
    aws --region "$AWS_REGION" secretsmanager put-secret-value \
      --secret-id "$secret_id" --secret-string "$kv" >/dev/null
    echo "  🟢 updated"
  else
    aws --region "$AWS_REGION" secretsmanager create-secret \
      --name "$secret_id" --secret-string "$kv" >/dev/null
    echo "  🟢 created"
  fi
}

# Serialize each group's associative array to JSON (via jq -R).
serialize() {
  local -n arr=$1
  # shellcheck disable=SC2016
  local out='{}'
  for k in "${!arr[@]}"; do
    out=$(echo "$out" | jq --arg k "$k" --arg v "${arr[$k]}" '. + {($k): $v}')
  done
  echo "$out"
}

if [ "$APPLY" = "yes" ]; then
  echo ""
  echo "🔴 --apply mode: writing 8 grouped secrets to AWS Secrets Manager in $AWS_REGION"
else
  echo ""
  echo "🟡 dry-run mode — no writes will happen. Re-run with --apply."
fi

emit_group db        "$(serialize GROUP_DB)"
emit_group llm       "$(serialize GROUP_LLM)"
emit_group email     "$(serialize GROUP_EMAIL)"
emit_group social    "$(serialize GROUP_SOCIAL)"
emit_group payments  "$(serialize GROUP_PAYMENTS)"
emit_group data      "$(serialize GROUP_DATA)"
emit_group auth      "$(serialize GROUP_AUTH)"
emit_group telemetry "$(serialize GROUP_TELEMETRY)"

echo ""
echo "=== Done ==="
if [ "$APPLY" != "yes" ]; then
  echo "Nothing was written. Re-run with --apply after reviewing the groups above."
fi
