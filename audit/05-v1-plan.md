# 05 · v1 Readiness Plan — Houdini  ·  FILLED 2026-07-03 (by the impartial deep audit)

> Built from `02-technical-diagnosis.md` (112 evidence-backed findings, all P0/P1
> adversarially verified), the validated `03` inventory (53 seeds + ~59 additions), the
> `04` verdicts, and the audit-revised `06`/`07` specs. Implementation units live in
> `08-fable5-ultracode-instructions.md`.

## 1. Definition — "v1 = ready, polished, shipped" (finalized)

Houdini v1.0.0 may be tagged when **all** of the following hold:

1. **Nothing the product says is false.** No user-facing claim (site, README, app copy,
   install output) describes a capability, behavior, or guarantee that doesn't exist —
   the audit found seven such falsehoods live today (T4/T5 in `02` §3).
2. **The repo is legally distributable as claimed** — a LICENSE exists (the "free & open
   source" claim is currently false; GitHub reports `license: null`).
3. **The release path is real, singular, and verified** — exactly one publisher (CI *or*
   manual, decided), a release cannot ship without core tests + asserting smoke checks
   passing, and RELEASE.md describes the flow that actually runs. (Today: 4/4 CI runs
   failed, releases are hand-built, two publishers race the same tag.)
4. **The flagship flow works for the worst-ordered user** — install Houdini first, log
   into Claude Code second, and the app connects without a relaunch (today it never does).
5. **The ToS posture is disclosed** — the ADR-012 §6 transparency line ships in the app
   and on the site privacy page (recommended decision; see §3).
6. **Docs describe the system that exists** — no App-Group/WidgetKit fiction, no phantom
   Scheduler/Cache/backoff, ADRs match reality (002/003 revised, 013 added), survey
   sections past-tense, one owner per fact.
7. **Verification is not silently green** — CI runs the 28 core tests somewhere they
   actually execute (they currently run **nowhere**), and at least one app smoke check can
   fail.
8. **A11y holds off the landing page too** — sub-pages pass the same AA bar the landing
   got in 78e2bf3; the menu-bar label doesn't encode severity in color alone; P2 slice 3
   (real-data verification) is done.
9. **Install → update → uninstall is a complete story** — `houdini update` ships per the
   revised `07` (or is explicitly deferred by the owner), and uninstall instructions no
   longer leave the credential behind.

## 2. The P0 gate (blocks the v1 tag — nothing ships around these)

| # | Blocker | Findings | Effort |
|---|---------|----------|--------|
| G1 | Add LICENSE (MIT or Apache-2.0) + README reference | SITE-01 | S |
| G2 | Release-path decision + fix: compile-time guard for `WidgetGlass.glassEffect` (or macOS-26-SDK runner), ONE publisher, pre-publish verification, RELEASE.md amended (incl. Info.plist bump; drop "CI passing" fiction) | INS-01/02, DX-01/02/11, MB-08/09, GAP-03 | M |
| G3 | Site truth pass: /reveals Tokens removed or rescoped; /guide legend → 60/85; cookie copy honesty; /guide API copy future-tense; hero "Nothing leaves your Mac" → precise claim | SITE-02/03/04/05/07, MB-01 | S |
| G4 | Sticky-auth fix: re-resolve credentials on signed-out/error ticks + popover open/Refresh | CORE-01, MB-02, ARC-04 | S |
| G5 | Decision batch (owner sign-off, one sitting — see §3): ADR-013, ADR-002/003 revision, ADR-012 §6 → mandatory, ADR-010 prune revision, Gemini drop, apps/widget delete | ARC-05, SEC-02, INS-03, DOC-04/05, PER-01 | S (decisions) |

## 3. Decisions the owner must ratify (the audit's recommendations)

| Decision | Audit recommendation | Overturns / revises | Evidence |
|---|---|---|---|
| Desktop-widget strategy | **NSPanel is the desktop surface ("Option A hardened"); WidgetKit deferred, bundled with any future Developer-Program decision.** Write **ADR-013**; revise ADR-002/003 in place; **delete `apps/widget/`** (or make its README say "no target exists"). | ADR-002/003 framing; audit/06's original Option-C recommendation | WidgetKit is triple-hard-blocked under ad-hoc distribution (DTS 776087; sandboxed-.appex gallery rule; SPM can't build .appex — CodexBar #1095). 06 §R1–R3. |
| ToS transparency | **Make the ADR-012 §6 line mandatory for v1** (app Settings next to auth status + site privacy page). Keep the read-only freeze itself (the refresh-rotation hazard — unfreezing could strand the user's own CLI login — is the decisive reason; record it in ADR-012's Why). | ADR-012 §6 ("optional, deferred") | SEC-02/07/08; GAP-02 reconciliation in `03` |
| Release pruning | **Revise ADR-010:** keep superseded releases (retitle "superseded — do not install") and tags; prune only the *pointers*; enable GitHub **Immutable Releases**. | ADR-010 §3 prune rule; ADR-006's "never points at a dead artifact" | INS-03 (v0.3.0 one-liner already 404s; rollback impossible; `update <old>` a null set) |
| Release publisher | **Fix release.yml and make CI the sole publisher** (better provenance for a security-marketed installer); manual flow becomes verify-only. Acceptable alternative: retire the workflow and document manual as canonical — but pick one. | CLAUDE.md's "release CI" description (currently fiction) | INS-01/02, DX-01/02/11 |
| Gemini claim | **Drop** from README/CONTEXT/CLAUDE/feature_list until a PROVIDERS.md spec + ROADMAP phase exists. | README/CONTEXT provider claims | DOC-04 |
| Hero H1 posture | Make it coherent either way: the "Live for Claude Pro · Max" badge already defeats the low-profile rationale — recommend sharpening the H1 (no incremental ToS exposure); keeping generic is acceptable *only* if the badge/copy are toned down to match. | BACKLOG P3 "KEEP GENERIC" application (not ADR-012 itself) | SITE-10 |
| `houdini update` in v1? | **Yes** — per revised `07` (option (a) + five conditions). It is the last piece of the install→update→uninstall story and is now fully de-risked on paper. If the owner prefers to defer it, v1 must instead say so explicitly (README: "update = re-run the installer"). | — | 07 §R3 |

## 4. Phases (dependency-ordered)

**Phase A — Truth & release integrity (the P0 gate).** G1–G5 above. A5 (decision batch)
first or in parallel — G2's shape and Phase E's semantics depend on the ADR-010/publisher
decisions. *Gates v1: yes, all of it.*

**Phase B — Core reliability + security polish.** (P1; starts once A is merged)
B1 backoff-or-honest-copy + cache `claude --version` per process (ARC-02/CORE-03/CORE-06/MB-06).
B2 ephemeral URLSession + redirect-guard scheme check + guard unit tests (SEC-01/CORE-07 — security-adjacent → Opus routing).
B3 staleness cue on the menu-bar label; light-mode AA measurement/fix; expired-OAuth copy says "run `claude` to refresh" for CLI users (MB-03/MB-04/CORE-02/CORE-05).
B4 transparency line implementation (from A5): Settings + site privacy page (SEC-02).
B5 CLI primitives: `--help`, `--version` (tag-injected in the shared build path), usage-on-unknown-flag; Settings About/version row (CORE-08, critic, MB-09 tie-in).
*Gates v1: yes (all S/M efforts).*

**Phase C — Verification baseline.** (P1; parallel with B)
C1 `ci.yml` on push/PR: `swift test` on a full-Xcode runner (fixes the silent-green loop), `houdini-selftest`, site build, menubar build (needs A/G2's SDK fix), `--metrictest` converted to asserting; optional FetcherCore-for-iOS simulator compile job (DX-03/04/07, PER-05).
C2 core tests for the risky paths: HTTP status→error mapping both providers, 401→refresh→retry, cookie two-request flow, `sameSite` adversarial cases (CORE-09/DX-05).
*Gates v1: C1 yes; C2 yes (it covers the security-relevant guard).*

**Phase D — Docs & process hygiene.** (P1; after A5 decisions, parallel with B/C)
D1 ARCHITECTURE/PROVIDERS truth pass: App-Group fiction → "planned, not built"; phantom Scheduler/Cache/backoff removed; Keychain item names corrected; `claude-cookie` id documented; endpoint table added (ARC-01/02/06, DOC-01/02/06/07).
D2 ADR edits from A5: revise 002/003, write 013, amend 010 + 012, note the AfterFirstUnlock choice (DOC-05, SEC-08/09).
D3 Operating-doc pass: CLAUDE/CONTEXT survey sections → past tense; BACKLOG self-contradictions + ROADMAP markers; WORKFLOW.md merged into CLAUDE.md; feature_list.json deleted (or generator+consumer built); README repo map + NC-widget phrasing; scripts/README + init.sh fixes (DOC-03/08..12, ORG-01/05..08, INS-07/08, DX-10).
D4 Org hygiene: commit the P4 BACKLOG section; track audit/; `.claude/` in repo .gitignore; delete apps/widget (per ADR-013); apps/ios honesty pass (reword "verified", fix project.yml dependency, clamp the Gauge) (ORG-02/03/11, PER-01/04/06/08).
D5 Uninstall completeness (installer printout note is gated — put the full steps on site/README instead) + SECURITY.md + private vulnerability reporting (GAP-01/04).
*Gates v1: yes (this is criterion 6).*

**Phase E — `houdini update`.** (P1 feature; depends on B5 + A/G2 + A5's ADR-010 call)
E1 version resolver + `houdini update --check` (read-only, dogfoodable).
E2 the mutation per revised `07` R3: fetch per-tag installer → TAG-match guard → CLI rename-aside → app pre-stash → tty-detached spawn → post-install verification → report (incl. the `open` side-effect message).
E3 owned-file cleanup manifest + edge-case matrix + docs (README mention, RELEASE.md smoke step).
*Gates v1: yes per §3's recommendation (owner may explicitly defer).*

**Phase F — Surface polish end-to-end.** (P1/P2 mix; final stretch)
F1 **P2 slice 3** — verify gauges/reset timers/overage against real Claude Pro/Max data (PND-MB-01).
F2 Sub-page a11y pass; Settings Dynamic Type; live-AT check of the desktop-widget keyboard path (SITE-06, MB-07/12).
F3 Site niceties: /surfaces mock caption, dead assets removed, branded 404, robots/sitemap (SITE-08/09).
F4 README hero screenshot; regenerate/delete stale docs/review corpus (GAP-05/06). *(F4 may slip past v1 without gating.)*
*Gates v1: F1/F2 yes; F3 yes (S); F4 no.*

**Phase G — Final QA + tag v1.0.0.** (gated actions throughout)
G-1 full verification matrix: fresh-machine install → connect (both auth paths) → update → uninstall; live site visual+a11y re-audit (all 7 pages this time); CI green; `houdini update --check` post-release smoke.
G-2 release v1.0.0 via the Phase-A path (🔴 gated: tag/publish/site deploy), prune *pointers* per revised ADR-010.
*Gates v1: definitionally.*

## 5. Dependency graph (the load-bearing edges)

- **A5 (decisions) → G2 shape, D2, E semantics, apps/widget deletion.**
- **G2 (release path) → C1's menubar job (SDK), E2 (update rides the fixed path), G-2.**
- **B5 (version primitives) → E1/E2 ("Updated vX → vY" needs `--version` + plist read).**
- OPP-01's *rescoped* threshold fix lives in G3 (site truth), **not** in a HoudiniUI
  extraction — the extraction (OPP-02) is explicitly deferred with WidgetKit.
- F1 (real-data verification) last among app changes, so it validates B's fixes too.

## 6. Deferred past v1 (explicit, with re-entry triggers)

| Item | Why deferred | Re-entry trigger |
|---|---|---|
| WidgetKit widget (NC or desktop) + HoudiniUI extraction | Triple hard blocker under ad-hoc distribution (06 §R2) | Apple Developer Program adopted (iOS ship or notarized DMG — one bundled decision) |
| iOS app build/TestFlight/App Store | Needs Xcode + $99 + review track (ADR-008) | Same bundle as above |
| OpenAI Platform / Anthropic Console / ChatGPT-Plus adapters; provider switcher UI | Design-only today; v1 is Claude-first (ADR-004) | Post-v1 roadmap phase |
| Gemini adapter | Claim dropped in v1 (DOC-04) | A real PROVIDERS.md spec |
| CredentialStore native-Keychain migration | Correctly gated on a signed app in the item's ACL (CORE-04) | Developer-ID signing |
| Supply-chain ladder: embedded checksums in install.sh, provenance attestations, Sparkle-style key | install.sh edits are gated; ladder documented in 04 · OPP-30 | Owner appetite post-v1 (Immutable Releases lands in v1 via A5) |
| Menu-bar "Check for updates" surface; passive update nudge | CLI-first decided (07 §R4 Q1/Q3) | Post-v1 |
| Cookie-path orgId caching; refreshInterval/capabilities cleanup | P2 efficiency/hygiene (OPP-28) | Post-v1 core pass |
| Full site token/theme unification with the app | No third consumer yet (OPP-01 full scope) | WidgetKit re-entry |

## 7. Handoff

Every gated phase above is decomposed into concrete, ordered, evidence-verified units in
**`08-fable5-ultracode-instructions.md`** (per-unit template: Goal · Scope · Guardrails ·
Acceptance · Verify · Commit). Model routing per CLAUDE.md: **Opus** for the
security-adjacent units (B2, B4-app-side, anything touching `ClaudeAuth*`/`CredentialStore`
paths, E2's installer-adjacent logic review); **Fable 5** for the rest.
