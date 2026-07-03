# audit/ — Houdini v1 Audit initiative

**Goal:** get Houdini to a complete, polished, shipped **v1** via a **100% impartial deep
audit**, then implement the result.

## Workflow (3 steps)

1. **Prep (this folder) — DONE.** Charter + neutral scaffolds + consolidated pendências +
   forward specs (widget, update) + the audit-run prompt.
2. **Audit — DONE 2026-07-03** (fresh empty-context Fable 5 ultracode task; 43 agents, all
   P0/P1 findings adversarially verified). `02` filled (112 findings), `03`
   validated+extended (48 confirmed / 5 corrected / 0 refuted / ~59 added), `04`
   prioritized, `05` = the real v1 plan, `06`/`07` audit-revised (06's Option-C
   recommendation **overturned** → "Option A hardened" + ADR-013; 07 endorsed with 5
   mandatory conditions), `08` emitted.
3. **Implementation — NEXT: Claude Code Fable 5 Ultracode.** First ratify the decision
   batch (`05` §3 / unit A0), then execute the ordered units in
   [`08-fable5-ultracode-instructions.md`](08-fable5-ultracode-instructions.md).

## Files

| File | What it is | State |
|------|-----------|-------|
| `00-README.md` | This index + workflow | Updated 2026-07-03 |
| `01-charter-and-method.md` | Impartial charter, scope, scoring schema, "challenge everything" mandate | Fixed |
| `02-technical-diagnosis.md` | Diagnosis across all dimensions — 112 evidence-backed findings, lead verdicts, consolidation | **FILLED (2026-07-03)** |
| `03-pendencias-todos.md` | Consolidated pendências (53 seeds validated: 48 confirmed / 5 corrected / 0 refuted) + ~59 additions | **VALIDATED + EXTENDED (2026-07-03)** |
| `04-improvement-opportunities.md` | 11 seeds + 19 new opportunities, all with Priority + Verdict | **PRIORITIZED (2026-07-03)** |
| `05-v1-plan.md` | The real v1 plan: definition, P0 gate, decision batch, phases A–G, deferrals | **FILLED (2026-07-03)** |
| `06-widget-macos-spec.md` | macOS widget spec — **audit-revised**: Option C overturned → "Option A hardened" (WidgetKit hard-blocked); §12 answered | **AUDIT-REVISED (2026-07-03)** |
| `07-update-feature-plan.md` | `houdini update` plan — **audit-revised**: option (a) endorsed with 5 mandatory conditions; §10 answered | **AUDIT-REVISED (2026-07-03)** |
| `08-fable5-ultracode-instructions.md` | Ordered build units A0–G2 with per-unit acceptance + evidence requirements | **FILLED (2026-07-03)** |
| `09-audit-run-prompt.md` | Self-contained prompt for the empty-context Fable 5 audit | Executed 2026-07-03 |

## Rules

- **Prep + audit = no code changes** (docs/planning only).
- The audit is **impartial**: nothing prior is assumed correct — ADR-012, the Build
  Conductor process, the widget/distribution choices, priorities — all fair game.
