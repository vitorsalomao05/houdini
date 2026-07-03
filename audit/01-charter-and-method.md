# 01 · Audit Charter & Method — Houdini v1 Audit

**Purpose.** Get Houdini to a **v1 that is complete, polished, and shipped**, via a
**100% impartial, deep audit** run as a fresh **empty-context task (Fable 5)**. This
`audit/` folder holds the inputs, neutral scaffolds, and handoff prompts for that audit and
for the implementation phase that follows.

## Impartiality mandate (read first)

- **Assume nothing is correct.** Every prior decision is open to challenge — including
  **ADR-012** (Claude read-only / frozen subscription-auth), the whole **Build Conductor**
  process and its `CLAUDE.md`/`CONTEXT.md`/`BACKLOG.md` docs, **ADR-006** (ad-hoc
  `install.sh` distribution), **ADR-002/010/011** (widget & branding), the
  **NSPanel-vs-WidgetKit** desktop-widget choice, the **monorepo** layout, the site's
  **generic-H1** decision, the **priority ordering**, and the **no-server / provider**
  strategy.
- Prior decisions are provided as **context to interrogate, not truth to preserve.** If a
  decision is wrong, say so with evidence and a recommended change (naming the ADR it revises).
- Separate **observation** (what is) from **judgment** (what should change). Give
  trade-offs, not verdicts-by-assertion.
- **Evidence, not reasoning.** Prove findings with pasted output (`file:line`, diffs, greps,
  build/test runs). If it wasn't checked, mark it **unverified**.

## Scope

Architecture · code quality · repo organization · flows (auth, fetch/poll, install, update,
release) · UX (menu bar, desktop widget, site) · DX (build/test/scripts/CI) · documentation
accuracy · stability/reliability · security/privacy/ToS · distribution.

## Prioritization schema (apply to every finding)

- **Priority:** `P0` blocks v1 · `P1` needed for a polished v1 · `P2` post-v1 · `P3` backlog.
- **Impact:** High / Med / Low.  **Risk:** High / Med / Low.  **Effort:** S / M / L.
- Finding row: `ID · Area · Observation · Evidence · Priority · Impact · Risk · Effort · Recommendation`.

## What the audit task produces (fills these scaffolds)

- `02-technical-diagnosis.md` — complete the evidence-backed findings.
- `03-pendencias-todos.md` — validate + extend the consolidated inventory (already seeded).
- `04-improvement-opportunities.md` — confirm/expand, prioritized.
- `05-v1-plan.md` — the phased v1 plan with explicit gating.
- Revise `06-widget-macos-spec.md` / `07-update-feature-plan.md` if the audit changes their
  assumptions.
- `08-fable5-ultracode-instructions.md` — the implementation instructions for the build phase.

## Non-goals

**No code changes** during prep or audit. Organize, audit, research, consolidate, plan.
Implementation happens later via **Claude Code Fable 5 Ultracode** (see `08` and `09`).

## Method (for the audit task)

1. Read the whole repo + this `audit/` folder before concluding anything.
2. Work dimension by dimension (see `02`), evidence-first.
3. Score every finding with the schema above; keep observation and recommendation distinct.
4. Roll findings up into `04` (opportunities) and `05` (v1 plan with gating).
5. Emit `08` implementation instructions the Fable 5 Ultracode build phase can execute.
