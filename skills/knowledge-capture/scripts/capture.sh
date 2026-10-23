#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: capture.sh [text] [options]

Save content into a markdown knowledge base.

Options:
  --file PATH      Read content from a file
  --stdin          Read content from stdin
  --type TYPE      Page type (default: note)
  --slug SLUG      Explicit slug, e.g. meetings/2026-05-21-pricing-review
  --title TITLE    Page title (default: first non-empty line)
  --source URL     Source URL or reference
  --root DIR       Knowledge base root (default: $KB_ROOT or ./brain)
  --json           Print a JSON receipt
  --quiet          Print only the slug
  -h, --help       Show this help

Environment:
  KB_ROOT          Default knowledge base root

Examples:
  capture.sh "a thought"
  capture.sh --file notes.md --type note
  cat transcript.txt | capture.sh --stdin --type meeting --title "Pricing review"
  capture.sh --file article.md --slug originals/2026-05-21-postgres-vs-sqlite
EOF
}

die() { echo "error: $*" >&2; exit 2; }

root="${KB_ROOT:-./brain}"
type="note"
type_set=0
slug=""
title=""
source=""
json=0
quiet=0
file=""
use_stdin=0
text=""
sources=0

while [ $# -gt 0 ]; do
  case "$1" in
    --file) [ $# -ge 2 ] || die "missing value for --file"; file="$2"; sources=$((sources+1)); shift 2 ;;
    --stdin) use_stdin=1; sources=$((sources+1)); shift ;;
    --type) [ $# -ge 2 ] || die "missing value for --type"; type="$2"; type_set=1; shift 2 ;;
    --slug) [ $# -ge 2 ] || die "missing value for --slug"; slug="$2"; shift 2 ;;
    --title) [ $# -ge 2 ] || die "missing value for --title"; title="$2"; shift 2 ;;
    --source) [ $# -ge 2 ] || die "missing value for --source"; source="$2"; shift 2 ;;
    --root) [ $# -ge 2 ] || die "missing value for --root"; root="$2"; shift 2 ;;
    --json) json=1; shift ;;
    --quiet) quiet=1; shift ;;
    -h|--help) usage; exit 0 ;;
    -*) die "unknown option: $1" ;;
    *) [ -z "$text" ] || die "only one inline text argument is supported"; text="$1"; sources=$((sources+1)); shift ;;
  esac
done

[ "$sources" -eq 1 ] || die "provide exactly one of: inline text, --file, or --stdin"

command -v awk >/dev/null 2>&1 || die "awk is required"
command -v sed >/dev/null 2>&1 || die "sed is required"

hash_cmd=""
if command -v shasum >/dev/null 2>&1; then
  hash_cmd="shasum -a 256"
elif command -v sha256sum >/dev/null 2>&1; then
  hash_cmd="sha256sum"
else
  die "shasum or sha256sum is required"
fi

tmp=$(mktemp "${TMPDIR:-/tmp}/kb-capture.XXXXXX")
body=$(mktemp "${TMPDIR:-/tmp}/kb-body.XXXXXX")
trap 'rm -f "$tmp" "$body"' EXIT

if [ -n "$file" ]; then
  [ -f "$file" ] || die "file not found: $file"
  cat "$file" > "$tmp"
elif [ "$use_stdin" -eq 1 ]; then
  cat > "$tmp"
else
  printf '%s' "$text" > "$tmp"
fi

[ -s "$tmp" ] || die "content is empty"

# If the input already has YAML frontmatter, strip it and reuse title/type.
old_title=""
old_type=""
if [ "$(head -n 1 "$tmp")" = "---" ]; then
  close=$(awk 'NR>1 && $0=="---" {print NR; exit}' "$tmp")
  if [ -n "${close:-}" ]; then
    old_title=$(awk -v end="$close" 'NR>1 && NR<end && /^title:[[:space:]]*/ {sub(/^title:[[:space:]]*/,""); gsub(/^["'\'']|["'\'']$/,""); print; exit}' "$tmp")
    old_type=$(awk -v end="$close" 'NR>1 && NR<end && /^type:[[:space:]]*/ {sub(/^type:[[:space:]]*/,""); gsub(/^["'\'']|["'\'']$/,""); print; exit}' "$tmp")
    awk -v start="$close" 'NR>start' "$tmp" > "$body"
  else
    cat "$tmp" > "$body"
  fi
else
  cat "$tmp" > "$body"
fi

[ -s "$body" ] || die "body is empty after removing frontmatter"

hash=$($hash_cmd "$body" | awk '{print $1}')
hash8=${hash:0:8}
today=$(date -u +%Y-%m-%d)
now=$(date -u +%Y-%m-%dT%H:%M:%SZ)

[ -n "$title" ] || title="$old_title"
if [ -z "$title" ]; then
  title=$(awk 'NF { sub(/^#+[[:space:]]*/, ""); print; exit }' "$body" | cut -c1-80)
fi
[ -n "$title" ] || title="Untitled capture"
[ -n "$type" ] || type="note"
[ "$type_set" -eq 0 ] && [ -n "$old_type" ] && type="$old_type"

# Validate and normalize an explicit slug.
if [ -z "$slug" ]; then
  slug="inbox/$today-$hash8"
else
  case "$slug" in
    /*|*..*|*/|*//*) die "invalid slug: $slug" ;;
  esac
  slug=$(printf '%s' "$slug" | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/\.md$//; s#[^a-z0-9/_-]+#-#g; s#-+#-#g; s#(^|/)-#\1#g; s#-($|/)#\1#g')
  [ -n "$slug" ] || die "invalid slug"
fi

mkdir -p "$root"

# Dedupe by content hash.
existing=$(grep -rl --include='*.md' -F "content_hash: \"$hash\"" "$root" 2>/dev/null | head -n 1 || true)
if [ -n "$existing" ]; then
  existing_slug=$(awk -F': ' '/^slug:[[:space:]]*/ {gsub(/^slug:[[:space:]]*/,""); gsub(/"/,""); print; exit}' "$existing")
  [ -n "$existing_slug" ] || existing_slug="${existing#$root/}"; existing_slug="${existing_slug%.md}"
  if [ "$json" -eq 1 ]; then
    printf '{"status":"deduped","slug":"%s","path":"%s","content_hash":"%s"}\n' "$existing_slug" "$existing" "$hash"
  elif [ "$quiet" -eq 1 ]; then
    printf '%s\n' "$existing_slug"
  else
    printf 'captured:\n  slug: %s\n  path: %s\n  status: deduped\n  content_hash: %s\n' "$existing_slug" "$existing" "$hash"
  fi
  exit 0
fi

target="$root/$slug.md"
if [ -e "$target" ]; then
  n=2
  while [ -e "$root/$slug-$n.md" ]; do n=$((n+1)); done
  slug="$slug-$n"
  target="$root/$slug.md"
fi

mkdir -p "$(dirname "$target")"

yaml_escape() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }
json_escape() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }

out=$(mktemp "$(dirname "$target")/.capture.XXXXXX")
{
  printf '%s\n' '---'
  printf 'title: "%s"\n' "$(yaml_escape "$title")"
  printf 'type: "%s"\n' "$(yaml_escape "$type")"
  printf 'slug: "%s"\n' "$(yaml_escape "$slug")"
  printf 'captured_at: "%s"\n' "$now"
  printf 'captured_via: "capture.sh"\n'
  if [ -n "$source" ]; then
    printf 'source: "%s"\n' "$(yaml_escape "$source")"
  fi
  printf 'content_hash: "%s"\n' "$hash"
  printf '%s\n' '---'
  printf '\n# %s\n\n' "$title"
  cat "$body"
  # Ensure a trailing newline.
  [ -z "$(tail -c 1 "$body")" ] || printf '\n'
} > "$out"
mv "$out" "$target"

if [ "$json" -eq 1 ]; then
  printf '{"status":"created","slug":"%s","path":"%s","content_hash":"%s","title":"%s"}\n' \
    "$(json_escape "$slug")" "$(json_escape "$target")" "$hash" "$(json_escape "$title")"
elif [ "$quiet" -eq 1 ]; then
  printf '%s\n' "$slug"
else
  printf 'captured:\n  slug: %s\n  path: %s\n  status: created\n  content_hash: %s\n  title: %s\n' \
    "$slug" "$target" "$hash" "$title"
fi
