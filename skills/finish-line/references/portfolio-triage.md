# Portfolio triage — pick exactly one product to finish

Use when there are several half-built products and none has shipped. Starting all of them again is the failure mode; the output of triage is **one** `FINISH-NEXT`.

## 1. Free snapshot (seconds, no model calls)

```bash
"$FINISH_SKILL_DIR/scripts/portfolio.sh" ~/code
```

One row per git repo directly under the folder: last commit, commit count, doc count, stub-marker count, and Finish Line status if a run already exists.

## 2. Triage session (one agent session, read-only)

Run from the folder holding the repos. Paste as the prompt:

```
Audit every git repo in this folder as a portfolio. Do not commit, push, or edit source in any repo. For each repo:
1. Read its docs (PRD, specs, README) and write its promise in one sentence.
2. Try to install and boot it; stop trying after 15 minutes. Record: boots yes/no, and why not.
3. Walk the core user journey (playwright-cli for web, maestro for mobile, curl for API). Classify each step WORKS / PARTIAL / FAKE / BROKEN / MISSING, with a screenshot saved under ./finish-portfolio/<repo>/.
4. Count fake/stub markers: TODO, FIXME, placeholder, lorem, mock data, not implemented, coming soon.
5. Estimate how many P0 launch items remain (sign up → core promise → return later and find data, plus launch gates).
Write ./finish-portfolio/README.md: one table sorted by boots=yes first, then fewest P0 items remaining. Columns: repo, promise, boots, core-journey status, P0 remaining, biggest risk, verdict.
Verdicts: exactly one FINISH-NEXT; the rest LATER or ARCHIVE. Don't ask me questions.
```

## 3. Choosing — the rules the triage applies

- **Boots beats ambitious.** A product that runs today with 8 P0 items left beats one that doesn't boot with 5.
- **Fewest P0 items remaining** breaks ties.
- **Real demand** breaks the next tie: a user, a waitlist, a customer asking.
- **ARCHIVE** when the core promise is now a commodity, the stack is dead, or nothing boots and the docs are thin. Archiving is a decision, not a failure; it frees attention.

## 4. After triage

```bash
"$FINISH_SKILL_DIR/scripts/finish.sh" ~/code/<FINISH-NEXT repo>
```

Don't start a second product until the first is `LAUNCH_READY` or every remaining item is `blocked_human` on something only you can do.
