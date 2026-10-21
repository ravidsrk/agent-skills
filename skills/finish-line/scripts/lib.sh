#!/usr/bin/env bash
# Shared helpers for the finish-line scripts. Sourced, never executed.
# Bash 3.2 compatible (macOS default shell): no associative arrays, no mapfile.
# shellcheck disable=SC2034  # variables are used by the scripts that source this file

FL_STATUSES="failing passing stuck needs_owner"
FL_TYPES="journey feature gate"
FL_METHODS="e2e-web e2e-mobile api command"

# A test-looking path: test dirs, *.test.ts / *.spec.ts, *_test.py, test_*.py, *Test.kt, Maestro flows.
FL_TEST_PATH_RE='(^|/)(e2e|tests?|__tests__|specs?|\.maestro|integration_test|androidTest|[Uu][Ii][Tt]ests?|Tests)/|\.(test|spec)\.[cm]?[jt]sx?$|_test\.(py|go|dart)$|(^|/)test_[^/]*\.py$|Tests?\.(kt|java|swift)$'

# Protected Finish Line test paths: any path with a `finish/` directory segment (not `.finish/`).
FL_PROTECTED_RE='(^|/)finish/'

# Markers that disable, focus or weaken tests.
FL_SKIP_RE='\.(skip|only|fixme)\(|(^|[^A-Za-z0-9_.])(xit|xdescribe|xtest|fit|fdescribe)\(|test\.todo\(|@pytest\.mark\.(skip|skipif|xfail)|pytest\.(skip|xfail)\(|unittest\.skip|expectedFailure|@(Ignore|Disabled)([^A-Za-z]|$)|XCTSkip|t\.Skip(f|Now)?\(|skip: *(true|'"'"'|")|optional: *true'

# Assertions that can never fail.
FL_TAUTOLOGY_RE='expect\( *(true|false|1|0|null|undefined) *\)|expect\( *'"'"'[^'"'"']*'"'"' *\)|expect\( *"[^"]*" *\)|assert +(True|1) *($|#|;)|assert +not +False|assertTrue\( *true *\)|XCTAssertTrue\( *true *\)|assertEquals\( *true *, *true *\)'

# Comments that silence a lint, type, coverage or scanner check (the "floor guard"). New ones
# after the freeze lower the bar the gate was frozen at.
FL_SUPPRESS_RE='@ts-(ignore|nocheck|expect-error)|eslint-disable|biome-ignore|istanbul ignore|(c8|v8) ignore|# *type: *ignore|# *noqa|# *pragma: *no cover|# *pylint: *disable|# *shellcheck +disable|//nolint|NOSONAR|nosemgrep|gitleaks:allow|Stryker disable|swiftlint:disable|rubocop:disable|@Suppress(Warnings|Lint)?\(|// *ignore(_for_file)?:|#\[allow\('

# Files whose only job is to exempt things from a scanner or linter.
FL_GATE_IGNORE_RE='(^|/)(\.gitleaksignore|\.gitleaks\.toml|\.semgrepignore|\.eslintignore|\.trivyignore|\.snyk|\.nsprc|audit-ci\.jsonc?|osv-scanner\.toml|\.secrets\.baseline|\.bandit)$'

# Lines that count as an assertion (JS/TS, Python, JVM, Swift, Go, Dart, Maestro).
FL_ASSERT_RE='expect\(|(^|[^A-Za-z_])assert|XCTAssert|assertThat\(|assertVisible|assertNotVisible|assertTrue:|t\.(Error|Fatal)f?\(|require\.[A-Z]'

fl_die() { echo "finish-line: $*" >&2; exit 2; }

fl_need() {
  local c
  for c in "$@"; do command -v "$c" >/dev/null 2>&1 || fl_die "missing required tool: $c"; done
}

fl_root() { git rev-parse --show-toplevel 2>/dev/null || fl_die "not inside a git repository"; }

fl_sha() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum | cut -d' ' -f1
  else shasum -a 256 | cut -d' ' -f1; fi
}

fl_mtime() { stat -c %Y "$1" 2>/dev/null || stat -f %m "$1"; }

fl_now() { date -u +%Y-%m-%dT%H:%M:%SZ; }

# Hash of everything in the ledger except the four mutable item fields.
fl_criteria_hash() {
  jq -cS '{product, one_liner, items: [.items[] | del(.status, .attempts, .evidence, .notes)]}' "$1" | fl_sha
}

# SCOPE file → number (P0 → 0). Defaults to 0.
fl_scope_n() {
  local s
  s="$(tr -d '[:space:]' 2>/dev/null < "$1/SCOPE")"
  case "$s" in P1) echo 1 ;; P2) echo 2 ;; *) echo 0 ;; esac
}

fl_is_test_path() { printf '%s\n' "$1" | grep -Eq "$FL_TEST_PATH_RE"; }
fl_is_protected_path() { printf '%s\n' "$1" | grep -Eq "$FL_PROTECTED_RE"; }

fl_assert_count() { grep -Ec "$FL_ASSERT_RE" "$1" 2>/dev/null || true; }

# Fingerprint of the code under test: HEAD + uncommitted and untracked changes outside .finish/.
# Run from the repo root. Gitignored files (node_modules, evidence, tool caches) don't count.
fl_code_state() {
  {
    git rev-parse HEAD 2>/dev/null
    git diff HEAD --no-color --no-ext-diff -- . ':(exclude).finish' 2>/dev/null
    git ls-files --others --exclude-standard -- . ':(exclude).finish' 2>/dev/null | while IFS= read -r f; do
      printf '%s %s\n' "$(git hash-object -- "$f" 2>/dev/null)" "$f"
    done
  } | fl_sha
}
