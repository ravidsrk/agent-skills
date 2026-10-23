# Design slop patterns

45 CSS/DOM patterns from the versioned slop-detect catalogue. Lower score = cleaner. Weight-0 rows are listed but add no points until promoted.

| # | ID | Pattern | Weight | Status | Antidote |
|---|---|---|---|---|---|
| 1 | `slop_fonts` | Slop fonts (Inter/Geist/Plus Jakarta as the only face) | 8 | decaying | Display + body + mono; pick a distinctive display face |
| 2 | `slop_fonts_2026` | 2026 slop fonts | 0 | review | Check the live list; do not swap one slop font for another |
| 3 | `purple_accent` | Vibe purple accent | 4 | decaying | One intentional accent; not indigo-600 by default |
| 4 | `gradient_text` | Gradient text | 6 | active | Solid ink; use weight/size for emphasis |
| 5 | `gradient_backgrounds` | Gradient backgrounds | 4 | active | Flat surface or a real product visual |
| 6 | `accent_stripe` | Accent stripe | 6 | active | Remove the decorative stripe; use hierarchy |
| 7 | `accent_stripe_2026` | Accent stripe 2026 | 0 | review | Same |
| 8 | `glassmorphism` | Glass panels | 4 | active | Solid surfaces with real elevation |
| 9 | `colored_glows` | Colored glows | 4 | active | Remove glow; use contrast and spacing |
| 10 | `centered_hero` | Centered hero | 4 | active | Asymmetric hero (60/40, text + product) |
| 11 | `hero_eyebrow_pill` | Eyebrow pill | 5 | active | Real news only, or no eyebrow |
| 12 | `all_caps_labels` | All-caps labels | 0 | retired | Sentence case |
| 13 | `eyebrow_label` | Eyebrow labels | 0 | review | Keep only if it carries verifiable news |
| 14 | `perma_dark_mode` | Perma dark mode | 4 | active | Choose a theme that fits the audience; support both if needed |
| 15 | `icon_card_grid` | Three-icon card grid | 4 | active | One product-narrative section instead |
| 16 | `numbered_steps` | Numbered steps | 3 | active | Use a real flow or a demo, not decorative 01/02/03 |
| 17 | `stat_banner` | Stat banner | 3 | active | Cite the stat and its source; otherwise remove |
| 18 | `faq_accordion` | FAQ accordion | 2 | active | Keep only if the questions are real and specific |
| 19 | `gradient_letter_avatars` | Gradient letter avatars | 5 | active | Real photos or plain initials |
| 20 | `bento_grid` | Bento grid | 4 | active | Use when the content is genuinely heterogeneous |
| 21 | `aurora_mesh_gradient` | Aurora blobs | 5 | active | Remove; use a real screenshot or flat color |
| 22 | `ai_sparkle_badges` | AI sparkles | 3 | active | Remove the sparkle; say what the product does |
| 23 | `cream_default_bg` | Cream default background | 7 | active | Choose a surface deliberately, not the default cream |
| 24 | `low_contrast_text` | Low-contrast text | 7 | active | Meet WCAG AA; verify with a contrast checker |
| 25 | `crushed_tracking` | Crushed letter-spacing | 5 | active | Tune tracking per size; never blanket `tracking-tight` |
| 26 | `oversized_hero_h1` | Oversized H1 | 4 | active | Size for the message, not for the screenshot |
| 27 | `nested_cards` | Nested cards | 4 | active | Flatten; one surface per idea |
| 28 | `flat_type_hierarchy` | Flat type hierarchy | 3 | active | Distinct display/body/mono roles |
| 29 | `scaffold_defaults_unedited` | Unedited scaffold defaults | 0 | review | Replace title, icons, OG, and copy |
| 30 | `hero_accent_word` | Hero accent word | 0 | review | Use only when the word carries meaning |
| 31 | `template_chrome_2026` | Template chrome 2026 | 0 | review | Remove decorative badges and borders |
| 32 | `uniform_radius_shadow` | Uniform radius/shadow | 0 | review | Vary elevation by role |
| 33 | `editorial_cream_kit` | Editorial cream kit | 0 | review | Ensure the aesthetic matches the audience |
| 34 | `template_page_order` | Template page order | 0 | review | At least one product-narrative section before features |
| 35 | `pulsing_status_badge` | Pulsing status badge | 0 | review | Static text or remove |
| 36 | `display_mono_heading` | Mono heading | 0 | review | Mono for code/numbers, not headlines |
| 37 | `chip_rainbow` | Rainbow chips | 0 | review | One accent; not a row of colored tags |
| 38 | `fake_macos_terminal` | Fake macOS terminal | 0 | review | Use a real terminal capture or a code block |
| 39 | `fake_logo_bar` | Fake logo bar | 0 | review | Real, verifiable logos only |
| 40 | `infinite_marquee_ticker` | Marquee ticker | 0 | review | Static, readable proof |
| 41 | `fade_up_monoculture` | Fade-up monoculture | 0 | review | One purposeful motion, or none |
| 42 | `cursor_spotlight_gradient` | Cursor spotlight | 0 | review | Remove decorative pointer effects |
| 43 | `uniform_card_hover` | Uniform card hover | 0 | review | Hover only when it communicates affordance |
| 44 | `section_template_repetition` | Repeated section template | 0 | review | Vary layout by content role |
| 45 | `unthemed_browser_surfaces` | Unthemed browser surfaces | 0 | review | Theme scrollbars, selection, and form controls |

# Tier boundaries

- Clean: 0–9
- Mild: 10–27
- Heavy: ≥28

# Evidence rules

- A pattern only counts when you can point to the literal DOM/CSS.
- A weight-0 row is still worth reporting as a review note, but it does not change the score.
- Do not infer a pattern from a screenshot alone when the DOM is available.
- Do not count the same selector twice unless it violates two distinct patterns.
