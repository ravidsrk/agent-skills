# Contributing

Thanks for wanting to contribute. The rules here keep the repo clean, spec-compliant, and useful for the people who'll install your skill.

If you're new to the [Agent Skills spec](https://agentskills.io/specification), skim the [README](README.md) first — the inline primer there shows a minimal `SKILL.md`.

---

# TL;DR

1. Fork → branch off `main`
2. Add `skills/<your-skill>/SKILL.md` (+ optional `README.md`, `scripts/`, `references/`, `assets/`)
3. Run `python3 scripts/validate-skills.py` → must pass
4. Add a row to the **Skills** table in [`README.md`](README.md)
5. Open a PR with a short demo (screenshot, log, or example output)

---

# Spec compliance

Every skill must conform to the [Agent Skills specification](https://agentskills.io/specification). Hard requirements:

| Rule | Why |
|---|---|
| One directory per skill, under `skills/` | Spec requirement |
| Folder name matches the `name` field in frontmatter | Spec requirement — validator enforces this |
| `name`: 1–64 chars, lowercase letters/digits/hyphens, no leading/trailing hyphen, no consecutive `--` | Spec requirement |
| `description`: 1–1024 chars, describes **what** + **when** with real trigger phrases | The agent reads this to decide whether to activate the skill |
| `SKILL.md` body kept under 500 lines | Progressive disclosure — push detail into `references/` |
| `compatibility` (if present): 1–500 chars | Spec requirement |

Run the validator before every commit:

```bash
python3 scripts/validate-skills.py
```

Expected output:

```
✅ your-skill
✅ ...

🟢 All N skills valid against agentskills.io spec.
```

---

# What makes a *good* skill

Spec compliance is the floor, not the ceiling. The [agentskills.io best-practices](https://agentskills.io/skill-creation/best-practices) page is canonical. Three things matter most:

🟢 **Start from real expertise.** Write skills from production-tested workflows you've actually run — not from "what an LLM thinks an X skill should look like." If you've never used it yourself, the agent won't either.

🟢 **Use progressive disclosure.** Keep `SKILL.md` short and scannable. Push detailed prompts, schemas, lookup tables, and edge-case docs into `references/<topic>.md` files that load only when the skill needs them. The agent's context is precious.

🟢 **Make the description fire on real triggers.** Include the actual phrases a user would say when they need this skill — verbs, jargon, brand names, error messages. The `description` field is how the agent decides whether to activate; vague descriptions = silent skills.

Two existing examples to use as references:

- [`skills/terminal-poster/SKILL.md`](skills/terminal-poster/SKILL.md) — image-generation skill with reference cluster files
- [`skills/deep-research/SKILL.md`](skills/deep-research/SKILL.md) — multi-source orchestrator with `scripts/sources/` modules

---

# Skill README

Every skill should ship with a `README.md` alongside its `SKILL.md`. The README is for **humans installing the skill**; `SKILL.md` is for **the agent using it**. Keep them separate.

A good skill `README.md` covers:

- What the skill does (1–2 paragraphs)
- When to use it (real trigger phrases)
- Install steps (env vars, dependencies, CLI tools)
- Usage examples (real commands, real output)
- Cost/latency if it calls paid APIs
- File layout
- Known gotchas
- Credits

See [`skills/deep-research/README.md`](skills/deep-research/README.md) for a full example.

---

# Before opening a PR

# 1. Validate

```bash
python3 scripts/validate-skills.py
```

Must pass. CI runs the same check.

# 2. Test end-to-end

Install your skill into at least one agent runtime (Claude Code, Cursor, OpenClaw, Codex, Mogra, etc.) and verify the agent picks it up from a natural prompt — not just a "use the X skill" command. Include a short verification note in the PR (screenshot, transcript, or log).

# 3. Scan for leaks — 🔴 ZERO TOLERANCE

The maintainers will reject any PR that leaks confidential data. Before pushing, scan your skill directory:

```bash
# Absolute paths from your machine
rg -n "/Users/|/home/[a-z]+/|C:\\\\Users\\\\|/workspace/" skills/<your-skill>/

# API keys, tokens, secrets
rg -n "(api[_-]?key|token|secret|password|bearer)\\s*[=:]" skills/<your-skill>/ -i

# Internal product / company codenames not yet public
# (use your judgment — search for names you wouldn't want on the front page of HN)
```

If anything shows up, sanitize before committing. Common patterns:

| Found | Fix |
|---|---|
| `/Users/you/Code/...` in example paths | Replace with `./` or `<your-project>/` |
| `MY_INTERNAL_API_KEY` hardcoded as fallback | Read from `os.environ` with a clear error if unset |
| Internal codename in comments | Generic verb ("the downstream artifact", "your project") |
| Company-specific workflow examples | Generalize or remove |

# 4. License compatibility

All skills must be MIT-compatible. If your skill bundles external scripts, libraries, fonts, or assets, they must be redistributable under MIT. When in doubt, link out instead of bundling.

---

# Adding a new skill — full checklist

```
[ ] skills/<your-skill>/SKILL.md         ← Required, valid frontmatter
[ ] skills/<your-skill>/README.md        ← Recommended, human-facing docs
[ ] skills/<your-skill>/scripts/         ← Optional, executable helpers
[ ] skills/<your-skill>/references/      ← Optional, progressive-disclosure docs
[ ] skills/<your-skill>/assets/          ← Optional, examples / templates
[ ] python3 scripts/validate-skills.py   ← Must pass
[ ] Row added to README.md skills table  ← Include trigger phrases column
[ ] Leak scan run (paths, secrets, names)
[ ] Tested in ≥1 runtime, evidence in PR
[ ] PR description explains the workflow + cost + when to use
```

---

# Editing an existing skill

Bug fixes, schema updates, new examples, and clarifications are always welcome. A few rules:

- 🟡 **Backwards compatibility.** If you change CLI flags, env vars, or output schema, call it out in the PR. Users may have wired the skill into their own pipelines.
- 🟡 **Gotchas section is sacred.** When you discover a new upstream quirk, add it to the skill's `Known gotchas` table with the fix. Future agents (and humans) will thank you.
- 🟢 **Voice contracts.** Some skills have explicit "this skill must not do X" rules (e.g. `deep-research` must never synthesize editorial prose). Respect them — they exist because the rule was learned the hard way.

---

# Skill ideas we'd love to see

If you're looking for a starting point, these gaps would help the most:

- 🔐 Security & hardening (recon, OWASP code audit, cloud misconfig, prompt-injection audit)
- 🌐 DNS + infra (Route53 migration, Vercel DNS, additional registrar wrappers)
- 🛠️ Dev workflow (TDD red-green-refactor, structured debug protocols, codebase cleanup)
- 📈 Marketing (SEO audit, schema markup, copywriting, page CRO)
- 🤖 Agent infra (Composio triggers, MCP servers, browser automation harnesses)
- 🚀 More platform migrations (Heroku → AWS, Vercel → Cloudflare, Render → Fly)

Open an issue first if you want to claim one — avoids duplicate work.

---

# Getting help

- Open a [discussion](https://github.com/ravidsrk/agent-skills/discussions) for design questions
- Open an [issue](https://github.com/ravidsrk/agent-skills/issues) for bugs or proposals
- Tag [@ravidsrk](https://x.com/ravidsrk) on X for quick async questions

---

# License

By contributing, you agree your contribution is MIT-licensed. See [LICENSE](LICENSE).
