# Pre-Submit Checklist — `agent-skills`

Run through **every step** immediately before pasting the description into
[platform.claude.com/plugins/submit](https://platform.claude.com/plugins/submit).

The marketplace review pipeline pins whatever SHA you paste, and the description
lands in `claude-plugins-community/.claude-plugin/marketplace.json` verbatim. A
stale SHA or a ghost-skill mention is not easy to fix after approval — the
follow-up PR has to route through Anthropic again.

# 1. Refresh the pinned SHA

```bash
# From the repo root
git fetch origin main
git rev-parse origin/main
```

Copy the SHA into **both** places:

- `docs/marketplace-submission/marketplace-entry.json` → `source.sha` (replace the `<BUMP-TO-HEAD-AT-SUBMIT>` placeholder)
- `docs/marketplace-submission/README.md` → the "Pinned SHA" line under `Submission packet for agent-skills`

Verify neither file still contains the placeholder:

```bash
grep -n "BUMP-TO-HEAD-AT-SUBMIT" docs/marketplace-submission/
# → must be empty
```

# 2. Verify the skill count

```bash
ls -d skills/*/ | wc -l
# → must equal the count named in the description ("Six battle-tested skills")
```

If the counts disagree, the description is stale — update the enumeration in
`marketplace-entry.json` and in the description block inside
`docs/marketplace-submission/README.md`, then re-run this check.

# 3. Guard against ghost skills

```bash
grep -rn "ai-image-generation" docs/marketplace-submission/ .claude-plugin/ \
  README.md AGENTS.md CLAUDE.md
# → must be empty
```

The `ai-image-generation` skill never existed in this repo. If it re-appears
in any submission-related file, remove it before continuing.

Same idea, generalized — grep the description block against the actual skill
directories:

```bash
# List real skills
ls -1 skills/

# Extract skill mentions from the description block
python3 - <<'PY'
import json, pathlib, re
entry = json.loads(pathlib.Path("docs/marketplace-submission/marketplace-entry.json").read_text())
desc = entry["description"]
mentioned = set(re.findall(r"\b([a-z]+(?:-[a-z]+)+)\b", desc))
real = {p.name for p in pathlib.Path("skills").iterdir() if p.is_dir()}
ghosts = mentioned - real - {"agent-skills", "claude-code", "nano-banana"}
if ghosts:
    print("GHOSTS FOUND:", ghosts)
    raise SystemExit(1)
missing = real - mentioned
if missing:
    print("REAL SKILLS NOT MENTIONED:", missing)
    raise SystemExit(1)
print("OK — description mentions exactly the real skills")
PY
```

# 4. Verify the announcement banner image

`docs/marketplace-submission/announcement-banner.jpg` was regenerated from
`announcement-banner-prompt.txt` after the clean-sweep addition and now shows
"6 capability skills" on the agent-skills half of the sibling banner. Confirm
before attaching to any launch post:

```bash
# Confirm the prompt file is current
grep -n "capability skills" docs/marketplace-submission/announcement-banner-prompt.txt
# → must say "6 capability skills", not "5"

# Confirm the image is at least as new as the prompt
stat -f "%Sm %N" docs/marketplace-submission/announcement-banner-prompt.txt \
                 docs/marketplace-submission/announcement-banner.jpg
# → the .jpg mtime should be ≥ the .txt mtime

# If either check fails (or the prompt/spec changes again), regenerate:
# (requires $OPENROUTER_API_KEY, ~$0.002, ~30 s)
bash skills/terminal-poster/scripts/generate.sh \
  docs/marketplace-submission/announcement-banner-prompt.txt \
  docs/marketplace-submission/announcement-banner.jpg

# Vision-audit before shipping — Nano Banana Pro sometimes garbles labels
# (See AGENTS.md → Known gotchas)
```

# 5. Run the validator

```bash
python3 scripts/validate-skills.py
# → must exit 0 with "🟢 All N skills valid against agentskills.io spec."
```

CI also runs this on every push (see `.github/workflows/validate.yml`).

# 6. Confirm the plugin manifest is current

```bash
python3 -m json.tool .claude-plugin/plugin.json > /dev/null && echo "plugin.json OK"
python3 -m json.tool docs/marketplace-submission/marketplace-entry.json > /dev/null && echo "marketplace-entry.json OK"
```

# 7. Commit + push

```bash
git status                              # nothing dirty except deliberate updates
git add -A
git commit -m "Marketplace submission: refresh SHA + description"
git push origin main
git rev-parse origin/main               # confirm what was pushed matches step 1
```

Only now open [platform.claude.com/plugins/submit](https://platform.claude.com/plugins/submit)
and paste the description + SHA.

# 8. After approval

The community marketplace CI auto-bumps the pinned SHA on subsequent pushes,
so future updates ship without re-submitting. If the approval takes more than
a week, follow up on the form's reply thread or open an issue at
`anthropics/claude-plugins-community`.
