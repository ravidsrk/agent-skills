# Copy slop patterns

26 prose patterns from the versioned slop-detect catalogue. Lower score = cleaner. Weight-0 rows are listed but add no points until promoted.

| # | ID | Pattern | Weight | Status | Antidote |
|---|---|---|---|---|---|
| 1 | `buzzword_density` | Buzzword density | 7 | active | Replace abstractions with the concrete job |
| 2 | `em_dash_overload` | Em-dash overload | 2 | decaying | Use periods and commas |
| 3 | `antithesis_construction` | "Not just X, but Y" | 6 | rising | State the claim directly |
| 4 | `filler_openers` | Filler opener | 5 | decaying | Start with the product or the audience |
| 5 | `formulaic_closers` | Formulaic closer | 4 | historical | End with a specific next step |
| 6 | `rule_of_three` | Rule-of-three lists | 4 | decaying | Use the number of items the content needs |
| 7 | `whether_youre` | "Whether you're X or Y" | 3 | active | Address one audience concretely |
| 8 | `unicode_artifacts` | Unicode tells | 0 | retired | Plain ASCII punctuation |
| 9 | `emoji_bullet_headers` | Emoji bullet headers | 3 | active | Use headings, not emoji bullets |
| 10 | `hidden_tag_characters` | Hidden tag characters | 0 | review | Remove invisible characters |
| 11 | `invisible_characters` | Invisible characters | 0 | review | Strip zero-width and directional marks |
| 12 | `fake_bold_math_alnum` | Fake-bold Unicode | 4 | active | Use real emphasis markup |
| 13 | `chatbot_markup_leak` | Chatbot markup leak | 0 | review | Remove `**`, `###`, and JSON residue from rendered copy |
| 14 | `chatbot_reply_residue` | Reply residue | 0 | review | Remove "Certainly!", "Here's...", and meta commentary |
| 15 | `ai_referral_utm_links` | AI referral UTM links | 0 | review | Use clean canonical links |
| 16 | `unfilled_placeholders` | Unfilled placeholders | 0 | review | Replace `[Company]`, `Lorem`, `TODO` |
| 17 | `leaked_markdown` | Raw Markdown | 0 | review | Render Markdown; do not show source syntax |
| 18 | `structural_fake_social_proof` | Fake social proof | 0 | review | Use verifiable logos/quotes or remove |
| 19 | `bare_antithesis` | Bare antithesis | 0 | review | Rewrite as a positive claim |
| 20 | `emoji_heading_ratio` | Emoji heading ratio | 0 | review | Remove emoji from headings |
| 21 | `announced_structure` | Announced structure | 0 | review | Remove "In this section we will..." |
| 22 | `restated_thesis_closer` | Restated thesis closer | 0 | review | Close with the action, not a summary |
| 23 | `context_leak_copy` | Context leak | 0 | review | Remove instructions meant for the model |
| 24 | `trailing_participial_clauses` | Participial tails | 0 | review | Split into two sentences |
| 25 | `sentence_length_uniformity` | Uniform sentence length | 0 | review | Vary rhythm; keep it readable |
| 26 | `excess_vocabulary_log_odds` | Unusual vocabulary log-odds | 0 | review | Use the words the audience uses |

# Tier boundaries

- Clean: 0–7
- Mild: 8–19
- Heavy: ≥20

# High-value rewrites

| Instead of | Write |
|---|---|
| "AI-powered platform that reimagines workflow" | "Issue tracking for product teams" |
| "Build faster with our next-generation tools" | "Ship a landing page in an afternoon" |
| "Get started" | "See the live demo" / "Start my free trial" |
| "Trusted by 1,000+ teams" (no logos) | "Used by Acme, Northwind, and Contoso" (with permission) |
| "Whether you're a founder or an enterprise" | "For seed-stage founders" |

# Evidence rules

- Quote the exact sentence and its selector/location.
- Count density, not a single buzzword.
- Do not flag a pattern that the page does not contain just because the template usually has it.
- A clean copy score does not excuse a heavy design score, or vice versa.
