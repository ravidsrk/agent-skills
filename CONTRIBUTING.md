# Contributing

Thanks for wanting to contribute. The rules here keep the repo clean and spec-compliant.

# Spec

Every skill must conform to the [Agent Skills specification](https://agentskills.io/specification). Key requirements:

- One directory per skill, under `skills/`
- Folder name matches the `name` field in frontmatter
- `name`: 1–64 chars, lowercase letters/digits/hyphens, no leading/trailing hyphen, no consecutive hyphens
- `description`: 1–1024 chars; describe **what** the skill does and **when** to use it (with keywords/trigger phrases)
- `SKILL.md` body kept under 500 lines; move detailed reference material into `references/`

# Before opening a PR

1. **Validate** — run the validator and make sure it passes:

   ```bash
   python3 scripts/validate-skills.py
   ```

2. **Test the skill end-to-end** in at least one agent runtime (Claude Code, Mogra, Cursor, etc.) and include a short verification note in the PR.

3. **No secrets, no private paths.** Scan your skill for:
   - Absolute paths from your machine (`/Users/you/...`, `/workspace/.private/...`)
   - API keys, tokens, or anything from a `.env`
   - Internal product or company names that aren't public yet

   The maintainers reserve the right to reject any PR that leaks confidential data.

4. **License compatibility.** All skills must be MIT-compatible. If your skill uses an external script, library, or asset, it must be redistributable under MIT.

# What makes a good skill

The [agentskills.io best practices](https://agentskills.io/skill-creation/best-practices) page is the canonical guide. Three things matter most:

- 🟢 **Start from real expertise** — write skills from production-tested workflows you've actually run, not from "what an LLM thinks an X skill should look like"
- 🟢 **Use progressive disclosure** — keep `SKILL.md` short, push detail into `references/` files that only load when needed
- 🟢 **Make the description fire on real triggers** — include the actual phrases a user would say when they need this skill

# Adding a new skill

1. Create `skills/<your-skill-name>/SKILL.md` with valid frontmatter
2. Add optional `scripts/`, `references/`, `assets/` subdirectories as needed
3. Add a row to the table in [`README.md`](README.md)
4. Run `python3 scripts/validate-skills.py`
5. Open a PR with a screenshot or example output

# License

By contributing, you agree your contribution is MIT-licensed.
