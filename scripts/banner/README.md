# Banner Generation

The repo banner (`assets/banner.jpg`) and the per-skill banners under `skills/<name>/assets/banner.{jpg,png}` are generated with Nano Banana Pro (Google Gemini 3 Pro Image) via OpenRouter.

# Reproducing the main banner

```bash
# From repo root
bash skills/terminal-poster/scripts/generate.sh \
  scripts/banner/banner-prompt.txt \
  assets/banner.jpg
```

Requires `OPENROUTER_API_KEY` set. Costs ~$0.002, takes ~30 seconds.

# Alternate banner

`banner-prompt-alt.txt` is a backup isometric-illustration prompt (Linear.app + Stripe style) if you want a more illustrated feel instead of the typography hero.

# Per-skill banners

Each `skills/<name>/assets/banner.{jpg,png}` was generated from `skills/<name>/assets/banner-prompt.txt`. To regenerate:

```bash
bash skills/terminal-poster/scripts/generate.sh \
  skills/cloudflare-dns/assets/banner-prompt.txt \
  skills/cloudflare-dns/assets/banner.jpg
```

🟡 **Note on output format:** Nano Banana Pro sometimes returns JPEG even when you ask for PNG. The `generate.sh` script warns you when this happens. If you need a strict PNG, run `ffmpeg -i banner.jpg banner.png` after generation.

🟡 **Text-rendering tips:** the model sometimes drops words or garbles labels. If a regeneration has spelling errors, tighten the prompt with:
- "the word X must appear in the image exactly once"
- "do not duplicate any label"
- "render text outside the card, not inside"

Don't try to fix small text errors by upscaling — regenerate with a tighter prompt instead.
