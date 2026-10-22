# Verification toolkit

Read this in Phase 0 when you write `.finish/init.sh` and fill `.finish/verify.sh`, and whenever you write a spec. Every command here is a starting point: confirm flags with `--help` before you rely on them (Law 7).

## 1. Two kinds of checking — both are required for every item

| | Persistent tests (the gate) | Interactive eyes (finding problems) |
|---|---|---|
| Web | `@playwright/test` specs in `e2e/finish/` using `finish-fixture.ts` | `playwright-cli` |
| Mobile | Maestro flows in `.maestro/finish/` | `maestro test` on a single flow, `maestro studio`, screenshots |
| API | the stack's test runner against the running server and real local DB | `curl` / `httpie` |
| Perf / a11y | axe inside every web spec (`a11y()`) | `npx lighthouse` |

Interactive checks find problems; persistent tests prove fixes stay fixed.

## 2. `.finish/init.sh`

Idempotent; safe to run every session. Shape:

```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
PORT="${PORT:-3000}"                                   # honour PORT: a fresh clone boots beside this checkout on 3100
mkdir -p .finish/logs                                  # gitignored, so absent in a fresh clone
curl -fsS -o /dev/null "http://localhost:$PORT/" 2>/dev/null && exit 0   # already up on this port
[ -f .env.local ] || cp .env.example .env.local      # safe local defaults only
docker compose -f .finish/compose.yml up -d --wait     # or: supabase start / firebase emulators:start
npm ci                                                 # the stack's lockfile install
npm run db:migrate && npm run db:seed                  # from an EMPTY database
PORT="$PORT" nohup npm run dev > .finish/logs/app.log 2>&1 &
echo $! > .finish/logs/app.pid                         # lets a fresh-clone check stop its own app
for i in $(seq 1 60); do curl -fs -o /dev/null "http://localhost:$PORT/" && exit 0; sleep 2; done
echo "app did not become healthy; see .finish/logs/app.log"; exit 1
```

The app must read its port from `PORT`, so the fresh-clone gate (`PORT=3100`) proves the clone boots instead of hitting the app already running on 3000.

## 3. Real local infrastructure

Never mock your own backend in E2E. Run the real dependencies locally:

```yaml
# .finish/compose.yml — every port bound to 127.0.0.1 so test data never leaves the machine
name: myapp-finish    # fixed project name: a fresh clone reuses these containers instead of fighting for ports
services:
  postgres:
    image: postgres:16
    environment: { POSTGRES_PASSWORD: postgres, POSTGRES_DB: app }
    ports: ["127.0.0.1:5432:5432"]
    healthcheck: { test: ["CMD", "pg_isready", "-U", "postgres"], interval: 2s, retries: 30 }
  redis:
    image: redis:7
    ports: ["127.0.0.1:6379:6379"]
  mailpit:            # SMTP on 1025, UI + API on 8025 — assert emails via http://localhost:8025/api/v1/messages
    image: axllent/mailpit
    ports: ["127.0.0.1:1025:1025", "127.0.0.1:8025:8025"]
  minio:              # S3-compatible storage on 9000
    image: minio/minio
    command: server /data
    environment: { MINIO_ROOT_USER: minio, MINIO_ROOT_PASSWORD: minio12345 }
    ports: ["127.0.0.1:9000:9000"]
```

| Service in the code | Local stand-in |
|---|---|
| Supabase | `supabase start` (Supabase CLI) |
| Firebase Auth / Firestore / Functions | `firebase emulators:start` |
| Stripe | test-mode keys + `stripe listen --forward-to localhost:3000/api/webhooks/stripe` |
| SES / SendGrid / Resend / SMTP | point SMTP at Mailpit; for API-only providers, their sandbox mode |
| S3 / R2 / GCS | MinIO (S3 API) or the provider's emulator |
| LLM APIs | real key with the cheapest adequate model; no key → that criterion becomes an owner action (`ledger.sh owner … 'test -n "$OPENAI_API_KEY"'`, approved by the verifier in owner mode) |

## 4. Filling `.finish/verify.sh`

Every `STAGE_*` is a command or `n/a: <reason>`. Spec stages get their files from the ledger automatically (all in-scope specs in full mode, passing specs in `--quick`); use `{}` in the command to run once per spec instead of once with all of them. `STAGE_COMMANDS` is pre-set: it runs the ledger's `command` items the same way, logging each to `.finish/evidence/<ID>/command.log`.

Get the gate right in Phase 0: once the ledger is frozen, `tamper.sh` fails on any change to `verify.sh` except filling in a stage that was empty or `n/a`. A genuine fix after that goes through a verifier-approved `ledger.sh amend --rebaseline`.

| Stack | INSTALL | TYPECHECK | LINT | UNIT | BUILD |
|---|---|---|---|---|---|
| Node / TS (npm) | `npm ci` | `npx tsc --noEmit` | `npx eslint .` | `npx vitest run` or `npx jest` | `npm run build` |
| pnpm | `pnpm install --frozen-lockfile` | `pnpm exec tsc --noEmit` | `pnpm lint` | `pnpm test` | `pnpm build` |
| Python | `uv sync --frozen` or `pip install -r requirements.txt` | `uv run mypy .` or `pyright` | `uv run ruff check .` | `uv run pytest -q` | `uv build` / `n/a: no build step` |
| Flutter | `flutter pub get` | `flutter analyze` | `n/a: analyze covers lint` | `flutter test` | `flutter build apk --release` |
| React Native / Expo | `npm ci` | `npx tsc --noEmit` | `npx eslint .` | `npx jest` | `npx expo prebuild --clean && (cd android && ./gradlew assembleRelease)` |
| Android (Kotlin) | `n/a: gradle resolves deps` | `./gradlew compileDebugKotlin` | `./gradlew lint` | `./gradlew testDebugUnitTest` | `./gradlew assembleRelease` |
| iOS (Swift) | `n/a: SPM resolves in build` | `n/a: build typechecks` | `swiftlint` | `xcodebuild test -scheme App -destination 'platform=iOS Simulator,name=iPhone 16'` | `xcodebuild -scheme App -configuration Release build` |
| Go | `go mod download` | `go vet ./...` | `golangci-lint run` | `go test ./...` | `go build ./...` |

| Stage | Typical command |
|---|---|
| E2E_WEB | `npx playwright test -c e2e/finish/playwright.config.ts` |
| E2E_MOBILE | `maestro test {}` |
| API | `npx vitest run` · `uv run pytest -q` · `go test ./{}` (spec = the package directory) |
| SECRETS | `gitleaks git --no-banner` (gitleaks ≥ 8.19) · `gitleaks detect --no-banner` (older) |
| DEPS | `npm audit --audit-level=critical --omit=dev` · `pnpm audit --audit-level critical --prod` · `osv-scanner scan source -r .` (fails on any finding — use only if you can triage) |

## 5. Web specs (`e2e/finish/<ID>.spec.ts`)

- Import `{ test, expect }` from `./finish-fixture`. Never from `@playwright/test` directly.
- One `test()` per acceptance criterion, titled with the criterion text verbatim.
- Real backend, real database. Make data unique per run (`finish+<timestamp>@example.test`). Don't depend on test order.
- Expected values come from the criterion, the docs or a row you query yourself — never copied from the app's own output or from a constant the code under test also uses.
- Prefer `getByRole` / `getByLabel` / `getByText` locators; they double as accessibility checks.
- `snap('<step>')` at each key step; `a11y()` on each P0 screen.
- `allowHttpError({ status, url })` only for a response a criterion expects (duplicate signup → 409). Everything else fails the test.
- To simulate a server error for an unhappy path, use the app's real failure mode where possible (stop the dependency, send invalid data). `page.route()` is allowed only to fail a request (`route.fulfill({ status: 500 })`, declared with `allowHttpError({ status: 500 })`), never to fake a success.
- Assert persistence by reloading or opening a new context, not by reading client state.
- Check the database or Mailpit directly when a criterion is about stored data or sent email.

The config runs every spec at 375×812 (`phone`) and 1440×900 (`desktop`), with `forbidOnly` and no retries.

## 6. Mobile flows (`.maestro/finish/<ID>.yaml`)

- `launchApp: { clearState: true }` at the start; criteria as comments above their steps.
- `takeScreenshot: .finish/evidence/<ID>/phone-<nn>-<step>` at each key step (paths are relative to the directory `maestro test` runs from).
- Persistence: `stopApp` then `launchApp` and assert again.
- Never `optional: true`. Prefer `id:` selectors (`testID` in React Native, `Key` in Flutter, resource-id on Android, accessibilityIdentifier on iOS); add them to the app if missing.
- Release-build gate: build the release variant, install it (`adb install -r <apk>` / `xcrun simctl install booted <app>`), then run the flows.

## 7. API tests

Under the backend's test directory in a `finish/` folder (e.g. `tests/finish/test_j005_invoices.py`), against the running server from `init.sh`, with the real local database. Assert status codes, response bodies and the resulting rows.

## 8. Interactive eyes — `playwright-cli`

```bash
playwright-cli open http://localhost:3000        # add --headed to watch
playwright-cli resize 375 812                    # phone; later: resize 1440 900
playwright-cli snapshot                          # accessibility tree with element refs (e12…)
playwright-cli fill e12 "finish+1@example.test"
playwright-cli click e15
playwright-cli console                           # console messages
playwright-cli requests                          # network log; request <n> for details
playwright-cli screenshot --full-page --filename .finish/evidence/J-001/look-phone-signup.png
playwright-cli reload
playwright-cli network-state-set offline         # unhappy path: offline mid-action
playwright-cli close
```

`playwright-cli --help` lists the rest (tabs, cookies, storage, color scheme). Install its skill once per repo with `playwright-cli install --skills`.

## 9. Lighthouse (Phase 3)

```bash
npx lighthouse http://localhost:3000/ --quiet --chrome-flags="--headless=new" \
  --only-categories=performance,accessibility,best-practices,seo \
  --output=json --output-path=.finish/evidence/_lighthouse/home.json
```

## 10. What `tamper.sh` checks

- Protected tests (any path with a `finish/` segment) contain no skip/only/fixme/xfail/ignore/`optional: true` markers and no assertions that can't fail.
- Every `passing` item's spec exists.
- Every spec in `ratchet.json` (max over its history since the freeze, for items still in the ledger with that spec) exists with at least that many assertions.
- Against the freeze commit: criteria hash unchanged; no test files deleted or renamed out of the test tree; assertion-line counts cannot decrease in any existing test, including renamed tests and protected specs that have never passed; no skip markers or tautologies added to any test; no changes to include/exclude/ignore/retries/only rules or coverage thresholds in test-runner and coverage configs; `verify.sh` unchanged except stages that were empty or `n/a`; `.finish/bin/` unchanged.
- Assertion counts are a lexical floor, not semantic verification: a same-count edit still needs review. Stage test moves so Git records an actual rename and the guard can compare its old/new assertions; a same-basename untracked file does not excuse a deleted protected test. A changed runner config containing an `include` key requires review of the entire file, so multiline array edits cannot evade the guard by leaving the key untouched. This conservative check can also flag unrelated edits in that file; use the reviewed rebaseline procedure below for legitimate changes.
- Floor guard (after Addy Osmani's `constraint-driven-development`): the tree may not hold more lint, type, coverage or scanner suppression comments than it did at the freeze — `@ts-ignore`, `@ts-expect-error`, `eslint-disable`, `biome-ignore`, `istanbul`/`c8`/`v8 ignore`, `# type: ignore`, `# noqa`, `# pragma: no cover`, `# pylint: disable`, `# shellcheck disable`, `//nolint`, `NOSONAR`, `nosemgrep`, `gitleaks:allow`, `Stryker disable`, `swiftlint:disable`, `rubocop:disable`, `@Suppress…(`, Dart `// ignore:`, Rust `#[allow(`. The count is over the whole tree (docs, `.finish/`, `node_modules`, `vendor`, `dist`, `build`, lockfiles excluded), so moving code doesn't trip it. Scanner and linter ignore files (`.gitleaksignore`, `.semgrepignore`, `.eslintignore`, `.trivyignore`, `.snyk`, `audit-ci.json`, `osv-scanner.toml`, `.secrets.baseline`, …) may not grow (a re-include `!…`, or replacing a whole-directory rule with a literal path inside it — `src/**` → `src/generated/**` — is fine; any other replacement counts as growth).

A false positive caused by a legitimate change is handled without a human: commit it, `ledger.sh amend --rebaseline "<why>"`, and the verifier approves or rejects it (`ledger.md` §8).
