# Banner Reproducer

Regenerates `assets/banner.png` from `scripts/banner/spec.yaml` using the `terminal-poster` skill.

# Usage

```bash
# From repo root
bash skills/terminal-poster/scripts/make-poster.sh \
  scripts/banner/spec.yaml \
  assets/banner.png
```

Requires `OPENROUTER_API_KEY` set. Costs ~$0.002, takes ~30 seconds.

Edit `spec.yaml` to update the panels — each panel becomes one column of the poster. See `skills/terminal-poster/SKILL.md` for the spec format.
