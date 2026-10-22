# Ledger — the frozen definition of done

Read this in Phase 1. The ledger turns the repo's docs into a short, ordered list of items that a stranger could check from outside the code. It is built on the brief (§1a), never on a guess about the product. Once frozen, it is the only definition of done.

## 1. Sources and precedence

When docs disagree, the higher one wins; log each conflict in `DECISIONS.md`:

PRD / product spec > feature specs > design docs & mockups > architecture / implementation plan > GitHub issues > README.

Put the product's promise, from the PRD, in `one_liner`: one sentence a stranger understands. It is the brief's `one_liner`, word for word.

## 1a. The brief — `.finish/product.json`

Written in Phase 0, before the code is read (protocol §3.2). It is what the run understands the product to be, one claim per fact, and the verifier approves it with the ledger before the freeze. A full example: `templates/product.example.json`.

| Field | What goes in it |
|---|---|
| `product`, `one_liner` | The product's name and its promise in the docs' own terms; the ledger copies both |
| `one_liner_claims` | The `doc` or `seen` claims the one_liner rests on |
| `docs` | Every doc read in full (repo paths, including `.finish/sources/` exports) |
| `claims[]` | `id` (`B-001`…), `basis`, `claim`, `source` (a repo path; `#anchor` or `:line` allowed), `quote` |
| `unknowns` | Every question the docs leave open that a ledger would need answered — listed, never guessed |

| `basis` | Source | `quote` | What it may say |
|---|---|---|---|
| `doc` | A doc in `docs` — README, PRD, spec, design doc, a mockup, an issue export in `.finish/sources/` | Required for text: copied verbatim, 3+ words. Images and PDFs without text: none; the verifier opens them | What the product is, who it's for, what it must do, what's later or out of scope |
| `seen` | A screenshot or log you captured in `.finish/evidence/` | Optional (logs) | What the running app does — above all where it differs from the docs |
| `code` | A source file | Required | Only what exists (a framework, a table, an endpoint), never what it's for |

`ledger.sh brief` checks every source exists, that no claim cites `.finish/` notes or Finish Line's tests, and that every quote is in its file (whitespace, case, typographic quotes and markdown marks are ignored; PDFs through `pdftotext`). It writes `.finish/PRODUCT.md`, the readable version. After the freeze the brief changes only through `ledger.sh amend --rebaseline` (§8), and the verifier checks each changed claim against its source.

## 2. Writing criteria

- Every criterion is observable from outside: UI state, URL, API response, database row, email in Mailpit, file in storage, exit code.
- Every criterion is one line of the form **Given … when … then …** (`ledger.sh validate` enforces it).
- Every journey has at least one unhappy path (invalid input, server or network error, empty state) and one persistence check (reload or reopen → data still there).
- Each item must be verifiable in one session. Split anything bigger.
- No implementation details ("uses Redis"). The docs define what, not how.

## 3. The scope cut — P0 / P1 / P2

Decide this yourself; it's the most important call in the run.

- **P0** — the user the docs describe gets the core promise end to end, in the brief's terms, and finds their result again wherever the product keeps one. Sign-up, payment and coming back are part of P0 only when the brief has claims for them: a CLI, an internal tool or a one-page utility has no sign-up journey, and a product whose docs never mention pricing has no payment. Plus every launch gate below that applies.
- **P1** — in the docs, valuable, not needed for the P0 path.
- **P2** — "future", "phase 2", nice-to-have.

When in doubt, it's P1. A smaller P0 that ships beats a complete P0 that never does.

## 4. Launch gates (P0 when they apply)

A gate applies when the brief shows it does — the auth gate needs claims about accounts, the mobile gate a mobile app the docs name, the privacy gate personal data — and its item cites those claims. Boot, build, secrets and env apply to any product that runs; they can cite a `code` claim about how it's built.

| Gate | Usual `verify.method` |
|---|---|
| Fresh clone → `.finish/init.sh` → app runs, no manual steps (**always item 1**, `G-000`; boot the clone on its own port, e.g. `PORT=3100`) | `command` |
| Production build succeeds for every surface | `command` |
| No console errors, unhandled rejections or unexpected 4xx/5xx on any P0 journey | covered by the web fixture in every journey spec |
| Auth complete: sign up, log in, log out, password reset or magic link, session survives reload | `e2e-web` / `e2e-mobile` journeys |
| Loading, empty and error states on every P0 screen | inside the journeys |
| Web: usable at 375×812 and 1440×900; axe finds no serious/critical violations on P0 screens | `e2e-web` (`G-…spec.ts` visiting each P0 screen) |
| Mobile: release build installs and cold-starts without crashing (Android emulator; iOS simulator on macOS); permission prompts handled | `command` + `e2e-mobile` |
| Migrations run from an empty database; seed/demo data available | `command` |
| `.env.example` lists every variable the code reads | `command` |
| gitleaks clean; no critical dependency vulnerabilities | `command` |
| Privacy policy and terms pages exist, if the product collects personal data | `e2e-web` |
| README "how to run" instructions are true | `command` (run them in a fresh clone) |
| P0 journeys pass against a deployed preview | `command` (`BASE_URL=… npx playwright test …`) |

## 5. Item order = work order

`ledger.sh next` takes the first in-scope `failing` item in file order, so write items in the order they should be built:

1. `G-000` boot gate
2. journeys, in the order a user meets them (signup before dashboard before billing)
3. features
4. remaining gates

IDs: `G-###` gates, `J-###` journeys, `F-###` features, `I-###` defects found during the run (§8a). Never reuse an ID.

## 6. Schema

```json
{
  "product": "<name>",
  "one_liner": "<core promise, one sentence>",
  "items": [
    {
      "id": "J-001",
      "type": "journey",
      "priority": "P0",
      "platforms": ["web"],
      "title": "New user signs up and reaches an empty dashboard",
      "source": "B-002, B-003",
      "acceptance": ["Given …, when …, then …"],
      "verify": { "method": "e2e-web", "spec": "e2e/finish/J-001.spec.ts" },
      "status": "failing",
      "attempts": 0,
      "evidence": [],
      "notes": ""
    }
  ]
}
```

| Field | Values |
|---|---|
| `type` | `journey` · `feature` · `gate` · `issue` |
| `source` | The brief claims the item comes from, e.g. `"B-002, B-003"`. Journeys and features need a `doc` or `seen` claim among them; gates may cite `code`; an `issue` cites the evidence it was found in. `ledger.sh validate` checks every cited claim exists. |
| `priority` | `P0` · `P1` · `P2` |
| `platforms` | non-empty list, e.g. `web`, `android`, `ios`, `api`, `cli` |
| `verify.method` | `e2e-web` (spec `e2e/finish/<ID>.spec.ts`) · `e2e-mobile` (`.maestro/finish/<ID>.yaml`) · `api` (`<backend tests>/finish/…`) · `command` (`verify.command`, a shell command that exits 0; `verify.sh` re-runs it, so it must never call `verify.sh`) |
| `status` | `failing` · `passing` · `stuck` · `needs_owner` — all items start `failing`, `attempts` 0, `evidence` `[]`, `notes` `""`. `stuck` is a pause, never an end: `ledger.sh round` brings the item back as a research round, as many times as it takes. |

Spec paths must sit under a `finish/` directory: that's what makes them protected by `tamper.sh`. A full worked example: `templates/ledger.example.json`.

The criteria hash covers everything except `status`, `attempts`, `evidence` and `notes` — so after the freeze even a title or spec path changes only through an amendment (§8). `ledger.sh criteria <ID>` separately fingerprints the immutable item (including its ID, source, criteria and verify configuration), product/promise and exact supporting brief. An item-mode PASS report must contain exactly one matching `CRITERION: <hash>` as well as its code `STATE:`; older reports without this identity require fresh verification. Mutable status/attempt/evidence/note updates do not change it.

## 7. Freeze

```bash
./.finish/bin/ledger.sh brief             # until BRIEF: VALID (the brief was committed in Phase 0)
./.finish/bin/ledger.sh validate          # until LEDGER: VALID
git add .finish/ledger.json .finish/product.json .finish/PRODUCT.md && git commit -m "chore(finish): definition of done"
./.finish/bin/ledger.sh lock              # first time: writes .finish/freeze-review/request.md and exits 3
#   finish-verifier, freeze mode, with .finish/freeze-review/request.md → .finish/freeze-review/review.md
#   REJECT: fix what it lists, commit, lock again (a new request needs a new review)
./.finish/bin/ledger.sh lock              # after APPROVE: writes FREEZE (this commit) + LEDGER.lock
git add .finish/FREEZE .finish/LEDGER.lock .finish/freeze-review && git commit -m "chore(finish): freeze ledger"
```

New freeze reviews use `freeze-review/`, which cannot collide with the `FREEZE` marker on case-insensitive filesystems. `lock` refuses occupied/symlink marker paths, orphan locks and legacy review paths before a new freeze; it never deletes or migrates them automatically. Existing valid case-sensitive legacy `freeze/` reviews may be checked read-only when no current review directory exists. Ambiguous states require an explicitly reviewed migration preserving the original request/review bytes. Failed request or marker writes/installations return nonzero and never print a frozen success.

The verifier reads the docs itself first, then checks every claim against its source, the brief against the docs (nothing missing, no guess where they're silent), and every item against the claims it cites. Without its `APPROVE` for exactly this brief and ledger, `lock` doesn't freeze, and the runner reverts a session that freezes any other way.

## 8. Amendments — changing the definition of done without a human

Write the complete new ledger to `.finish/ledger.proposed.json`, then:

```bash
./.finish/bin/ledger.sh amend "<one-line reason citing the doc>"
```

| Change | What happens |
|---|---|
| Additions only: new items, new criteria, higher priority, more platforms | Applied at once (`strengthening`). Changed items go back to `failing` to be re-verified. |
| Anything else: remove or reword a criterion, demote, change a spec path, remove an item | Exit 3 and a request file `.finish/amendments/<NNN>.request.md`. The verifier reviews it in amendment mode against the docs. `VERDICT: APPROVE` → `ledger.sh amend --apply <NNN>`. `REJECT` → drop it and keep working the item (research rounds, protocol §5.1). |
| A legitimate change `tamper.sh` flags (a real fix to `verify.sh`, a test config the stack needs) | Commit it, then `ledger.sh amend --rebaseline "<why>"` — same review; on approval FREEZE moves to HEAD. Changes to `.finish/bin/` can never be rebaselined. |

Non-additive amendments are capped at `FINISH_MAX_AMENDMENTS` (default 5) per product. Every amendment is logged in `.finish/amendments.jsonl` with the before/after criteria hash and FREEZE, and each ledger change keeps a snapshot (`amendments/<NNN>.ledger.json`). After every session the runner re-derives each step from the snapshots — it never trusts the logged class — and reverts any lock or FREEZE change it can't explain. A request applies only to the definition of done it was reviewed against, and only once.

Commit after each amendment: `git add .finish && git commit -m "chore(finish): amendment <NNN> — <reason>"`. Ratchet entries for removed items or changed spec paths stop counting on their own.

## 8a. Defects found during the run

Any defect found after the freeze — by the verifier (`OTHER DEFECTS`, first-user `DEFECT`s), Lighthouse, a security or code review, or while working on another item — becomes an item, so it gets a failing test, a fix, the verifier and the tamper guard like everything else:

```bash
./.finish/bin/ledger.sh issue --title "Signup button hidden behind the footer on phones" \
  --given "Given a visitor on /signup at 375x812, when the page loads, then the Sign up button is fully visible" \
  --source .finish/evidence/_first-user/report.md
git add .finish && git commit -m "chore(finish): file I-001 — signup button hidden on phones"
```

It's an addition, so it applies at once (no review). Defaults: priority = the current scope (`P0`), platform `web`, spec `e2e/finish/I-###.spec.ts`; the platform decides how it's verified — `--platform android|ios` for a Maestro flow, `--platform api` with `--spec <tests/finish/…>` for an API test (whatever its file name), `--command "<cmd>"` for a command check; `--method` overrides. The criterion states the correct behaviour, so the test fails until the defect is fixed. A defect is never deferred to `LATER.md`; only ideas and features the docs don't ask for are.

## 9. No public refreeze bypass

`lock` freezes a new reviewed definition once; `lock --refreeze` is unsupported. A changed frozen definition, including an owner-requested change, must use the amendment/rebaseline procedure in §8 with its request-bound review and cap. There are no internal callers of the removed flag. Editing the definition and calling lock again cannot replace review or rewrite freeze markers.
