# Ledger — the frozen definition of done

Read this in Phase 1. The ledger turns the repo's docs into a short, ordered list of items that a stranger could check from outside the code. Once frozen, it is the only definition of done.

## 1. Sources and precedence

When docs disagree, the higher one wins; log each conflict in `DECISIONS.md`:

PRD / product spec > feature specs > design docs & mockups > architecture / implementation plan > GitHub issues > README.

Put the product's promise, from the PRD, in `one_liner`: one sentence a stranger understands.

## 2. Writing criteria

- Every criterion is observable from outside: UI state, URL, API response, database row, email in Mailpit, file in storage, exit code.
- Every criterion is one line of the form **Given … when … then …** (`ledger.sh validate` enforces it).
- Every journey has at least one unhappy path (invalid input, server or network error, empty state) and one persistence check (reload or reopen → data still there).
- Each item must be verifiable in one session. Split anything bigger.
- No implementation details ("uses Redis"). The docs define what, not how.

## 3. The scope cut — P0 / P1 / P2

Decide this yourself; it's the most important call in the run.

- **P0** — a stranger can discover the product → sign up → get the core promise → pay (only if the PRD charges at launch) → come back later and find their data. Plus every launch gate below that applies.
- **P1** — in the docs, valuable, not needed for the P0 path.
- **P2** — "future", "phase 2", nice-to-have.

When in doubt, it's P1. A smaller P0 that ships beats a complete P0 that never does.

## 4. Launch gates (P0 when they apply)

| Gate | Usual `verify.method` |
|---|---|
| Fresh clone → `.finish/init.sh` → app runs, no manual steps (**always item 1**, `G-000`) | `command` |
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

IDs: `G-###` gates, `J-###` journeys, `F-###` features. Never reuse an ID.

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
      "source": "docs/PRD.md#onboarding",
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
| `type` | `journey` · `feature` · `gate` |
| `priority` | `P0` · `P1` · `P2` |
| `platforms` | non-empty list, e.g. `web`, `android`, `ios`, `api`, `cli` |
| `verify.method` | `e2e-web` (spec `e2e/finish/<ID>.spec.ts`) · `e2e-mobile` (`.maestro/finish/<ID>.yaml`) · `api` (`<backend tests>/finish/…`) · `command` (`verify.command`, a shell command that exits 0) |
| `status` | `failing` · `passing` · `stuck` · `blocked_human` — all items start `failing`, `attempts` 0, `evidence` `[]`, `notes` `""` |

Spec paths must sit under a `finish/` directory: that's what makes them protected by `tamper.sh`. A full worked example: `templates/ledger.example.json`.

The criteria hash covers everything except `status`, `attempts`, `evidence` and `notes` — so after the freeze even a title or spec path can't change without the human.

## 7. Freeze

```bash
./.finish/bin/ledger.sh validate          # until LEDGER: VALID
git add .finish/ledger.json && git commit -m "chore(finish): definition of done"
./.finish/bin/ledger.sh lock              # writes FREEZE (this commit) + LEDGER.lock
git add .finish/FREEZE .finish/LEDGER.lock && git commit -m "chore(finish): freeze ledger"
```

## 8. Re-freezing (human only)

To change the definition of done after the freeze — add a criterion, split an item, move something to P1, clear a tamper false positive:

```bash
$EDITOR .finish/ledger.json
git add .finish/ledger.json && git commit -m "chore(finish): revise definition of done"
.finish/bin/ledger.sh lock --refreeze
git add .finish/FREEZE .finish/LEDGER.lock && git commit -m "chore(finish): re-freeze ledger"
```

The runner treats an agent that does this as a guard trip and stops.
