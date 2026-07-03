# 09 · Audit-run prompt — paste into the empty-context Fable 5 task

> Start a FRESH Claude Code task with **empty context**, model **Fable 5** (ultracode ok),
> at the Houdini repo root, and paste the fenced block below. It runs the impartial v1 audit
> and fills the `audit/` docs. No code changes.

```
You are Claude Code (Fable 5), starting a FRESH task with NO prior context, in the Houdini monorepo (repo root = current directory). Mission: run a 100% IMPARTIAL, DEEP AUDIT of the entire project to prepare a complete, polished v1, and produce the plan + implementation instructions to get there. This is an AUDIT + PLANNING task — do NOT change any code. You read, research, consolidate, and write ONLY into the audit/ folder.

WHAT HOUDINI IS (verify against the repo; do not take it as gospel): a local-first macOS app (menu bar + desktop widget) that reveals a user's Claude (Pro/Max) usage + spend. Swift/SwiftUI app in apps/menubar + shared core/ (FetcherCore) + a WidgetKit placeholder apps/widget + an iOS scaffold apps/ios + an Astro/Tailwind site in site/. Installed via install.sh.

IMPARTIALITY MANDATE (non-negotiable):
- Assume NOTHING is correct. Every prior decision is open to challenge — ADR-012 (Claude read-only / frozen subscription-auth), the Build Conductor process and its CLAUDE/CONTEXT/BACKLOG docs, ADR-006 (ad-hoc install.sh distribution), ADR-002/010/011 (widget & branding), the NSPanel-vs-WidgetKit widget choice, the monorepo layout, the priority ordering, the provider strategy. Prior decisions are context to INTERROGATE, not truth to preserve. If one is wrong, say so with evidence + a recommended change (name the ADR it revises).
- Separate observation (what is) from judgment (what should change); give trade-offs. Evidence, not reasoning — prove findings with pasted output (file:line, grep, build/test). Mark anything unchecked "unverified."

START HERE — read, in order:
1. audit/01-charter-and-method.md — your charter, scope, and the Priority/Impact/Risk/Effort schema. Follow it.
2. audit/03-pendencias-todos.md — a neutral, sourced inventory (~53 items) as your starting map; validate + extend it, don't trust it blindly.
3. audit/06-widget-macos-spec.md and audit/07-update-feature-plan.md — forward specs for the two big v1 features; refine them if your audit changes their assumptions.
4. Then read the WHOLE repo: README, ARCHITECTURE, DECISIONS (all ADRs), PROVIDERS, ROADMAP, CONTEXT, BACKLOG, CLAUDE, feature_list.json, install.sh, scripts/, .github/workflows/, core/, apps/*, site/, conductor/audits/.

DO THE AUDIT — fill these audit/ docs, objectively:
- 02-technical-diagnosis.md — complete every dimension (architecture, code, organization, flows, UX, DX, scripts/installer/release, docs accuracy, stability, security/ToS) with evidence-backed findings scored by the schema. Verify the "leads" listed there (e.g. ARCHITECTURE.md claims the menu bar writes an App-Group snapshot + calls WidgetCenter.reloadAllTimelines() but the code may not; CredentialStore shells /usr/bin/security every ~60s poll; RELEASE.md is referenced by ADRs but may not exist; keychain item named "Claude Code" vs "Claude Code-credentials"; ROADMAP/feature_list drift) — confirm or refute each with evidence.
- 03-pendencias-todos.md — validate, correct, and extend; remove anything false, add anything missing.
- 04-improvement-opportunities.md — confirm/expand the candidates; fill Priority + Verdict.
- 05-v1-plan.md — produce the REAL phased v1 plan: define "v1 ready", set the gating (what MUST be fixed before tagging v1), sequence the phases + dependencies, mark what's deferred past v1. Two phases are large and already specced: the macOS widget (06) and houdini update (07) — slot them in.
- 08-fable5-ultracode-instructions.md — emit the concrete, ordered implementation UNITS for the build phase (per the template there), derived from 05.

RESEARCH where needed (web): current Apple/macOS widget design + WidgetKit refresh budgets (06 has a starting set — extend/verify); safe CLI self-update patterns (07 has a starting set). Cite sources.

CONSTRAINTS:
- No code changes. Docs/planning only, all under audit/. If you find a factual error in BACKLOG/CONTEXT/CLAUDE/ARCHITECTURE, record it as a finding — do NOT edit those files (owner sign-off first).
- Respect gated actions (install.sh / SHASUMS256.txt / releases) — never touch them.
- Leave conductor/ untouched.

DELIVER: the filled audit/ docs above, PLUS a concise top-level FINDINGS SUMMARY in your reply — the P0 blockers for v1, the biggest risks, the recommended phase order, and any prior decision you recommend overturning (with evidence). End by telling the owner exactly which audit/ docs you updated and the recommended next step.
```
