#!/usr/bin/env bash
# Re-author HEAD as the repository's configured user and strip agent trailers from its message. integrate.sh runs it
# on every integrated commit (git rebase --exec), because a cherry-pick keeps the owner agent's author.
#
# Trailers removed: lines matching STRIP_TRAILERS_RE (an ERE; default: AI co-author, agent session and
# "Generated with" lines).
set -euo pipefail

name=$(git config user.name || true); email=$(git config user.email || true)
if [ -z "$name" ] || [ -z "$email" ]; then
  echo "reauthor.sh: set the user's identity first: git config user.name '…' && git config user.email '…'" >&2
  exit 1
fi
re="${STRIP_TRAILERS_RE:-^(Co-[Aa]uthored-[Bb]y:.*(Claude|Copilot|Cursor|GPT|Gemini|noreply@anthropic\.com)|Claude-Session:|.*Generated with \[)}"
msg=$(git log -1 --format=%B | grep -Ev "$re" || true)
# Drop the blank lines a removed trailer block leaves at the end.
msg=$(printf '%s\n' "$msg" | sed -e :a -e '/^\n*$/{$d;N;ba' -e '}')
git -c core.hooksPath=/dev/null commit -q --amend --reset-author -m "$msg"
