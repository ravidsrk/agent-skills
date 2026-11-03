# .integrator/config.sh: the project's own commands for parallel-build-integrator's scripts.
# Copy into the project, fill in the real commands, and commit it (no secrets here, ever).
# Every command runs from the worktree root with `bash -c`.

# Scratch space outside the repo: integration worktrees, logs, the keys file.
SCRATCH="${SCRATCH:-$HOME/.integrator-scratch}"

# 1. Regenerate everything generated (env types, codegen, bundles, API exports). Empty to skip.
REGEN_CMD="pnpm install --frozen-lockfile --prefer-offline && pnpm env:generate"

# 2. Lint and format. The whole log is kept; read it all.
LINT_CMD="pnpm exec biome check ."

# 3. Typecheck.
TYPECHECK_CMD="pnpm typecheck"

# 4. Drift checks: each must exit 0 and leave `git status` clean.
DRIFT_CMDS=(
  "pnpm --filter @acme/api openapi:export"
  "pnpm --filter @acme/db exec prisma migrate diff --from-migrations prisma/migrations --to-schema prisma/schema --exit-code"
  "node scripts/pins.mjs"
)

# 5. A fresh database for the full suite. Empty if the suite needs none.
FRESH_DB_CMD="bash scripts/fresh-test-db.sh acme_integ"
# Env file the full suite reads (points at the fresh DB). Empty for none.
TEST_ENV_FILE="$SCRATCH/integ.env"

# 6. The full suite, and one file alone (for classifying failures; `{}` is the file).
TEST_CMD="pnpm exec vitest run"
TEST_ONE_CMD="pnpm exec vitest run {}"

# Conflict classes for merge_loop.sh (space-separated globs, matched against repo paths).
UNION_GLOBS="docs/adr/README.md packages/core/CONTRACTS.md"
ROW_GLOBS="docs/plan/status.md"

# Attribution: integrated commits are re-authored as the repo's `git config user.name/email` (the human owner)
# and stripped of agent trailers. Set REAUTHOR=0 only if the project wants agent authorship kept.
REAUTHOR=1
# STRIP_TRAILERS_RE='^(Co-[Aa]uthored-[Bb]y:.*Claude|Claude-Session:|.*Generated with \[)'

# Secret scan: extra allowed matches (an ERE matched against the whole added line).
KEYSCAN_ALLOW='placeholder: .(sk-ant-|AIza)\.\.\.|xoxb-test-token|sk-ant-fake-'

# --- Other stacks -------------------------------------------------------------------------------
# Python: LINT_CMD="ruff check . && ruff format --check ."  TYPECHECK_CMD="mypy ."  TEST_CMD="pytest -q"
#         TEST_ONE_CMD="pytest -q {}"
# Go:     LINT_CMD="golangci-lint run"  TYPECHECK_CMD="go vet ./..."  TEST_CMD="go test ./..."
#         TEST_ONE_CMD="go test {}"
