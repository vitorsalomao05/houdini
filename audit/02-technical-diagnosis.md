# 02 · Technical Diagnosis — Houdini v1 Audit  ·  COMPLETED 2026-07-03

> **Status: FILLED.** Produced by the impartial deep audit (Fable 5 ultracode, 2026-07-03):
> **43 agents** — 10 dimension auditors covering A–J, 2 spec verifiers (audit/06, audit/07),
> 2 web researchers, **adversarial verification of every P0/P1 finding** (independent refuters
> re-derived each claim from the repo; P0s got two refuters), and a completeness critic.
> 809 tool calls; local evidence (grep/read/build/test) plus live GitHub (`gh run list`,
> `gh release view`, raw-URL probes) and the live production site.
>
> Scoring per `01-charter-and-method.md`: Priority **P0** blocks v1 · **P1** needed for a
> polished v1 · **P2** post-v1 · **P3** backlog; Impact/Risk High/Med/Low; Effort S/M/L.
> Verification column: `CONFIRMED` = an adversarial verifier independently re-derived the
> evidence; `CORRECTED` = real but re-scored/re-stated (correction noted); findings without a
> verifier carry their auditor's pasted evidence only.

## 0. Verdicts on the seeded leads

| Lead (from the scaffold) | Verdict | Evidence |
|---|---|---|
| ARCHITECTURE.md claims App-Group write + `WidgetCenter.reloadAllTimelines()` but code has neither | **CONFIRMED** (2 independent agents + verifier) | `grep -rn 'WidgetCenter\|reloadAllTimelines' apps/menubar/Sources` → 0 hits; `suiteName` only in WidgetTest/SelfTest/Snapshotter test harnesses; ARCHITECTURE.md:32, :50, :65-68 assert it. → ARC-01/DOC-02 |
| `CredentialStore` shells `/usr/bin/security` every ~60s poll | **CONFIRMED, severity downgraded** | CredentialStore.swift:55-57 → cliReadGenericPassword. But argv carries only the service name (secret returns via stdout pipe — no `ps` leak), and the *dominant* per-poll cost is actually `ClaudeOAuthProvider` spawning `/usr/bin/env claude --version` every fetch (uncached computed property). → CORE-03/CORE-04/SEC-05/SEC-06 |
| `RELEASE.md` is referenced by ADRs but may not exist | **REFUTED** | RELEASE.md exists at repo root (116 lines, tracked since 2026-06-18, commits 710bef3→c80483a) with the full bump/publish/prune checklist. audit/07 §1.5 ("searched; absent") is itself wrong and is corrected in this pass. |
| Keychain item named "Claude Code" vs "Claude Code-credentials" | **CONFIRMED** (drift is real, code is right) | Code reads ordered `["Claude Code-credentials", "Claude Code"]` + `~/.claude/.credentials.json` fallback (ClaudeOAuthCredentialSource.swift:38); PROVIDERS.md:43 and ARCHITECTURE.md:41 still name only "Claude Code". → DOC-06 |
| ROADMAP/feature_list drift | **CONFIRMED and worse than seeded** | ROADMAP Phase 2 unmarked though shipped, still lists the never-built App-Group bullet; feature_list.json has **zero consumers and no generator** (`grep -rn feature_list scripts/ site/ core/ apps/` → 0 hits) and was never regenerated. → DOC-08/DOC-09/ORG-05/ORG-06 |
| 2026-07-01 site audit was landing-page-only, a11y simulated | **CONFIRMED** | Sub-pages audited from source this pass: they retain the failure classes the landing fix (78e2bf3) addressed, plus factual errors the earlier audit never looked at (SITE-02/03/04/06/07). |

**Beyond the leads — the four biggest net-new discoveries of this audit:**

1. **The release CI story is fiction.** All 4 runs of `release.yml` ever (v0.2.0 ×2, v0.3.0, v0.4.0) **failed** — `WidgetGlass.swift:149` (`Color.clear.glassEffect(in:)`, needs the macOS 26 SDK) cannot compile on the workflow's pinned Xcode 16 runner. Every shipped release was hand-built on the dev machine and published manually; the published SHASUMS256.txt is byte-identical to the local `build/release-v0.4.0/` staging dir. Two publishers race on the same tag. `swift test` on the dev machine **exits 0 while executing zero tests** (swift-testing no-ops on CommandLineTools). → INS-01/INS-02/DX-01/DX-02/DX-03/DX-11/MB-08
2. **No LICENSE file exists** (GitHub API: `license: null`) while "free & open source" is claimed on /, /install, /faq, /privacy, README and is a CLAUDE.md guardrail. The claim is legally false today (all-rights-reserved by default). → SITE-01
3. **WidgetKit under the current distribution is a confirmed hard blocker, not a cost.** Apple DTS (forums 776087): ad-hoc-signed apps cannot get App-Group container access on macOS 15+ (Team-ID-based); Mac widget .appex must be sandboxed to appear in the gallery (685166/718589); SwiftPM cannot produce a working .appex on macOS 26 at all (CodexBar #1095 — same product category, public post-mortem). And audit/06's stated reason to revisit ("Tahoe made desktop widgets first-class") is factually wrong — desktop WidgetKit shipped in macOS 14 Sonoma (2023). → §3 of the revised audit/06
4. **The site teaches falsehoods about the shipped product:** /guide's threshold legend (75/90) contradicts the app (60/85); /reveals advertises a "Tokens" capability that has no code anywhere; /faq//install//guide promise "sign in once … no repeated logins" for a cookie that is short-lived and non-refreshable **by ADR-012 decision**. → SITE-02/03/04, MB-01


## 1. Findings index (all 112, most severe first within dimension)

| ID | Dimension | Priority | Impact | Risk | Effort | Area | Verification |
|---|---|---|---|---|---|---|---|
| ARC-01 | architecture | P1 | High | Low | S | ARCHITECTURE.md vs apps/menubar — App-Group/WidgetKit bridge | CONFIRMED |
| ARC-02 | architecture | P1 | Med | Low | S | core/FetcherCore — phantom Scheduler/Cache components; no backoff anywhere | CONFIRMED |
| ARC-03 | architecture | P2 | Med | Low | M | Provider-adapter abstraction (ADR-007) — real at the core, ceremonial at the edges | — |
| ARC-04 | architecture | P2 | Med | Med | S | apps/menubar auth data flow — out-of-band credential changes never detected | — |
| ARC-05 | architecture | P2 | Med | Low | S | Desktop widget: NSPanel vs WidgetKit — merits judgment + missing ADR | — |
| ARC-06 | architecture | P3 | Low | Low | S | 'No server, direct-to-provider' claim — full endpoint enumeration (VERIFIED) | — |
| ARC-07 | architecture | P3 | Low | Low | S | core/FetcherCore/ClaudeCookieProvider — org lookup repeated every poll | — |
| ARC-08 | architecture | P3 | Low | Low | S | README.md — Notification Center widget phrasing overstates apps/widget | — |
| ARC-09 | architecture | P3 | Low | Low | M | Future WidgetKit coupling — snapshot bridge stranded in the uncompiled iOS scaffold | — |
| CORE-01 | core-code | P1 | High | High | S | auth/reliability — runtime auth resolution | CORRECTED |
| CORE-02 | core-code | P1 | High | Med | M | auth — frozen OAuth refresh (leads 2) | CORRECTED |
| CORE-03 | core-code | P2 | Low | Low | S | performance — per-poll subprocess spawns | CORRECTED |
| CORE-04 | core-code | P2 | Low | Low | M | security/perf — CredentialStore `security` CLI spawn (lead 1) | — |
| CORE-05 | core-code | P2 | Med | Med | S | UX — what the user sees on auth expiry (lead 3) | — |
| CORE-06 | core-code | P2 | Med | Med | S | reliability — retry/backoff and the 60s poll design | — |
| CORE-09 | core-code | P2 | Med | Med | M | test coverage — core | — |
| CORE-07 | core-code | P3 | Low | Low | S | security — HTTPRedirectGuard scheme downgrade | — |
| CORE-08 | core-code | P3 | Low | Low | S | CLI ergonomics — houdini executable | — |
| CORE-10 | core-code | P3 | Low | Low | S | efficiency — cookie provider per-poll org lookup | — |
| CORE-11 | core-code | P3 | Low | Low | S | code quality — dead protocol surface | — |
| CORE-12 | core-code | P3 | Low | Low | S | concurrency — overall assessment (observation, positive) | — |
| MB-01 | menubar | P1 | Med | Low | S | threshold scale / site-app consistency | CONFIRMED |
| MB-02 | menubar | P1 | Med | Med | S | auth state reliability | CONFIRMED |
| MB-08 | menubar | P1 | Med | Med | S | release verification | CONFIRMED |
| MB-05 | menubar | P2 | Med | Low | M | Theme/token duplication (lead) | — |
| MB-03 | menubar | P2 | Med | Low | S | UX states — menu bar staleness | — |
| MB-04 | menubar | P2 | Med | Low | S | accessibility — menu bar contrast/color-only | — |
| MB-07 | menubar | P2 | Low | Low | S | accessibility — Settings Dynamic Type | — |
| MB-09 | menubar | P3 | Low | Med | S | release process — Info.plist version | — |
| MB-06 | menubar | P3 | Low | Low | S | reliability — rate-limit copy | — |
| MB-10 | menubar | P3 | Low | Low | S | smoke flags — coverage + docs | — |
| MB-11 | menubar | P3 | Low | Low | S | UX — manual refresh feedback | — |
| MB-12 | menubar | P3 | Low | Low | M | accessibility — desktop widget keyboard access | — |
| PER-02 | periphery | P1 | Med | Low | S | apps/widget / root docs | CONFIRMED |
| PER-01 | periphery | P2 | Med | Low | S | apps/widget | — |
| PER-03 | periphery | P2 | Med | Low | S | apps/ios | — |
| PER-04 | periphery | P2 | Med | Low | S | apps/ios docs honesty | — |
| PER-05 | periphery | P2 | Med | Low | S | apps/ios / CI | — |
| PER-06 | periphery | P3 | Low | Med | S | apps/ios/project.yml | — |
| PER-07 | periphery | P3 | Low | Med | M | apps/ios drift risk | — |
| PER-08 | periphery | P3 | Low | Low | S | apps/ios/HoudiniWidget | — |
| SITE-01 | site | P1 | High | Low | S | site/ + repo root — legal accuracy of the 'open source' claim | CONFIRMED |
| SITE-02 | site | P1 | High | Low | S | /reveals — capability accuracy (Tokens) | CONFIRMED |
| SITE-03 | site | P1 | Med | Med | S | /faq + /install + /guide — cookie-login accuracy | CORRECTED |
| SITE-04 | site | P1 | Med | Low | S | /guide — gauge threshold legend contradicts the shipped app | CONFIRMED |
| SITE-05 | site | P2 | Med | Low | S | index hero — 'Nothing leaves your Mac' precision | — |
| SITE-06 | site | P2 | Med | Low | S | sub-pages — a11y regressions the landing-only fix missed | — |
| SITE-07 | site | P2 | Med | Low | S | /guide — API-usage copy in present tense for an unbuilt capability | — |
| SITE-08 | site | P3 | Low | Low | S | /surfaces — undisclosed mock UI next to a 'Live' chip | — |
| SITE-09 | site | P3 | Low | Low | S | site/src — dead assets and dead config | — |
| SITE-10 | site | P3 | Low | Low | S | index hero — coherence of the 'KEEP GENERIC H1' decision | — |
| INS-01 | installer | P1 | High | Med | M | release CI (.github/workflows/release.yml) | CONFIRMED |
| INS-03 | installer | P1 | High | High | S | single-version prune policy (ADR-010 / RELEASE.md §5) | CORRECTED |
| INS-02 | installer | P2 | Med | Med | S | release publishing (dual paths) | — |
| INS-04 | installer | P2 | Med | Med | M | install.sh security model | — |
| INS-05 | installer | P2 | Med | Med | S | install.sh upgrade/failure behavior | — |
| INS-06 | installer | P2 | Med | Low | M | release process (RELEASE.md checklist vs ADR-010) | — |
| INS-07 | installer | P3 | Low | Low | S | scripts/README.md | — |
| INS-08 | installer | P3 | Low | Low | S | scripts/init.sh | — |
| INS-09 | installer | P3 | Low | Low | S | install.sh advertised guarantees (verification pass) | — |
| DOC-01 | docs | P1 | High | Med | S | ARCHITECTURE.md + PROVIDERS.md vs core | CONFIRMED |
| DOC-02 | docs | P1 | High | Med | S | ARCHITECTURE.md / ROADMAP.md vs apps/menubar + apps/widget | CORRECTED |
| DOC-03 | docs | P1 | Med | Med | S | CLAUDE.md + CONTEXT.md survey findings vs shipped code | CONFIRMED |
| DOC-04 | docs | P1 | Med | Low | S | Gemini provider claim (README/CONTEXT/CLAUDE/feature_list vs PROVIDERS/ROADMAP) | CONFIRMED |
| DOC-05 | docs | P2 | Med | Low | S | DECISIONS.md ADR-002 / ADR-003 vs reality | — |
| DOC-06 | docs | P2 | Low | Low | S | PROVIDERS.md / ARCHITECTURE.md — Keychain item name | — |
| DOC-07 | docs | P2 | Low | Low | S | PROVIDERS.md contract vs shipped provider set | — |
| DOC-08 | docs | P2 | Med | Low | S | ROADMAP.md phase status markers | — |
| DOC-09 | docs | P2 | Med | Low | S | feature_list.json — stale and consumer-less | — |
| DOC-10 | docs | P2 | Low | Low | S | CONTEXT.md / BACKLOG.md — stale 'staleness' claims | — |
| DOC-11 | docs | P2 | Low | Low | S | WORKFLOW.md — stale executor description, overlapping process doc | — |
| DOC-12 | docs | P3 | Low | Low | S | README.md / scripts/README.md — repo layout inaccuracies | — |
| DOC-13 | docs | P3 | Low | Low | S | RELEASE.md — checklist vs practiced reality | — |
| DOC-14 | docs | P3 | Low | Low | S | ADR-001/004/005/006/008/009/010/011/012 — conformance check (mostly clean) | — |
| DX-01 | dx | P1 | High | High | M | Release CI / supply chain | CONFIRMED |
| DX-02 | dx | P1 | High | Med | S | Release CI root cause / toolchain skew | CONFIRMED |
| DX-03 | dx | P1 | High | Med | S | Test runner integrity (swift test no-op) | CONFIRMED |
| DX-04 | dx | P1 | High | Med | S | CI baseline (PR/push) | CONFIRMED |
| DX-05 | dx | P2 | Med | Med | M | Test coverage shape (core) | — |
| DX-07 | dx | P2 | Med | Med | S | Menubar smoke flags as test substitute | — |
| DX-11 | dx | P2 | Med | Med | S | Release flow conflict (manual vs CI) | — |
| DX-06 | dx | P3 | Med | Low | M | houdini-selftest duplicate maintenance | — |
| DX-08 | dx | P3 | Med | Low | S | Build reproducibility / toolchain pinning | — |
| DX-09 | dx | P3 | Low | Low | S | .gitignore hygiene | — |
| DX-10 | dx | P3 | Low | Low | S | scripts/init.sh correctness | — |
| SEC-01 | security | P1 | Med | Med | S | core/ network layer (Keychain-only claim) | CONFIRMED |
| SEC-02 | security | P1 | High | Med | S | ADR-012 / user-facing transparency | CONFIRMED |
| SEC-03 | security | P2 | Med | Low | M | install.sh supply chain | — |
| SEC-04 | security | P2 | Med | Low | S | install.sh / site copy (Gatekeeper) | — |
| SEC-07 | security | P2 | Med | Med | S | ADR-012 risk record accuracy | — |
| SEC-05 | security | P3 | Low | Low | S | core/ ClaudeOAuthProvider (process hygiene) | — |
| SEC-06 | security | P3 | Low | Low | S | Verification record — Keychain-only + no-server claims | — |
| SEC-08 | security | P3 | Med | Low | S | ADR-012 options (c)/(d) — merits check | — |
| SEC-09 | security | P3 | Low | Low | S | core/ CredentialStore (cookie item protection class) | — |
| ORG-01 | organization | P1 | Med | Med | M | root docs — duplication & contradiction | CONFIRMED |
| ORG-02 | organization | P1 | Med | Med | S | git hygiene — uncommitted BACKLOG P4 WIP | CONFIRMED |
| ORG-03 | organization | P1 | Med | Med | S | process artifacts — conductor/ vs audit/ sprawl | CORRECTED |
| ORG-04 | organization | P2 | Med | Med | M | Build Conductor process — cost/benefit at v1 | — |
| ORG-05 | organization | P2 | Low | Low | S | feature_list.json — no consumer, no generator | — |
| ORG-06 | organization | P2 | Med | Low | S | ROADMAP.md — drift survived its own refresh | — |
| ORG-07 | organization | P2 | Low | Low | S | BACKLOG.md — internal self-contradiction | — |
| ORG-08 | organization | P2 | Low | Low | S | WORKFLOW.md — contradiction + duplication with CLAUDE.md | — |
| ORG-09 | organization | P3 | Low | Low | S | monorepo layout — verdict + apps/widget placeholder | — |
| ORG-10 | organization | P3 | Low | Low | S | naming consistency | — |
| ORG-11 | organization | P3 | Low | Low | S | git hygiene — .gitignore coverage & branch state | — |
| ORG-12 | organization | P3 | Low | Low | S | README/CLAUDE repo maps — omit half the doc set | — |
| GAP-02 | critic | P1 | High | Low | S | cross-finding contradiction — ADR-012 refresh freeze (CORE-02 vs SEC-08) | — |
| GAP-01 | critic | P2 | Med | Med | S | install.sh / uninstall story | — |
| GAP-03 | critic | P2 | Med | Low | S | cross-finding tension — DX-04 CI baseline cannot build the menubar app as recommended (vs  | — |
| GAP-04 | critic | P2 | Med | Med | S | .github / vulnerability-disclosure policy (SECURITY.md) | — |
| GAP-05 | critic | P3 | Med | Low | S | README.md — zero product imagery | — |
| GAP-06 | critic | P3 | Low | Low | S | apps/menubar/docs + design — unexamined 5.6MB tracked screenshot corpus, stale vs shipped  | — |

## 2. Findings in full, by dimension

> Every finding: observation (what is) → pasted evidence → recommendation (what should change), with the adversarial-verification outcome. Where a verifier re-scored a finding, the corrected score is shown and used.


### A. Architecture & data flow

#### ARC-01 · P1 · High/Low/S — ARCHITECTURE.md vs apps/menubar — App-Group/WidgetKit bridge

**Observation.** ARCHITECTURE.md's diagram and prose state the menu bar app 'writes value to App Group + WidgetCenter.reloadTimelines()' and that a WidgetKit widget 'reads only the cached value from the App Group'. None of this exists in the macOS app: apps/menubar/Sources has zero WidgetCenter/reloadAllTimelines/WidgetKit references, and every UserDefaults(suiteName:) use is a test harness suite ('houdini.widgettest', 'houdini.snapshot'), not an App Group ('group.*'). The only admission is apps/menubar/README.md's 'Not in this phase' line. Judgment: for v1, CORRECT THE DOC, do not implement. Implementing requires an Xcode-built .appex (impossible on this repo's declared CommandLineTools-only toolchain — apps/menubar/Package.swift comment: 'this machine has only CommandLineTools'), App-Group entitlements under ad-hoc signing (unproven, and risks the install.sh no-Gatekeeper guarantee), and would deliver a third surface that is ~15-min stale (ADR-002) next to two live 60s surfaces. Correcting is a one-file doc edit; the trade-off (losing the design record) is avoided by re-labeling those sections 'planned, not built' instead of deleting them.

**Evidence.** ARCHITECTURE.md:32 '│ writes value to App Group + WidgetCenter.reloadTimelines()'; :50 'Writes latest value into the App Group container and calls WidgetCenter.shared.reloadAllTimelines()'; :65-68 WidgetKit section. grep -rn 'WidgetCenter|reloadAllTimelines|WidgetKit' apps/menubar/Sources → 0 hits (only apps/ios/HoudiniMobile/UsageViewModel.swift:60,87). suiteName hits: WidgetTest.swift:30,33; SelfTest.swift:79,86; Snapshotter.swift:61 — all test suites. apps/menubar/README.md: 'Not in this phase — Other providers, WidgetKit/App-Group writes, distribution — later phases.'

**Challenges.** ARCHITECTURE.md (its as-built framing); consistent with, not against, ADR-002

**Recommendation.** Edit ARCHITECTURE.md: change the diagram arrow and the menu-bar bullet (L32-33, L50) to 'planned', and prefix the WidgetKit section (L65-68) with an explicit 'DESIGNED, NOT BUILT' marker referencing apps/widget's placeholder status. Do not build the bridge for v1.

**Verification.** CONFIRMED

#### ARC-02 · P1 · Med/Low/S — core/FetcherCore — phantom Scheduler/Cache components; no backoff anywhere

**Observation.** ARCHITECTURE.md and PROVIDERS.md both list 'Scheduler (per-provider interval, jitter, exponential backoff on 401/403/429)' and 'Cache (last-good value)' as FetcherCore components. Neither type exists anywhere in core/ or apps/: a repo-wide grep for backoff/jitter/Scheduler in Swift sources returns nothing. Polling and in-memory last-good caching actually live in the app's UsageModel (a fixed-cadence Timer at the user's 30/60/120s setting), and NO backoff logic exists at all — on a 429 the timer keeps firing at the same interval while the UI displays 'Rate limited — backing off, will retry', which is false. The CLI (houdini) has no cache at all. This is both doc over-claim and a small behavioral gap against the doc's own 'poll politely' constraint.

**Evidence.** ARCHITECTURE.md:16-17 'Scheduler (per-provider interval, backoff) / Cache (last-good value…)'; :42 'jitter, exponential backoff on 401/403/429'. PROVIDERS.md:37 'Cross-cutting services in FetcherCore: … Scheduler (interval + jitter + backoff), Cache'. grep -rni 'backoff|jitter|scheduler' core/Sources apps/menubar/Sources apps/ios → exit=1 (0 hits). UsageModel.swift:100 fixed Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true); :184 '"Rate limited — backing off, will retry."'.

**Challenges.** ARCHITECTURE.md §FetcherCore and PROVIDERS.md §Contract cross-cutting services

**Recommendation.** Fix both docs to attribute polling + last-good cache to the app's UsageModel and drop 'jitter/exponential backoff' claims — or implement a minimal backoff (e.g. double the effective interval after a .rateLimited result until the next success, ~15 lines in UsageModel). Either way, change the 'backing off' UI string to match real behavior.

**Verification.** CONFIRMED

#### ARC-03 · P2 · Med/Low/M — Provider-adapter abstraction (ADR-007) — real at the core, ceremonial at the edges

**Observation.** The abstraction is genuinely load-bearing where it counts today: one UsageProvider protocol, two real adapters (ClaudeOAuthProvider, ClaudeCookieProvider) selected at runtime by ClaudeAuthResolver, one shared parser proven to normalize both endpoint dialects identically, and one [UsageMetric] model consumed by three frontends (CLI, popover, NSPanel widget). But two protocol requirements are dead weight: `capabilities` is declared by every provider and read by NOTHING (the only '.capabilities' reference outside provider declarations is claude.ai org-JSON parsing), and `refreshInterval` is never consumed (the app polls at AppSettings' user-chosen interval). Meanwhile the UI hard-codes Claude-specific metric labels ('5-hour', 'Weekly', 'Sonnet weekly', 'Extra usage ($)') in Formatting.swift's ring-ranking priority map and in AppSettings.PrimaryMetricChoice. So ADR-007's and PROVIDERS.md's claim that 'the UI never special-cases a provider; it reads capability flags' is aspirational: adaptation today happens by inspecting metric shape (pct vs dollars), plus label special-casing.

**Evidence.** UsageProvider.swift:8 'var capabilities: Capabilities { get }'; grep '\.capabilities' across core+apps → only ClaudeCookieProvider.swift:158 (org JSON decode) + provider declarations. provider refreshInterval consumers → none (UsageModel.swift:47 uses settings?.refreshInterval). Formatting.swift:58 'let priority: [String: Int] = ["5-hour": 0, "Weekly": 1]'; AppSettings.swift:30-33 metricLabel returns '5-hour'/'Weekly'/'Sonnet weekly'/'Extra usage ($)'. PROVIDERS.md:3 'The UI never special-cases a provider; it reads capability flags'.

**Challenges.** ADR-007 ('registry + UI adapt' via capability flags) — the mechanism described is not the one implemented

**Recommendation.** Decide when the 2nd provider (OpenAI Platform, PND-PROV-02) lands: either wire `capabilities` into the planned Settings switcher + metric picker and make ring/pin selection label-agnostic, or trim `capabilities`/`refreshInterval` from the protocol and revise ADR-007 to say 'UI adapts to metric shape'. Until then, soften PROVIDERS.md:3 so the doc matches the code.

**Verification.** inline evidence only (P2/P3 — not adversarially re-verified)

#### ARC-04 · P2 · Med/Med/S — apps/menubar auth data flow — out-of-band credential changes never detected

**Observation.** UsageModel's comment says 'the active provider is resolved fresh on each fetch (so sign-in/out … take effect immediately)', but the resolveProvider closure just returns ClaudeSession.currentProvider — a CACHED value. ClaudeSession.refresh() (which re-reads the Keychain and rebuilds the provider) runs only at init, when the prefer-cookie toggle flips, and when Houdini's own login window closes. Consequence: a user who installs Houdini first (shows 'signed out') and then logs into Claude Code in the terminal will never be picked up — the 60s timer keeps resolving nil until app relaunch. Same for a token restored/re-created out of band after expiry. This undercuts the P1 'works for any Claude Code user' goal for a realistic first-run ordering.

**Evidence.** UsageModel.swift:27-28 'the active provider is resolved fresh on each fetch (so sign-in/out … take effect immediately)'; :115 'resolveProvider.map { $0() }'. ClaudeSession.swift:21 'private(set) var currentProvider' set only in refresh(); refresh() call sites: init (ClaudeSession.swift:34), preferCookieAuth sink (:39), login onClose (:73). No periodic or fetch-time re-resolution exists; grep 'session.refresh()' in apps/menubar/Sources → only those sites.

**Recommendation.** In UsageModel.refreshNow(), when the resolved provider is nil (signed out) — and optionally after an .authExpired failure — call session.refresh() before giving up, so a newly-appeared Claude Code credential is discovered on the next tick. Keep the happy path unchanged to avoid a 60s /usr/bin/security subprocess when already authenticated (see PND-APP-05).

**Verification.** inline evidence only (P2/P3 — not adversarially re-verified)

#### ARC-05 · P2 · Med/Low/S — Desktop widget: NSPanel vs WidgetKit — merits judgment + missing ADR

**Observation.** Judged on its merits, the NSPanel choice is correct for v1. The desktop widget shares the menu bar process, UsageModel and single timer (verified: AppDelegate builds one model and hands it to DesktopWidgetController), so it gets true 60s freshness — the product's core promise — with zero IPC, no App Group, no Apple reload budget (ADR-002 caps WidgetKit at ~40-70 reloads/day), and it builds on the repo's CommandLineTools-only toolchain, where a WidgetKit .appex cannot be built at all. The desktop-furniture semantics are competently implemented (window level desktopIconWindow+1, canJoinAllSpaces/stationary/ignoresCycle, non-activating, frame+display persistence with off-screen recovery). Real costs accepted: it lives outside the macOS widget gallery/Sonoma desktop-widget management, needs bespoke persistence/screen-recovery code WidgetKit gives free, and is nonstandard UX. However, NO ADR records this decision — ADR-002 and ADR-003 still name Übersicht as the 60s desktop surface, and the only trace is one ARCHITECTURE.md parenthetical.

**Evidence.** HoudiniApp.swift:21-27 one UsageModel + 'lazy var desktopWidget = DesktopWidgetController(model: model, session: session, …)'. DesktopWidgetController.swift:113-115 'panel.level = …desktopIconWindow…+1; panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]'. apps/menubar/Package.swift comment: 'this machine has only CommandLineTools (no full Xcode…)'. DECISIONS.md ADR index (grep '^## ADR') has no desktop-widget ADR; ADR-002:11 'the menu bar app (and Übersicht)'. ARCHITECTURE.md:63 '(Replaces the former Übersicht .jsx widget.)'.

**Challenges.** Revises ADR-002/ADR-003 stale framing; fills a missing decision record rather than reversing one

**Recommendation.** Keep the NSPanel architecture for v1. Write a new ADR (ADR-013) recording: NSPanel-in-host-process is the desktop surface (why: 60s freshness, toolchain, signing), WidgetKit desktop placement is a non-goal, the NC widget stays a possible post-v1 glanceable extra; revise the Übersicht references in ADR-002/003 in the same pass (overlaps PND-DOC-01).

**Verification.** inline evidence only (P2/P3 — not adversarially re-verified)

#### ARC-06 · P3 · Low/Low/S — 'No server, direct-to-provider' claim — full endpoint enumeration (VERIFIED)

**Observation.** The claim holds. Exhaustive grep of core/ and apps/ Swift sources for URL(/https:///URLSession/URLRequest finds exactly these reachable endpoints: (1) GET https://api.anthropic.com/api/oauth/usage (OAuth bearer path); (2) GET https://claude.ai/api/organizations and (3) GET https://claude.ai/api/organizations/{orgId}/usage (cookie path); (4) a WKWebView load of https://claude.ai/login for interactive sign-in (browser semantics — the login page may pull claude.ai subresources/SSO redirects, but nothing Houdini-owned); the iOS scaffold repeats (4) and is uncompiled. No telemetry, update-check, or Houdini-owned host exists in app code; no plain http:// URLs; both API paths use a redirect guard that strips Authorization/Cookie on cross-host redirects. Two nits: the entitlements comment says outbound HTTPS 'to api.anthropic.com' though the app equally talks to claude.ai, and the endpoint inventory is documented nowhere.

**Evidence.** grep 'https://' core/ apps/ *.swift → ClaudeCookieProvider.swift:26,28 (claude.ai/api/organizations[+/usage]); ClaudeOAuthProvider.swift:48 (api.anthropic.com/api/oauth/usage); ClaudeLoginWindow.swift:10 + apps/ios ClaudeLoginView.swift:78 (claude.ai/login). grep 'http://' sources → exit=1. HTTPRedirectGuard.swift:3-11 'strips credential headers (Cookie, …)'. Houdini.entitlements: '<!-- Outbound HTTPS to api.anthropic.com. -->' + network.client only.

**Recommendation.** Add the 4-endpoint inventory as a short table in ARCHITECTURE.md (it strengthens the trust story and makes future drift auditable) and widen the entitlements comment to 'api.anthropic.com + claude.ai'. No code change needed.

**Verification.** inline evidence only (P2/P3 — not adversarially re-verified)

#### ARC-07 · P3 · Low/Low/S — core/FetcherCore/ClaudeCookieProvider — org lookup repeated every poll

**Observation.** The cookie provider issues two claude.ai requests per poll: it re-fetches GET /api/organizations and re-runs org selection on every 60s tick, even though the selected org id is stable for a session. This doubles request volume against an undocumented consumer endpoint for cookie-auth users (the exact population ADR-012 worries about w.r.t. detection/throttling) and doubles the 429 surface.

**Evidence.** ClaudeCookieProvider.swift:60-66: 'func fetch() … let orgsData = try await get(Self.orgsURL, …); let orgId = try Self.selectOrganization(from: orgsData); let usageData = try await get(Self.usageURL(orgId: orgId), …)'. The struct holds no cached org state; UsageModel calls provider.fetch() every refreshInterval (UsageModel.swift:132).

**Recommendation.** Cache the resolved orgId in memory (e.g. in ClaudeSession or an actor inside the provider) and invalidate it on .needsLogin, halving steady-state cookie-path traffic. Note ClaudeCookieProvider is a struct rebuilt per resolution, so the cache belongs one level up or in a shared actor.

**Verification.** inline evidence only (P2/P3 — not adversarially re-verified)

#### ARC-08 · P3 · Low/Low/S — README.md — Notification Center widget phrasing overstates apps/widget

**Observation.** The root README says a 'glanceable Notification Center widget (WidgetKit, apps/widget) also exists in the repo'. What exists is a single 82-byte, one-line README — no Swift target, no manifest, no widget. 'Exists in the repo … an architecture surface' reads as more than a placeholder; feature_list.json more honestly calls it 'planned'. Minor, but it is the same over-claim family as ARC-01 on the most-read doc.

**Evidence.** README.md:35-36 'A glanceable Notification Center widget (WidgetKit, apps/widget) also exists in the repo; Apple caps its refresh at ~15 min (ADR-002)…'. ls apps/widget → only README.md (82 bytes); its full content: 'WidgetKit / Notification Center widget. Glanceable ~15min (Apple limit, ADR-002).'

**Recommendation.** Reword to 'is planned (placeholder directory, ADR-002 caps it at ~15 min)' so README, feature_list.json and the tree agree.

**Verification.** inline evidence only (P2/P3 — not adversarially re-verified)

#### ARC-09 · P3 · Low/Low/M — Future WidgetKit coupling — snapshot bridge stranded in the uncompiled iOS scaffold

**Observation.** The only App-Group snapshot bridge in the whole repo lives in apps/ios/Shared/SharedSnapshot.swift (writes/reads UsageSnapshot JSON in container group.org.salomao.houdini) — an uncompiled scaffold with a TODO Team ID. If any WidgetKit surface (macOS NC widget or iOS) ever ships, this bridge is generic core logic (UsageSnapshot is already Codable in FetcherCore) and will otherwise be re-scaffolded per platform. Similarly, the cookie-capture constants (cookie name 'sessionKey', prefix 'sk-ant-sid01') are duplicated between the macOS login window and the iOS login view instead of living in FetcherCore next to ClaudeCookieProvider.

**Evidence.** SharedSnapshot.swift:4-15 'the app … writes the latest UsageSnapshot into the App Group container; the widget reads that cached snapshot…; static let appGroupID = "group.org.salomao.houdini"' (+ TODO(xcode) Team ID note). Duplication: ClaudeLoginWindow.swift:11-12 cookieName/cookiePrefix vs apps/ios/ClaudeLoginView.swift:79-80 identical constants.

**Recommendation.** Defer until a WidgetKit surface is actually scheduled; at that point move the snapshot read/write helper into FetcherCore (parameterized by App Group id) and hoist the sessionKey cookie constants into FetcherCore so both platforms share them. Do not build now (anti-over-engineering budget).

**Verification.** inline evidence only (P2/P3 — not adversarially re-verified)

**Dimension summary.** Dimension A mapped the actual end-to-end data path and it is simpler and tighter than the docs claim. VERIFIED PATH: UsageProvider protocol (core/Sources/FetcherCore/UsageProvider.swift:4-12) → runtime auth selection by ClaudeAuthResolver (ClaudeAuth.swift:63-82: OAuth → cookie → nil) → either ClaudeOAuthProvider GET https://api.anthropic.com/api/oauth/usage with Bearer token + claude-code/<v> UA (ClaudeOAuthProvider.swift:48,89-126) or ClaudeCookieProvider GET https://claude.ai/api/organizations then /organizations/{id}/usage with the sessionKey cookie (ClaudeCookieProvider.swift:26-29,60-66) → one tolerant ClaudeUsageParser normalizes both dialects into [UsageMetric]/UsageSnapshot (Models.swift) → the app's single UsageModel polls on a fixed Timer at the user's 30/60/120s setting (UsageModel.swift:100-108) → consumed by the MenuBarExtra popover AND the desktop NSPanel widget in the SAME process sharing the SAME model and timer (HoudiniApp.swift:21-27; DesktopWidgetController.swift) — this menu-bar↔desktop-widget coupling is clean and matches the docs. The houdini CLI is a fourth thin consumer via ProviderRegistry.makeDefault(). LEAD CONFIRMED: no App-Group write and no WidgetCenter call exist in apps/menubar (only test-suite suiteNames); ARCHITECTURE.md L32-33/L50/L65-68 describe an unbuilt bridge, and it additionally invents FetcherCore 'Scheduler' (jitter/backoff) and 'Cache' components that exist nowhere — PND-DOC-03 upgraded to 'corrected'. Judgment: correct the doc for v1 (S effort), do not implement — a WidgetKit .appex can't even be built on the repo's CommandLineTools-only toolchain and would add a ~15-min-stale third surface. NSPanel-vs-WidgetKit judged on merits: NSPanel is the right v1 architecture (true 60s, one process, no reload budget, buildable, competent desktop-furniture semantics) but the decision has no ADR while ADR-002/003 still credit Übersicht — write ADR-013. The 'no server, direct-to-provider' claim is VERIFIED by exhaustive endpoint enumeration (4 endpoints, all Anthropic-owned; credential-stripping redirect guard; no telemetry/update hosts; no plain http). The provider abstraction is real at its core (2 adapters × 4 consumers through one normalized model) but ceremonial at the edges: capabilities/refreshInterval have zero consumers and the UI hard-codes Claude labels, contradicting ADR-007's stated mechanism. Two new bug-class gaps found: false 'backing off' UI copy with no backoff anywhere, and out-of-band CLI logins never detected until relaunch (cached ClaudeSession.currentProvider). All 5 assigned pendências validated: 4 confirmed, 1 corrected; 6 new pendências added.


### B1. Code quality — core/ (auth, fetch, reliability)

#### CORE-01 · P1 · High/High/S — auth/reliability — runtime auth resolution

**Observation.** Claude auth is resolved once at launch and only re-resolved on explicit user action (prefer-cookie toggle, login-window close, sign-out). `UsageModel` reads `session.currentProvider` on each poll, but `ClaudeSession.refresh()` is never called periodically or on fetch failure. Consequence 1: launch with an expired/absent OAuth token → app shows 'Sign in' for the ENTIRE run, even after the user runs `claude` and the Keychain item becomes valid again (only relaunch or an unrelated Settings action recovers). Consequence 2: mid-run OAuth expiry never falls back to a valid stored cookie — the app errors forever on the dead OAuth path.

**Evidence.** HoudiniApp.swift:21-24 `resolveProvider: { [weak self] in self?.session.currentProvider }`. UsageModel.swift:115-124: nil provider → `state = .signedOut` and return. Grep of `refresh()` call sites in apps/menubar: only ClaudeSession.swift L34 (init), L39 (preferCookieAuth sink), L73 (login onClose), L85 (signOut) — no timer, no call from fetch errors, no call from `refreshNow()`. `hasUsableToken()` (ClaudeOAuthCredentialSource.swift:165-169) returns false for expired+refreshToken+refresher==nil, so launch-expired resolves `.none`.

**Recommendation.** Re-run `session.refresh()` before each poll when state is `.signedOut`/`.error` (or on every tick — cost is 1-3 `security` spawns, ~15ms each), so credential appearance/expiry/cookie-fallback are picked up without relaunch. Trade-off: more Keychain reads per minute; gate it to non-`.ok` states to keep the common path unchanged.

**Verification.** CORRECTED (score → P1 (impact High for the launch-locked signed-out case, Med for the missing mid-r)

#### CORE-02 · P1 · High/Med/M — auth — frozen OAuth refresh (leads 2)

**Observation.** OAuth refresh is fully built and tested but production wires `refresher == nil` (ADR-012 §3), so an expired access token makes `hasUsableToken()` false → resolver demotes to cookie/`.none`. The repo does not document the Claude Code access-token TTL and it could not be measured on this machine (no ~/.claude/.credentials.json; Keychain untouched by this audit). Judgment challenging ADR-012 §3: freezing refresh does not reduce ToS exposure — an expired-at-launch CLI user is shown 'Connect Claude', which launches the claude.ai cookie WebView, i.e. the SAME prohibited surface ADR-012 §Context names, but ephemeral (ADR-005) and re-login-looping. The freeze shifts users to the weaker credential rather than avoiding risk, while the traffic signature (60s polls with a claude-code UA) is unchanged.

**Evidence.** ClaudeOAuthCredentialSource.swift:111 `public init(store: CredentialStore = CredentialStore(), refresher: Refresher? = nil)`; L168 `return blob.nonEmptyRefreshToken != nil && refresher != nil`. ClaudeSession.swift:27 `private let resolver = ClaudeAuthResolver()` (no refresher injected). DECISIONS.md:64 'no OAuth token refresh (the `refresher` stays `nil`)'. SharedUI.swift:137-146 NeedsAuthView → `session.signIn()` → ClaudeLoginWindow (cookie WebView). ADR-012 §Context (DECISIONS.md:60): 'Both of Houdini's Claude auth paths fall within the prohibited use.'

**Challenges.** ADR-012 Decision §3 (DECISIONS.md L64) — the refresh freeze; partially also BACKLOG P1 cap rationale

**Recommendation.** Revisit ADR-012 §3 on this narrow point: wiring the already-built in-memory refresh (no persistence) keeps existing CLI users on the credential they already have and reduces cookie-path funneling; the marginal 'signal escalation' of a refresh call is arguably smaller than pushing users into fresh claude.ai WebView logins. If the freeze stands, at minimum change the expired-at-launch copy to say 'run `claude` to refresh your token' instead of funneling into the cookie flow.

**Verification.** CORRECTED (score → P1 (impact High, risk Med) — but split the effort: S for the ADR-012-compliant c)

#### CORE-03 · P2 · Low/Low/S *(re-scored by adversarial verifier; original P1)* — performance — per-poll subprocess spawns

**Observation.** `ClaudeOAuthProvider.clientVersion` is a computed property that calls `detectedClientVersion()` on EVERY `fetchUsage`, spawning `/usr/bin/env claude --version` (a Node CLI) synchronously each 60s poll — measured 0.43s wall on this machine, ~30x the cost of the `security` spawn the CredentialStore TODO tracks, and it blocks a Swift-concurrency cooperative thread via `waitUntilExit()`. It also executes a PATH-resolved binary from a credential-handling app instead of pinning an absolute path. The result is identical across polls and trivially cacheable.

**Evidence.** ClaudeOAuthProvider.swift:130-131 `private var clientVersion: String { explicitVersion ?? Self.detectedClientVersion() }` (no cache); :96 used per request; :142-144 `proc.executableURL = URL(fileURLWithPath: "/usr/bin/env"); proc.arguments = ["claude", "--version"]`; :151 `proc.waitUntilExit()`. Measured: `time (claude --version)` → `0.426 total`; `time security find-generic-password …` → `0.015 total`.

**Recommendation.** Cache the detected version once per process (e.g. a `static let`), or resolve it lazily at provider construction; optionally probe known absolute install paths before falling back to `env`. This removes ~0.4s of subprocess work per poll and the PATH-hijack surface.

**Verification.** CORRECTED (score → P2 (impact Low, risk Low, effort S))

#### CORE-04 · P2 · Low/Low/M — security/perf — CredentialStore `security` CLI spawn (lead 1)

**Observation.** Confirmed: the default read path shells `/usr/bin/security find-generic-password -s <service> -w` on every poll (CredentialStore.swift:55-57 → cliReadGenericPassword). Severity judgment: LOWER than it sounds on security — the argv visible to `ps` contains only the service name, never the token; the secret transits the child's stdout pipe, which is private to Houdini. Real costs: ~15ms/spawn (measured), a synchronous `Process` + `waitUntilExit()` inside async code, and process-spawn noise from a menu-bar agent. Minor robustness nit: stdout is drained fully before stderr (L84-85), a theoretical pipe-buffer deadlock if `security` ever wrote >64KB to stderr — practically impossible for this tool. The TODO gating migration on a signed app is sound.

**Evidence.** CredentialStore.swift:55-57 `return try cliReadGenericPassword(...)` (default macOS path); :71-77 args `["find-generic-password","-s",service,"-w"]` — no secret in argv; :84-87 sequential `readDataToEndOfFile()` then `waitUntilExit()`; :48-54 `TODO(phase ≥2, signed app)`. Measured spawn: 0.015s. Per poll: 1 spawn (primary item hit first per ClaudeOAuthCredentialSource.discover L147-151); ClaudeSession.refresh() costs ~3 (hasUsableOAuthToken + resolve + makeProvider each re-run blobLoader).

**Recommendation.** Keep the TODO as the plan of record but re-rank it below CORE-03 (the `claude --version` spawn is the dominant per-poll cost). When migrating, note `discover` re-reads the Keychain on every call — add one-shot caching per fetch cycle at the same time.

**Verification.** inline evidence only (P2/P3 — not adversarially re-verified)

#### CORE-05 · P2 · Med/Med/S — UX — what the user sees on auth expiry (lead 3)

**Observation.** On mid-run OAuth expiry the model keeps last-good metrics and sets `.error`; the popover shows an 11px banner 'Showing last value — Claude token expired / not found — re-authenticate Claude Code.' — clear, but with NO action button (the sign-in CTA is gated on `needsLogin`, which is set only for the cookie path). The menu bar label keeps rendering the frozen number with threshold colors and NO staleness cue whatsoever, so the primary at-a-glance surface silently shows stale data indefinitely. The desktop widget's stale chip says only 'Showing last value' (9px) and omits the reason entirely. Settings' 'active auth' label also goes stale (never re-resolved, see CORE-01).

**Evidence.** UsageModel.swift:140-142 error keeps metrics, `needsLogin` true only for `.needsLogin`; :180 authExpired message. UsagePopover.swift:82-84 staleBanner (text only, no button); :117 CTA only `if model.needsLogin`. MenuBarLabelContent.swift:12-20: `if let primary = model.metrics.primary(...)` renders the number regardless of `state.isError` — the error glyph branch (L30-37) is reached only when metrics are empty. DesktopWidgetView.swift:221-229 staleChip has no reason text.

**Recommendation.** Add a staleness cue to the menu bar label when `state.isError` (e.g. dim the number or add a small warning glyph); include the reason in the widget's stale chip tooltip/accessibility; give the authExpired banner an action ('Open Settings' or 'How to fix'). Trade-off vs ADR-002 minimalism: a subtle opacity change is enough.

**Verification.** inline evidence only (P2/P3 — not adversarially re-verified)

#### CORE-06 · P2 · Med/Med/S — reliability — retry/backoff and the 60s poll design

**Observation.** There is no retry, no exponential backoff, and no jitter anywhere: every failure (429, 5xx, network) is simply retried at the fixed user cadence (30/60/120s). The rate-limited UI message claims 'Rate limited — backing off, will retry.' — false: nothing backs off. The poll design itself is otherwise sound (timer at app scope, tolerance set, one fetch in flight, generation-stamped results), but no explicit URLSession timeout is configured, so a stalled response can suppress polls via the `fetchTask == nil` guard for as long as Foundation's defaults allow.

**Evidence.** UsageModel.swift:184 `return "Rate limited — backing off, will retry."`; grep for backoff/retry across core+menubar sources finds only message strings and comments, no logic. UsageModel.swift:126 `guard fetchTask == nil else { return }` — a hung fetch skips subsequent ticks. ClaudeOAuthProvider.swift:103 / ClaudeCookieProvider.swift:89 use `URLSession.shared` with default config (no timeoutIntervalForRequest tuning).

**Recommendation.** Either implement a real backoff on 429 (e.g. skip N ticks, honor Retry-After if present) or fix the message to 'will retry in ~60s'. Set an explicit request timeout (~15-30s) on a dedicated URLSession so a hung request can't starve the poll loop.

**Verification.** inline evidence only (P2/P3 — not adversarially re-verified)

#### CORE-09 · P2 · Med/Med/M — test coverage — core

**Observation.** Core tests are genuinely good for parsing/discovery/org-selection, but the live-path seams are untested: no test covers ClaudeOAuthProvider's HTTP status mapping (200/401→authExpired/429/other) or its 401→refresh→retry-once branch; nothing exercises `ClaudeCookieProvider.fetch()`'s two-request flow or its sessionKeyReader error mapping (notFound→needsLogin); CredentialStore (both read paths, exit-44 mapping) and CredentialRedirectGuard are untested. Separately, `houdini-selftest` hand-duplicates ~240 lines of the swift-testing suite — a drift risk since nothing enforces the mirror stays in sync.

**Evidence.** core/Tests contains only ClaudeAuthResolverTests.swift (167 ln), ClaudeUsageParserTests.swift (102 ln), OrgSelectionTests.swift (40 ln). No URLProtocol/mock-transport tests; ClaudeOAuthProvider.fetch's retry branch (ClaudeOAuthProvider.swift:72-81) has no test. houdini-selftest/main.swift:128 'Mirrors ClaudeAuthResolverTests.swift' — manual duplication. PND-TEST-03's cookie-user gap is a subset of this.

**Recommendation.** Add a mock URLProtocol (or injectable transport closure, matching the existing seam style) and cover: status→error mapping for both providers, the 401-refresh-retry, cookie notFound→needsLogin, and redirect-guard stripping. Consider generating the selftest checks from a shared table to kill the manual mirror.

**Verification.** inline evidence only (P2/P3 — not adversarially re-verified)

#### CORE-07 · P3 · Low/Low/S — security — HTTPRedirectGuard scheme downgrade

**Observation.** `CredentialRedirectGuard` compares only hosts, not schemes: a same-host redirect from https to http keeps the `Authorization`/`Cookie` headers on the cleartext request. Practical risk is low (Anthropic won't issue such redirects; a MITM can't forge one without breaking TLS; ATS may additionally block http — unverified for an unbundled binary), but for purpose-built credential-protection code the check is incomplete. The guard also has zero test coverage despite `sameSite` being a pure static function.

**Evidence.** HTTPRedirectGuard.swift:19-27 compares `task.originalRequest?.url?.host` vs `request.url?.host` only; :33-35 `sameSite` is host-suffix logic; no scheme check anywhere. Grep of core/Tests: no test file references `CredentialRedirectGuard` or `sameSite`.

**Recommendation.** Strip credentials when `request.url?.scheme != "https"`; add unit tests for `sameSite` (exact host, subdomain both directions, `evilclaude.ai` lookalike, scheme downgrade).

**Verification.** inline evidence only (P2/P3 — not adversarially re-verified)

#### CORE-08 · P3 · Low/Low/S — CLI ergonomics — houdini executable

**Observation.** The `houdini` CLI has no `--help`, no `--version`, and no usage output; unknown flags are silently ignored by design (`--jsn` typo behaves like `--json`), and any first non-flag argument is taken as a provider id. Exit codes are reasonable (64 EX_USAGE for unknown provider, 2 for ProviderError, 1 otherwise) but undocumented outside the source header; core/README.md is a single line. The missing `--version` also collides with the planned P4 `houdini update` requirement to 'report the new version' (PND-REL-03 notes no update subcommand; there is also no version to report).

**Evidence.** core/Sources/houdini/main.swift:14-15 'JSON is the only output mode, so `--json` is accepted and ignored. … unknown flags are ignored.'; :21-22 `arguments.first { !$0.hasPrefix("-") } ?? "claude"`; :27 `exit(64)`; :43 `exit(2)`; :46 `exit(1)`. Grep for `--version|--help` across core sources/READMEs: only the `claude --version` probe hit. core/README.md: 1 line, no usage.

**Recommendation.** Add `--help` and `--version` (inject the release tag at build time), print usage + exit 64 on unrecognized flags, and document exit codes in core/README.md.

**Verification.** inline evidence only (P2/P3 — not adversarially re-verified)

#### CORE-10 · P3 · Low/Low/S — efficiency — cookie provider per-poll org lookup

**Observation.** `ClaudeCookieProvider.fetch()` re-fetches `GET /api/organizations` on every poll before the usage call, doubling request volume against claude.ai (2 req/min at the 30s setting = 4/min) for a value that effectively never changes within a session. Given ADR-012's own concern about traffic signal, halving the cookie path's request rate is both a perf and posture win.

**Evidence.** ClaudeCookieProvider.swift:60-66: `fetch()` always runs `get(Self.orgsURL…)` → `selectOrganization` → `get(usageURL…)`. No caching of orgId anywhere (struct is stateless, rebuilt only on auth changes but fetch always does both calls).

**Recommendation.** Cache the selected orgId in-memory (e.g. an actor or a `Mutex`-guarded static) and refresh it only on 401/404 of the usage call.

**Verification.** inline evidence only (P2/P3 — not adversarially re-verified)

#### CORE-11 · P3 · Low/Low/S — code quality — dead protocol surface

**Observation.** `UsageProvider.refreshInterval` is a protocol requirement every provider implements (both return 60) but nothing ever reads it: the app's cadence comes exclusively from `AppSettings.refreshInterval` (30/60/120). Dead contract surface that misleads future adapter authors into thinking the value is honored.

**Evidence.** UsageProvider.swift:9 `var refreshInterval: TimeInterval { get }`; ClaudeOAuthProvider.swift:41 and ClaudeCookieProvider.swift:18 both `= 60`. Grep for consumers: only UsageModel's own settings-driven `refreshInterval` (UsageModel.swift:32,42) and SelfTest/PreviewData stubs — no read of `provider.refreshInterval`.

**Recommendation.** Either honor it (clamp the settings interval to the provider's floor — useful once the ~15-min-capped providers of ADR-002 arrive) or delete it from the protocol until needed.

**Verification.** inline evidence only (P2/P3 — not adversarially re-verified)

#### CORE-12 · P3 · Low/Low/S — concurrency — overall assessment (observation, positive)

**Observation.** Concurrency safety is largely sound: Swift 6 tools-version with `Sendable` structs and `@Sendable` closures throughout core; `UsageModel`/`ClaudeSession` are `@MainActor`; the generation-stamped single-in-flight fetch correctly prevents a superseded fetch from resurrecting stale state; `CredentialRedirectGuard` is stateless `@unchecked Sendable`. The one systemic wart is synchronous `Process.waitUntilExit()` calls (CredentialStore, detectedClientVersion) running inside async fetch paths, blocking cooperative-pool threads for up to ~0.45s per poll (see CORE-03/04).

**Evidence.** Package.swift:1 `swift-tools-version: 6.0`. UsageModel.swift:129-145 generation guard on every mutation; :168-172 `invalidateFetch` bumps generation + cancels. ClaudeOAuthCredentialSource.swift:32 `public struct … : Sendable` with `@Sendable` seams (L102-104). Blocking spawns: CredentialStore.swift:83-87, ClaudeOAuthProvider.swift:149-151.

**Recommendation.** No structural change needed; when fixing CORE-03/04, wrap unavoidable `Process` calls in a detached/blocking-friendly context or use `posix_spawn`-style async wrappers.

**Verification.** inline evidence only (P2/P3 — not adversarially re-verified)

**Dimension summary.** Dimension B1 (core/ code quality + auth/fetch + reliability). Overall the core is small, well-documented, Swift-6-Sendable-clean, with excellent injectable seams (ClaudeOAuthCredentialSource, sessionKeyReader), typed errors, token-safe messaging, a thoughtful credential-stripping redirect guard, and a correctly generation-stamped single-in-flight poll loop. Against that strong baseline, the audit found one genuine P1 reliability bug the inventory misses: auth is resolved once at launch and never re-resolved at runtime, so launching with an expired token strands the app in 'signed out' for the entire run even after the credential becomes valid, and mid-run expiry never falls back to a stored cookie (CORE-01). Lead verdicts: (1) the CredentialStore `security` spawn is confirmed but benign on security (no secret in argv/ps; ~15ms measured) — the real per-poll cost is the untracked `claude --version` spawn (~0.43s measured, every 60s, uncached, PATH-resolved) (CORE-03/04); (2) the frozen refresh (`refresher == nil`, ADR-012 §3) is confirmed, but its consequence challenges the ADR's own logic — expired-at-launch CLI users are funneled into the claude.ai cookie WebView, the same ToS-prohibited surface, only weaker and re-login-looping (CORE-02); the token TTL is documented nowhere in-repo and was not measurable on this machine; (3) on expiry the UI keeps last-good data with a clear popover banner but no action button, the menu bar shows a frozen number with zero staleness cue, and the desktop widget's stale chip omits the reason (CORE-05). Also found: no retry/backoff despite a UI message claiming it (CORE-06), untested live HTTP paths and redirect guard (CORE-09, extends PND-TEST-03), a scheme-downgrade hole in the redirect guard (CORE-07), and minimal CLI ergonomics (no --help/--version, CORE-08). All seven assigned pendências validated as confirmed, with severity annotations on PND-APP-05 and a sharpened consequence on PND-APP-02/06; ten new pendências added.


### B2/E1/I. Code quality + UX states — apps/menubar

#### MB-01 · P1 · Med/Low/S — threshold scale / site-app consistency

**Observation.** The shipped site guide documents gauge color thresholds that contradict the app. The app colors gauges green <60%, amber 60-85%, red >85% (three switch functions in Formatting.swift; also stated in apps/menubar/README.md:55), but site/src/pages/guide.astro tells users green is 0-74%, amber 75-89%, red 90-100%. A user at 70% sees amber in the app while the guide says green territory.

**Evidence.** site/src/pages/guide.astro:28-30: `{ dot: "bg-ok", range: "0–74%", ... }{ dot: "bg-warn", range: "75–89%", ... }{ dot: "bg-danger", range: "90–100%", ... }` vs apps/menubar/Sources/Houdini/Formatting.swift:8-11: `case ..<60: return .green / case ..<85: return .orange / default: return .red` and apps/menubar/README.md:55: "**Thresholds:** `<60%` normal, `60–85%` amber, `>85%` red."

**Challenges.** Challenges the BACKLOG.md:96 claim that shared tokens mean the surfaces "can never drift" — the token layer only covers the two in-app surfaces; the site legend already drifted.

**Recommendation.** Fix guide.astro to 0-59 / 60-84 / 85-100 (or change the app if 75/90 is the intended scale — pick one). Add the threshold cutoffs to the RELEASE.md consistency grep so the two can't drift again.

**Verification.** CONFIRMED

#### MB-02 · P1 · Med/Med/S — auth state reliability

**Observation.** A signed-out Houdini never re-detects a newly added credential while running. ClaudeSession caches currentProvider and refresh() is only called at init, on the prefer-cookie toggle, and when the app's own login window closes/signs out. If the user launches Houdini first and then authenticates Claude Code in the terminal (the exact P1 target persona), the menu bar stays stuck on "Sign in" — the 60s timer and the manual Refresh button both read the cached nil provider — until app relaunch or opening/closing the in-app login.

**Evidence.** ClaudeSession.swift:21 `private(set) var currentProvider` set only in refresh() (L44-50); grep for `.refresh()` in apps/menubar/Sources finds only ClaudeSession.swift:39 (preferCookie sink) and :73 (login onClose), plus init/signOut. HoudiniApp.swift:23 `resolveProvider: { self?.session.currentProvider }`; UsageModel.swift:115-123: nil provider → `state = .signedOut; return` on every tick, never re-resolving.

**Recommendation.** Call session.refresh() when the model is in .signedOut on each timer tick (or at least from the popover's Refresh button / on popover open). Keychain presence checks are already performed per-fetch in other paths, so cost is negligible.

**Verification.** CONFIRMED

#### MB-08 · P1 · Med/Med/S — release verification

**Observation.** The release workflow builds and publishes binaries with zero verification: no `swift test` for core, and none of the app's own headless smoke flags (--selftest, --metrictest, --widgettest, --launchtest, --snapshot) are executed before `gh release create`. The proof harness exists but nothing runs it automatically; RELEASE.md pre-flight assumes "CI passing" that doesn't exist (cf. PND-TEST-05).

**Evidence.** .github/workflows/release.yml steps: Checkout → select toolchain → `./build.sh release` → `swift build -c release --product houdini` → stage+shasums → `gh release create`. `grep -n "selftest|metrictest|snapshot|launchtest|widgettest|test" release.yml` returns no matches. Main.swift:9-40 shows all five headless modes exist in the shipped binary.

**Recommendation.** Add `swift test` (core) and at minimum `--metrictest` + `--selftest 2 5` runs against the built binary as workflow steps before publishing; they are deterministic and stderr-only. --widgettest may need a WindowServer session — verify on the runner before gating on it.

**Verification.** CONFIRMED

#### MB-05 · P2 · Med/Low/M — Theme/token duplication (lead)

**Observation.** The threshold scale + palette exists in 3 independent copies with real drift: (1) apps/menubar Formatting.swift Thresholds — cutoffs 60/85, SwiftUI system .green/.orange/.red; (2) apps/ios/Shared/Theme.swift — a second Theme enum, same 60/85 cutoffs but hex #34d399/#f5a623/#f2555f and a stale blue accent #3b82f6 while claiming to be "in lockstep with the website's design tokens" (the site rebranded to violet #8b5cf6); (3) site global.css tokens + guide.astro legend (which uses different cutoffs entirely, see MB-01). So the same semantic state renders three different ambers. A shared HoudiniUI extraction is NOT warranted for v1: the menubar package's only target is an executable (not importable by a future WidgetKit extension anyway), the WidgetKit widget is unbuilt (PND-NCW-01), and iOS is frozen scaffold.

**Evidence.** apps/menubar/Sources/Houdini/Formatting.swift:5-37 (three switch fns, 60/85, .green/.orange/.red); apps/ios/Shared/Theme.swift:3-5 "kept in lockstep with the website's design tokens", :16 `accent = Color(hex: 0x3b82f6)`, :25-31 `case ..<60 ... ..<85`; site/src/styles/global.css:20 `--color-accent: #8b5cf6`, :31-33 `--color-ok: #34d399; --color-warn: #f5a623; --color-danger: #f2555f`; apps/menubar/Package.swift:24-25 `.executableTarget(name: "HoudiniApp")` — the app's UI code lives in an executable target, which SPM cannot import from another target.

**Challenges.** Partially refutes the lead's framing: the duplication is real, but the third copy is the SITE (guide.astro + global.css) and the iOS scaffold, not a second in-repo Swift UI layer; menubar-internal tokens are genuinely single-source since P2 slice 2.

**Recommendation.** For v1: fix the two S-effort drifts (guide.astro numbers per MB-01; rewrite the apps/ios Theme header as "stale, mirrors pre-rebrand palette" or update its hexes). Defer a HoudiniUI library extraction until apps/widget is actually built — at that point move Theme/SharedUI/WidgetRingGauge (and the 60/85 cutoffs, which are data semantics and could live in FetcherCore) into a library product. Trade-off: extracting now adds a package boundary with zero second consumer.

**Verification.** inline evidence only (P2/P3 — not adversarially re-verified)

#### MB-03 · P2 · Med/Low/S — UX states — menu bar staleness

**Observation.** Stale data is indistinguishable from fresh data in the menu bar. On fetch error with a last-good reading, the popover shows a "Showing last value" banner and the widget a stale chip, but MenuBarLabelContent's first branch renders the retained number with its normal threshold color whenever metrics are non-empty, regardless of model.state — a green "8%" can be hours old with no cue.

**Evidence.** MenuBarLabelContent.swift:12-19: `if let primary = model.metrics.primary(for: settings.primaryMetric) { ... Text(Format.barLabel(primary)).foregroundStyle(Thresholds.menuBarColor(primary.pct)) }` — no check of model.state in this branch. Contrast: UsagePopover.swift:82-83 `if case .error(let message) = model.state { staleBanner(message) }`; DesktopWidgetView.swift:273-275 `isStale` drives staleChip.

**Recommendation.** When `model.state.isError && !metrics.isEmpty`, add a small stale cue to the bar label (e.g. dim the number to .secondary or append the warning glyph), keeping the value visible per the last-good-cache design.

**Verification.** inline evidence only (P2/P3 — not adversarially re-verified)

#### MB-04 · P2 · Med/Low/S — accessibility — menu bar contrast/color-only

**Observation.** The menu bar number's threshold color is likely an AA failure in light mode and is the ONLY channel encoding severity. 13pt text in systemGreen (#34C759) over a light menu bar computes to roughly 2.2:1 against white (AA requires 4.5:1); orange is similarly weak. Color-blind users get no non-color severity cue in the bar (the popover conveys severity via numbers + reset text, so the bar is the only color-only surface). Live rendering over the translucent bar was not measured.

**Evidence.** MenuBarLabelContent.swift:17-18: `Text(Format.barLabel(primary)).foregroundStyle(Thresholds.menuBarColor(primary.pct))`; Formatting.swift:29-36: `case ..<60: return .green; case ..<85: return .orange; default: return .red`. Computed: systemGreen #34C759 relative luminance ≈0.423 → contrast vs white ≈2.2:1 (< 4.5:1 AA for 13pt).

**Challenges.** Challenges the P2 slice-1 'accessibility pass DONE' record (BACKLOG.md:95): the pass covered popover+widget but not the menu bar label itself, while BACKLOG.md:154 keeps the AA baseline open.

**Recommendation.** Measure on a real light menu bar; if it fails, use darker light-mode variants (e.g. system .green resolves poorly — pick explicit light/dark pairs) or keep the number .primary below 60% (as labelColor already does in the popover) so "comfortable" state isn't low-contrast green.

**Verification.** inline evidence only (P2/P3 — not adversarially re-verified)

#### MB-07 · P2 · Low/Low/S — accessibility — Settings Dynamic Type

**Observation.** SettingsView is excluded from the Dynamic Type work: every label uses raw fixed `.font(.system(size: 10-15))` instead of the `scaledFont` modifier the popover/widget use, and the panel is a fixed 360pt width, so user text-size settings have no effect in Settings. Native controls do give it keyboard/VoiceOver support for free, so this is scaling-only.

**Evidence.** SettingsView.swift:24 `.font(.system(size: 15, weight: .semibold))`, :77 `.font(.system(size: 13))`, :130-131, :201-202, :217 all raw fixed fonts; :65 `.frame(width: 360)`. Compare SharedUI.swift:48-52 `scaledFont` (@ScaledMetric) used throughout UsagePopover/DesktopWidgetView.

**Recommendation.** Swap the fixed fonts to `scaledFont(_:relativeTo:)` (already in the codebase) and let the window size itself (remove or relax the fixed width).

**Verification.** inline evidence only (P2/P3 — not adversarially re-verified)

#### MB-09 · P3 · Low/Med/S — release process — Info.plist version

**Observation.** RELEASE.md's "Bump the version (single source of truth)" checklist omits apps/menubar/Info.plist (CFBundleShortVersionString/CFBundleVersion), and its safety-net grep searches for the old tag with a `v` prefix (`vP.Q.R`), which cannot match Info.plist's plain `0.4.0`. v0.4.0 is currently aligned everywhere (Info.plist 0.4.0/5 = site config 0.4.0 = tag v0.4.0), but the next release can silently ship an app that reports the old version in Finder/Get Info.

**Evidence.** RELEASE.md:74-79: §2 lists only `site/src/config.ts`, `README.md`, and `grep -rIn "vP.Q.R" .`; the v0.4.0 retro note (RELEASE.md:19-20) shows the Info.plist bump was done ad hoc, outside the checklist. apps/menubar/Info.plist:19-22: `CFBundleShortVersionString 0.4.0`, `CFBundleVersion 5`.

**Challenges.** Corrects RELEASE.md §2's "single source of truth" claim — the version actually lives in at least three places (site config, Info.plist, README).

**Recommendation.** Add an explicit §2 checklist line for apps/menubar/Info.plist (both keys), or have build.sh/release.yml stamp the version from the git tag at build time (stronger: one true source).

**Verification.** inline evidence only (P2/P3 — not adversarially re-verified)

#### MB-06 · P3 · Low/Low/S — reliability — rate-limit copy

**Observation.** The rate-limited error copy promises behavior that doesn't exist: "Rate limited — backing off, will retry" is shown, but UsageModel's timer keeps the fixed user-chosen cadence (min 30s) with no error-aware backoff anywhere in the app or core; a persistent 429 is re-hit at full frequency.

**Evidence.** UsageModel.swift:182-183: `case .rateLimited: return "Rate limited — backing off, will retry."`; scheduleTimer (UsageModel.swift:99-108) is a fixed-interval repeating Timer with no error hook; grep for `backoff` across core/Sources returns only the doc-string in ClaudeOAuthProvider.swift:20 — no implementation.

**Recommendation.** Either implement a simple multiplicative backoff on `.rateLimited` (skip N ticks) or change the copy to "Rate limited — will retry at the next refresh."

**Verification.** inline evidence only (P2/P3 — not adversarially re-verified)

#### MB-10 · P3 · Low/Low/S — smoke flags — coverage + docs

**Observation.** The smoke flags exist and are substantive, but the documented list is incomplete and coverage has holes. Flags shipped: --snapshot (all UI states, light/dark, a11y variants), --selftest (live timer reschedule, StubProvider), --metrictest (menu-bar text per metric choice + defaults persistence), --widgettest (12-check NSPanel persistence/recovery suite), --launchtest, --register/--unregister-login-item. apps/menubar/README.md and CLAUDE.md list only four (--widgettest and the login-item flags are undocumented). Nothing headless exercises UsageModel error/stale/needsLogin transitions or ClaudeSession resolution — those states are only rendered by --snapshot, not asserted.

**Evidence.** Main.swift:9-40 (seven modes incl. `--widgettest` L23-26, `--register-login-item` L33-36); apps/menubar/README.md:23-32 documents only `--snapshot/--selftest/--metrictest/--launchtest`; `grep -n widgettest CLAUDE.md feature_list.json` → no matches. SelfTest.swift:20-56 uses StubProvider only; WidgetTest.swift:11-103 asserts frame/displayID persistence + off-screen clamping.

**Recommendation.** Document --widgettest and the login-item flags in the app README/CLAUDE.md; add a small `--statetest` that drives UsageModel through ok→error(stale)→needsLogin→signedOut with a failing stub and asserts state/needsLogin/metrics retention.

**Verification.** inline evidence only (P2/P3 — not adversarially re-verified)

#### MB-11 · P3 · Low/Low/S — UX — manual refresh feedback

**Observation.** The popover's Refresh button gives no feedback once data exists: refreshNow() silently no-ops if a fetch is already in flight, and the loading state is deliberately shown only before first data, so clicking Refresh changes nothing visible until "Updated Xs ago" eventually ticks over.

**Evidence.** UsageModel.swift:126-127: `guard fetchTask == nil else { return }` and `if metrics.isEmpty { state = .loading }`; UsagePopover.swift:165 `Button { model.refreshNow() }` with no busy/progress indication path for the populated state.

**Recommendation.** Briefly spin/disable the refresh icon while fetchTask != nil (expose an `isFetching` published flag) — keeps the no-spinner design for passive loads while acknowledging explicit user action.

**Verification.** inline evidence only (P2/P3 — not adversarially re-verified)

#### MB-12 · P3 · Low/Low/M — accessibility — desktop widget keyboard access

**Observation.** The desktop widget's "Connect Claude" button likely has no keyboard path: the panel is a non-activating NSPanel excluded from window cycling (`.ignoresCycle`), never becomes key except "if needed" on click, so a keyboard-only user cannot tab to the CTA (mouse and VoiceOver-cursor users can; the popover offers an equivalent CTA, which mitigates). Not verified in a live AT session.

**Evidence.** DesktopWidgetController.swift:93 `styleMask: [.nonactivatingPanel, ...]`, :109 `panel.becomesKeyOnlyIfNeeded = true`, :115 `collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]`; DesktopWidgetView.swift:239-241 renders `NeedsAuthView(session:)` (with its Button, SharedUI.swift:143-150) inside that panel.

**Recommendation.** Verify with a live keyboard/VoiceOver session (part of P2 slice 3 anyway); if unreachable, either accept and document popover parity as the keyboard path, or allow the panel to become key on Tab-in.

**Verification.** inline evidence only (P2/P3 — not adversarially re-verified)

**Dimension summary.** apps/menubar is in genuinely good shape for a v1 flagship: all five UX states (loading skeleton, error, empty-ok, needs-auth CTA, stale/last-good) are distinctly rendered in BOTH the popover and the desktop widget via shared components (SharedUI/WidgetRingGauge/WidgetGlass reading one Theme token layer), refresh cadence live-reschedules with a headless proof (--selftest), the NSPanel widget has a real 12-check persistence/recovery test (--widgettest), and the P2 a11y slice is substantive (VoiceOver label/value phrases, footer focus rings, @ScaledMetric Dynamic Type, Reduce Motion/Transparency and Increase Contrast all honored). Info.plist (0.4.0/build 5) matches the advertised v0.4.0 tag, site config, and installer pin. The material gaps found: (1) the site guide documents WRONG gauge thresholds (75/90 vs the app's 60/85) — the one user-facing drift of the duplicated threshold scale; (2) a signed-out app never re-detects a newly added Claude credential (sticky \"Sign in\" until relaunch); (3) the release workflow publishes binaries running zero tests despite the smoke harness existing; (4) the menu bar label shows stale data with no cue and its green threshold text computes to ~2.2:1 on a light bar (color is also the only severity channel there); (5) SettingsView is excluded from Dynamic Type. On the lead: the Theme/threshold duplication is real but its three copies are menubar-Swift, iOS-scaffold-Swift (stale blue palette falsely claiming site lockstep), and the site CSS/guide — and since apps/menubar's UI lives in an SPM executable target (unimportable by any future WidgetKit extension) while that extension and iOS are both frozen/unbuilt, a HoudiniUI library extraction is NOT warranted for v1; fix the two small drifts now and extract only when apps/widget actually gets built. All six assigned pendências (PND-MB-01/03/04/05/06, PND-TEST-04) validated as confirmed; ten new pendências logged, mostly doc drift plus the sticky-auth bug and the unverified release pipeline.


### B3. Periphery — apps/widget + apps/ios

#### PER-02 · P1 · Med/Low/S — apps/widget / root docs

**Observation.** Root docs over-claim the Notification Center widget. ARCHITECTURE.md §'WidgetKit widget — apps/widget' (L65–68) describes concrete runtime behavior ('TimelineProvider reads only the cached value from the App Group', '.after(~15min) policy', 'host app pushes reloadTimelines') with no 'planned/not built' qualifier, and README.md:35 says the widget 'also exists in the repo' — when only a one-line README exists. README.md is internally inconsistent: its own repo-layout tree (L67) correctly says 'placeholder today'. This is the single biggest credibility risk of the two 'dead' app dirs: the harm is docs claiming more than the tree contains, not the dirs existing.

**Evidence.** ARCHITECTURE.md:65-68: '### WidgetKit widget — `apps/widget`\n- `TimelineProvider` reads only the **cached** value from the App Group (cheap reloads).\n- Steady-state `.after(~15min)` policy; host app pushes `reloadTimelines`…' (no status qualifier). README.md:35: 'A glanceable **Notification Center widget** (WidgetKit, `apps/widget`) also exists in the repo' vs README.md:67: 'widget/ ← WidgetKit Notification Center widget (placeholder today; unadvertised)'. Actual tree: one 82-byte README.

**Challenges.** ARCHITECTURE.md as written (doc drift also flagged as PND-DOC-03)

**Recommendation.** Before v1: reword ARCHITECTURE.md L65–68 to design-intent framing ('planned surface, not built; requires the App-Group bridge which is also unbuilt — see PND-MB-02') and change README.md:35 'also exists in the repo' to 'is planned' or 'is reserved in the architecture'. This is required regardless of the keep/delete call in PER-01.

**Verification.** CONFIRMED

#### PER-01 · P2 · Med/Low/S — apps/widget

**Observation.** apps/widget has been a single 82-byte, one-line README ('WidgetKit / Notification Center widget. Glanceable ~15min (Apple limit, ADR-002).') with zero code since the repo's very first commit (2ff830a, 2026-06-16, 'chore: scaffold repo'). The ADR-002 decision record lives in DECISIONS.md, not in this directory, so the dir itself carries no information not already in DECISIONS.md + feature_list.json (which honestly says 'README placeholder today (no built target in tree)').

**Evidence.** `ls -la apps/widget` → one file: `-rw-r--r-- 1 vitorsalomao staff 82 Jun 17 21:54 README.md`; `grep -c '' README.md` → 1 line. `git log --follow -- apps/widget` → single commit `2ff830a 2026-06-16 chore: scaffold repo, docs and structure`. feature_list.json:10: `"status":"planned" ... "apps/widget is a README placeholder today (no built target in tree)"`.

**Recommendation.** V1 call (a): DELETE apps/widget/ for v1 (git history + ADR-002 + feature_list.json fully preserve the anchor), reworded ARCHITECTURE.md section to 'planned'. Trade-off: deleting loses the visible reserved slot and requires touching ARCHITECTURE/README repo-layout; keeping costs 82 bytes but signals vaporware because the in-dir README states no status ('placeholder', 'not built'). Acceptable alternative: keep the dir but grow README.md to an honest status paragraph (status: planned/not built; blocked on the App-Group bridge; see ADR-002). Unacceptable: shipping v1 with the current one-liner while root docs over-claim it (see PER-02).

**Verification.** inline evidence only (P2/P3 — not adversarially re-verified)

#### PER-03 · P2 · Med/Low/S — apps/ios

**Observation.** The iOS scaffold (12 files, ~27 KB) is high quality and currently coherent with the real core: every FetcherCore API it calls exists today (ClaudeAuthResolver.hasSessionCookie/makeProvider(preferCookie:), CredentialStore.nativeWrite/DeleteGenericPassword, ClaudeCookieProvider.keychainService/.keychainAccount, UsageSnapshot/UsageMetric/ProviderError shapes all verified against core sources), the folder docs are unusually honest (README line 1: 'This does not build on this machine'), and it is anchored by ADR-008 + ROADMAP Phase 9. It has never been compiled and cannot be on this machine (CommandLineTools only, no iOS SDK).

**Evidence.** API cross-check: ClaudeAuth.swift:58 `public func hasSessionCookie()`, :73 `public func makeProvider(preferCookie: Bool = false)`; CredentialStore.swift:141/:166 nativeWrite/DeleteGenericPassword; ClaudeCookieProvider.swift:23-24 keychainService/Account — all referenced by UsageViewModel.swift/ClaudeLoginView.swift. `xcrun --sdk iphoneos --show-sdk-path` → 'SDK "iphoneos" cannot be located'; xcode-select -p → /Library/Developer/CommandLineTools. apps/ios/README.md:3: '**This does not build on this machine.**'

**Recommendation.** V1 call (b): KEEP apps/ios in-tree as a scaffold; do not ship it in v1 (impossible: never compiled, needs Xcode + $99 + TestFlight review), do not move to a branch, do not cut. Trade-offs: shipping is not an option at all; a branch guarantees silent rot (core already changed under it once — ClaudeAuth.swift rewritten 2026-07-01 in slice (a) while apps/ios was last touched 2026-06-17; it survived only because API names were kept) and hides ADR-008 rationale; cutting destroys verified-coherent design work for a 27 KB saving. An honestly-labelled scaffold does not hurt OSS credibility — over-claiming docs do (fix PER-04). Root README already labels it 'not yet built — ADR-008' (L68).

**Verification.** inline evidence only (P2/P3 — not adversarially re-verified)

#### PER-04 · P2 · Med/Low/S — apps/ios docs honesty

**Observation.** apps/ios/README.md over-claims verification: 'The core (../../core) **is** already iOS-ready and its macOS build still passes — that part is done and verified.' Only the macOS build was verified; iOS compilation is explicitly an assumption per PLAN.md §5 ('iOS compilation itself can only be *verified in Xcode* … it stays a documented assumption until then'). ROADMAP.md Phase 9 repeats the over-claim with a checkmark: '**FetcherCore iOS-ready** ✅'. The README and PLAN in the same folder contradict each other on the one claim that matters.

**Evidence.** apps/ios/README.md:57-59: 'The core (`../../core`) **is** already iOS-ready and its macOS build still passes — that part is done and verified.' vs apps/ios/PLAN.md:173-177: 'iOS compilation itself can only be *verified in Xcode* (no iOS SDK here), so it stays a documented assumption until then'. ROADMAP.md:47: '- **FetcherCore iOS-ready** ✅ — only macOS-only dep was `Foundation.Process`…'.

**Challenges.** apps/ios/README.md 'done and verified' claim; ROADMAP.md Phase 9 ✅ marker

**Recommendation.** Reword README.md:57-59 to 'iOS-compilable by construction (guards verified, macOS build verified); iOS compile itself unverified — see PLAN §5', and change ROADMAP:47's ✅ to a qualified marker, OR make the claim true cheaply via CI (PER-05). For a project whose brand is 'evidence, not reasoning' (CLAUDE.md), an unverified 'verified' is a direct self-contradiction.

**Verification.** inline evidence only (P2/P3 — not adversarially re-verified)

#### PER-05 · P2 · Med/Low/S — apps/ios / CI

**Observation.** PLAN.md §5 frames iOS compilation of FetcherCore as unverifiable ('no iOS SDK here … documented assumption until then'), but the repo's own CI already has full Xcode: release.yml runs on macos-14 runners that 'ship Xcode 16 / Swift 6' and even does `sudo xcode-select -s`. The $99 Developer Program blocks *distribution*, not *compilation* — a free CI job (`xcodebuild build -scheme FetcherCore -destination 'generic/platform=iOS Simulator'` in core/) would convert the load-bearing assumption into evidence today. My own static verification supports the claim (FetcherCore imports only Foundation+Security; all three Foundation.Process uses are inside #if os(macOS)), but static reading is not a compile.

**Evidence.** .github/workflows/release.yml:10 '# Intel): macos-14 runners are arm64 and ship Xcode 16 / Swift 6', :21 'runs-on: macos-14', :33 'sudo xcode-select -s "$XC"'. core/Package.swift:34 '.iOS(.v17)'. Guards: CredentialStore.swift:56,:70, ClaudeOAuthProvider.swift:141, ClaudeOAuthCredentialSource.swift:201 all `#if os(macOS)`; `grep '^import'` over FetcherCore → only `import Foundation` / `import Security`.

**Challenges.** PLAN.md §5's framing that iOS verification must wait for local Xcode / $99 enrollment

**Recommendation.** Add a small (optionally manual-trigger) CI job on macos-14 that builds the FetcherCore library for an iOS Simulator destination. This settles PND-IOS-04 for ~zero cost, makes ROADMAP's ✅ honest, and protects the scaffold against silent core drift (PER-07) at the data-layer boundary.

**Verification.** inline evidence only (P2/P3 — not adversarially re-verified)

#### PER-06 · P3 · Low/Med/S — apps/ios/project.yml

**Observation.** The XcodeGen spec declares the widget extension as depending on the app: HoudiniWidget has `dependencies: … - target: HoudiniMobile # extension is embedded in the app`. Xcode/XcodeGen convention is the inverse — the APP target depends on (and thereby embeds) the extension into its PlugIns. As specced, `xcodegen generate` would likely produce an app that does not embed the widget (HoudiniMobile has no dependency on HoudiniWidget), wasting the first real Xcode session. Cannot be executed here (xcodegen not installed, no Xcode), so the semantic consequence is asserted from XcodeGen conventions, not a run.

**Evidence.** apps/ios/project.yml:57-59 (HoudiniWidget target): 'dependencies:\n      - package: FetcherCore …\n      - target: HoudiniMobile     # extension is embedded in the app'; HoudiniMobile target (L33-49) lists only the FetcherCore package dependency, no target dependency on HoudiniWidget. `which xcodegen` → not found (claim not executable on this machine).

**Challenges.** project.yml's claim to 'DOCUMENT the iOS target layout' correctly / HoudiniWidget.swift's 'structurally complete' (PND-IOS-05)

**Recommendation.** Flip the dependency: put `- target: HoudiniWidget` under HoudiniMobile's dependencies (XcodeGen embeds app-extension dependencies into the app by default) and drop the app dependency from the widget target. One-line fix; verify on first Xcode session or in the PER-05 CI job.

**Verification.** inline evidence only (P2/P3 — not adversarially re-verified)

#### PER-07 · P3 · Low/Med/M — apps/ios drift risk

**Observation.** Nothing compiles or typechecks the apps/ios sources — no test, no selftest hook, no CI. Core public-API changes therefore invalidate the scaffold silently. This is not hypothetical: ClaudeAuth.swift was rewritten on 2026-07-01 (P1 slice (a), commit d7a2f40) after the scaffold was last touched (2026-06-17, 2ad27b7); the scaffold survived only because slice (a) preserved the resolver API names it calls. The next core rename will break it with zero signal, and 'scaffold that no longer matches core' is worse for credibility than no scaffold.

**Evidence.** git log -- core/Sources/FetcherCore/ClaudeAuth.swift → 'd7a2f40 2026-07-01 feat(core): broaden Claude OAuth discovery + refresh (P1 slice a)'; git log -- apps/ios → last touch '2ad27b7 2026-06-17 refactor: rename Tally → Houdini'. No Tests/ or CI reference to apps/ios anywhere; .github/workflows contains only release.yml (app release on tags).

**Recommendation.** Cheapest: a stated convention in apps/ios/README ('scaffold is compile-checked opportunistically; re-verify API references when core auth changes') plus the PER-05 CI job for the FetcherCore-for-iOS half. Full fix (compile the app/widget targets in CI via xcodegen on the macos-14 runner) is M effort and reasonable post-v1; not required for v1.

**Verification.** inline evidence only (P2/P3 — not adversarially re-verified)

#### PER-08 · P3 · Low/Low/S — apps/ios/HoudiniWidget

**Observation.** Inconsistent pct clamping in the iOS widget scaffold: the Lock Screen path passes unclamped pct into `Gauge(value: pct, in: 0...100)` (HoudiniWidget.swift:76) while the Home Screen path clamps (`min(max(pct, 0), 100)`, :96). ClaudeUsageParser does not clamp — pct is decoded straight from the API's `utilization` field — so an out-of-range value (e.g. >100 during overage) would feed a SwiftUI Gauge outside its declared bounds on the Lock Screen. Placeholder-grade code, but a one-line inconsistency worth fixing whenever the file is next touched.

**Evidence.** HoudiniWidget.swift:76 'Gauge(value: pct, in: 0...100) { EmptyView() }' (no clamp) vs :96 'ProgressView(value: min(max(pct, 0), 100), total: 100)' (clamped). ClaudeUsageParser.swift:117 'pct = try c.decodeIfPresent(Double.self, forKey: .utilization)' — no min/max/clamp anywhere in the parser (grep for 'min(|max(|clamp' → no hits).

**Recommendation.** Clamp once at the `tightest()` helper or reuse the Home Screen clamp on the Gauge line. Runtime behavior of an out-of-bounds SwiftUI Gauge was not executed here (no iOS SDK), so the crash-vs-warn consequence is unverified; the inconsistency itself is verified from source.

**Verification.** inline evidence only (P2/P3 — not adversarially re-verified)

**Dimension summary.** Dimension B3 (apps/widget + apps/ios) audit. apps/widget is confirmed README-only: one 82-byte line, unchanged since the repo's first commit (2026-06-16); all 3 NCW pendências confirmed, including the coupled unbuilt App-Group bridge (zero WidgetCenter/App-Group code in apps/menubar or core). The credibility problem is not the empty dir but the over-claiming root docs: ARCHITECTURE.md L65-68 describes the widget's runtime behavior unqualified, and README.md L35 says it 'exists in the repo' while README L67 admits 'placeholder'. V1 call (a): delete apps/widget (ADR-002 in DECISIONS.md + feature_list.json fully preserve the anchor; git preserves history) or, at minimum, grow its README into an honest status note — and fix the two root-doc over-claims either way (P1). apps/ios is a genuinely high-quality, honestly-documented scaffold: all 6 IOS pendências confirmed; I independently verified every FetcherCore API the scaffold calls exists today, FetcherCore imports only Foundation+Security, and all three Foundation.Process uses are #if os(macOS)-guarded — but it has never been compiled (no Xcode/iOS SDK on this machine, confirmed via xcrun). V1 call (b): keep in-tree as scaffold; shipping is impossible (uncompiled, $99+TestFlight), a branch guarantees silent rot (core auth was already rewritten under it on 2026-07-01 and survived only by luck of preserved API names), and cutting destroys verified-coherent work for 27 KB. Two honesty defects need fixing for v1 polish: apps/ios/README's 'done and verified' and ROADMAP's 'FetcherCore iOS-ready ✅' both contradict PLAN.md §5's own 'documented assumption'. Key challenge to PLAN §5's framing: the iOS compile is cheaply provable TODAY — release.yml already runs on macos-14 runners shipping Xcode 16, so a tiny CI job converts the assumption into evidence; $99 gates distribution, not compilation. Also found: project.yml's widget-embedding dependency appears inverted (extension depends on app instead of app embedding extension), and an unclamped Lock Screen Gauge — both scaffold-grade P3s.


### B4/E2. Site — code, UX, accuracy

#### SITE-01 · P1 · High/Low/S — site/ + repo root — legal accuracy of the 'open source' claim

**Observation.** The site claims 'free & open source' in at least five places (index.astro:120 'free & open source', install.astro:62, faq config 'Houdini is free and open-source', privacy.astro points[3] 'Open source, end to end', index trust chip 'Open source'), but the repository contains NO license file of any kind, so the code is legally all-rights-reserved — source-visible, not open source.

**Evidence.** find maxdepth 2 -iname '*license*' -o -iname 'COPYING*' → exit 1 (no matches); grep -i 'license|MIT|GPL|Apache' README.md → no license mention; GitHub API repos/vitorsalomao05/houdini → "license": null, "private": false. Site: site/src/pages/index.astro:120 'macOS 14+ · Apple Silicon · free &amp; open source'; site/src/config.ts:123 'Houdini is free and open-source. Read every line before you run it'.

**Recommendation.** Add a LICENSE file (MIT or Apache-2.0 fits the posture) at the repo root and reference it from README. Until then the 'open source' claim on every page is legally false — this is a one-file fix that closes a real trust/legal gap. Also aligns with CLAUDE.md's own guardrail 'Free & open source.'

**Verification.** CONFIRMED

#### SITE-02 · P1 · High/Low/S — /reveals — capability accuracy (Tokens)

**Observation.** /reveals advertises 'Tokens' as one of four things Houdini reveals ('How much you've burned through each window, kept current to the minute'), renders a 1.24M-token panel captioned 'Illustrative sample · live in the app every 60s', and the page meta says 'tokens burned … refreshed every 60 seconds' — but the shipped product has no token metric at all: core Capabilities are only usagePct/resetTimer/dollarBalance and ClaudeUsageParser emits only percent windows + reset times + extra-usage dollars. Live in production (grep on fetched houdini.salomao.org/reveals confirms '1.24M').

**Evidence.** site/src/config.ts:74-77 'Tokens … How much you've burned through each window, kept current to the minute'; site/src/pages/reveals.astro:130 '1.24M', :140 'tokens, kept current to the minute', :83 'live in the app every 60s'. vs core/Sources/FetcherCore/Models.swift:19-21 (usagePct/resetTimer/dollarBalance only) and ClaudeUsageParser.swift:43-64 (labels: 5-hour, Weekly, Opus weekly, Sonnet weekly, Extra usage ($) — no token counts). Live: grep '1.24M' live-reveals.html → match.

**Challenges.** config.ts reveals comment 'No status badges — co-equal, glanceable' — co-equal presentation is wrong while one of the four dimensions doesn't exist; revises the reveals content model, and is a live counterexample to BACKLOG's claim that the site is ADR-honest.

**Recommendation.** Remove the Tokens tab from /reveals (and the reveals config entry) or rescope it to what exists (e.g. fold into 'Limits'). This violates ADR-010's no-vaporware rule ('a surface is either real and shown, or absent') and directly contradicts the site's own FAQ promise 'it never shows a gauge it can't honestly fill'. If tokens are the planned OpenAI-adapter UX (ADR-011), they belong on the site only when that adapter ships.

**Verification.** CONFIRMED

#### SITE-03 · P1 · Med/Med/S — /faq + /install + /guide — cookie-login accuracy

**Observation.** The non-CLI login copy claims a one-time login: FAQ 'you sign in to claude.ai once … no repeated logins', /install 'sign in to claude.ai once … The session is stored in your Keychain and reused — no repeated logins, no secret to paste', /guide option B same. The Keychain-storage part is true, but the project's own root-cause analysis says the captured cookie is short-lived and non-refreshable, producing a 're-login loop on expiry' — and the fix (cookie hardening) is frozen by ADR-012. 'Once' and 'no repeated logins' oversell to exactly the audience this copy targets.

**Evidence.** site/src/config.ts:107 'a claude.ai session you grant once', :115 'no repeated logins'; install.astro:140-145; guide.astro:240-244. vs BACKLOG.md:44-46 'Root cause B: the cookie WebView uses an ephemeral store … the captured cookie is short-lived and non-refreshable → re-login loop on expiry' and BACKLOG.md:58-66 (hardening (b) 'not pursued', ADR-012). Cookie IS Keychain-kept: ClaudeCookieProvider.swift:23 keychainService="Houdini-claude-session".

**Recommendation.** Soften the claim to match frozen reality: e.g. 'sign in to claude.ai in a native window; the session is kept in your Keychain and reused until it expires — you'll be asked to sign in again when it does.' Since ADR-012 froze the technical fix, the copy must move instead; today the site promises behavior the code cannot deliver.

**Verification.** CORRECTED (score → P1 (impact Med, risk Med, effort S) — unchanged; the original scoring is fair)

#### SITE-04 · P1 · Med/Low/S — /guide — gauge threshold legend contradicts the shipped app

**Observation.** The guide's 'Reading the gauges' legend teaches 0–74% green / 75–89% amber / 90–100% red, but the app colors <60% green, 60–85% amber, >85% red. The site is also internally inconsistent: /reveals and /surfaces render a 72% gauge in amber (matching the app) while the guide's own legend says 72% should be green. The wrong legend is live in production.

**Evidence.** site/src/pages/guide.astro:28-30 ranges '0–74%', '75–89%', '90–100%' vs apps/menubar/Sources/Houdini/Formatting.swift:4-12 '/// Threshold colors: <60% normal, 60–85% amber, >85% red. … case ..<60: return .green; case ..<85: return .orange; default: .red'. Internal contradiction: reveals.astro:13 '{ label: "Weekly", pct: 72, bar: "bg-warn" }' (amber at 72%). Live: grep live-guide.html → '0–74% / 75–89% / 90–100%' present.

**Recommendation.** Pick one scale and align both surfaces. Either fix the guide legend to 0–59 / 60–84 / 85–100 (matches shipped app, S effort), or change the app thresholds to 75/90 if that is the intended product language — but decide once; today the teaching page trains users to expect amber 15 points later than the app shows it.

**Verification.** CONFIRMED

#### SITE-05 · P2 · Med/Low/S — index hero — 'Nothing leaves your Mac' precision

**Observation.** The hero says 'No account, no server. Nothing leaves your Mac.' and the one-liner reassurance repeats 'nothing leaves your Mac' — but the site's own /privacy and /guide correctly document that one request, signed with your credential, leaves your Mac for the provider's endpoint ('Leaves your Mac: One request, straight to your provider's own endpoint'). The shorthand literally contradicts the accurate pages; the deferred 'Mac → Anthropic, no Houdini server' trust sentence (BACKLOG decision) would resolve this by saying precisely what does leave.

**Evidence.** site/src/pages/index.astro:97-98 'No account, no server. Nothing leaves your Mac.', :108 'nothing leaves your Mac' vs guide.astro:399-406 'Leaves your Mac · One request, straight to your provider's own endpoint · Signed with your own credential' and privacy.astro:20 'Requests go straight from your Mac to each provider's own endpoint'. BACKLOG.md P3: trust line 'decided: DEFERRED'.

**Challenges.** BACKLOG P3 'Explicit Mac → Anthropic trust line — DEFERRED' — the deferral is challenged because the current shorthand is not merely implicit but contradicts the site's own privacy page.

**Recommendation.** Replace the landing shorthand with the precise version, e.g. 'No account, no server — your Mac talks only to your provider.' It is one sentence, more accurate, arguably stronger as a trust claim, and reconciles the landing page with /privacy. This makes the DEFERRED decision worth revisiting: the deferral leaves an internal contradiction live, not just an omission.

**Verification.** inline evidence only (P2/P3 — not adversarially re-verified)

#### SITE-06 · P2 · Med/Low/S — sub-pages — a11y regressions the landing-only fix missed

**Observation.** Commit 78e2bf3 fixed the landing page's contrast issues (footer lifted to muted/90 ≈5.6:1, terminal label lifted to #9d7bf7) but only touched CopyBlock/Footer/index. Sub-pages retain the same failure classes: /reveals has a 12px font-mono line at text-muted/70 ≈3.6–3.8:1 (below AA 4.5:1) — the exact ratio the audit failed the old footer for; every sub-page eyebrow/label uses #8b5cf6 at 12px ≈4.65:1 (the borderline the audit said to lift, and did lift on the landing only); and six 11px chips (text-[11px] 'Live'/'Built in') sit below even the 12px floor the audit flagged.

**Evidence.** git show --stat 78e2bf3 → only CopyBlock.astro, Footer.astro, index.astro. reveals.astro:83 'font-mono text-xs text-muted/70' ('Illustrative sample…'); #9a93b0@70% over ~#0b0a10 blend ≈3.8:1 (computed). index.astro:103 uses lifted 'text-[#9d7bf7]' but SectionHeader.astro eyebrow + install.astro:42,250 + guide.astro:50 keep 'text-accent' (#8b5cf6 ≈4.65:1 at 12px). grep text-[11px] → guide.astro:164,175,186,196,223 + install.astro:217 (6 instances).

**Recommendation.** Apply the landing-page fixes site-wide: bump /reveals muted/70 to muted (≈6.7:1) or 13px; lift the shared eyebrow token to the same #9d7bf7 used on the landing (or add a --color-accent-text token); raise the 11px chips to 12–13px. All are class-level edits; the shared SectionHeader makes the eyebrow fix a one-component change.

**Verification.** inline evidence only (P2/P3 — not adversarially re-verified)

#### SITE-07 · P2 · Med/Low/S — /guide — API-usage copy in present tense for an unbuilt capability

**Observation.** The guide's 'Who it's for' card addresses 'People paying per API call' ('watch the dollars and tokens add up in real time') and the Subscription-vs-API table states in present tense 'Houdini shows: $ spent this period + token counts' — but no API provider exists (OpenAI Platform / Anthropic Console adapters are specced, not built, per PROVIDERS.md and ADR-011 'not built in this round'). One hedge exists ('your Claude subscription is revealed there today') but the audience card and table row read as current capability.

**Evidence.** guide.astro:144-148 'People paying per API call … watch the dollars and tokens add up in real time'; guide.astro:352-356 row 'Houdini shows … $ spent this period + token counts'. vs DECISIONS.md ADR-011 'The switcher and the OpenAI adapter are not built in this round'; core has only ClaudeOAuthProvider + ClaudeCookieProvider (ls core/Sources/FetcherCore/). Partial hedge at guide.astro:367-372.

**Recommendation.** Reframe the API column/audience as forward-looking ('built to speak both; API tracking arrives with the first API provider') or cut the audience card until an API adapter ships. ADR-010's no-vaporware rule applies to copy as much as UI chrome; same root as SITE-02 but lower severity because the table's closing line partially hedges.

**Verification.** inline evidence only (P2/P3 — not adversarially re-verified)

#### SITE-08 · P3 · Low/Low/S — /surfaces — undisclosed mock UI next to a 'Live' chip

**Observation.** The /surfaces Menu-bar tab renders a fabricated WindowFrame with made-up gauges (34/72/91%) directly beside a 'Live · every 60s' chip, with no 'Illustrative sample' disclaimer — while /reveals labels its identical mock panels 'Illustrative sample · live in the app every 60s' and the Desktop-widget tab uses a real screenshot. A visitor can reasonably read the mock as a product screenshot.

**Evidence.** surfaces.astro:9-13 hardcoded gauges '{ label: "5-hour", pct: 34 … pct: 72 … pct: 91 }'; :82-84 chip 'Live · every 60s' beside the mock WindowFrame (:88-104); no illustrative caption on this page (grep 'Illustrative' surfaces.astro → none) vs reveals.astro:83-85 which has one.

**Recommendation.** Add the same 'Illustrative sample' micro-caption under the /surfaces mock, or swap it for the real popover screenshot already used on / and /guide (which also removes one hand-maintained mock).

**Verification.** inline evidence only (P2/P3 — not adversarially re-verified)

#### SITE-09 · P3 · Low/Low/S — site/src — dead assets and dead config

**Observation.** site/src/assets/popover-light.png is imported nowhere (the site is dark-only, meta color-scheme dark), and the reveals config carries an `icon` field per entry whose comment says it 'maps to an inline SVG path in Reveals.astro' — no such component exists and reveals.astro never reads `.icon`. There is also no custom 404 page (live /nonexistent returns Vercel's default 404, off-brand and without site nav).

**Evidence.** grep -rn 'popover-light' site/src → no matches; config.ts:60-61 comment '`icon` maps to an inline SVG path in Reveals.astro' + icon: fields at :66,71,76,81; grep '.icon' reveals.astro → not used; no src/pages/404.astro; curl -s -o /dev/null -w '%{http_code}' https://houdini.salomao.org/nonexistent → 404 (default page).

**Recommendation.** Delete popover-light.png, drop the icon fields + stale comment from config.ts, and add a minimal branded 404.astro (Astro picks it up automatically; Vercel serves it for static sites). All zero-risk hygiene consistent with the zero-clutter posture.

**Verification.** inline evidence only (P2/P3 — not adversarially re-verified)

#### SITE-10 · P3 · Low/Low/S — index hero — coherence of the 'KEEP GENERIC H1' decision

**Observation.** The decision to keep the H1 generic ('See your AI usage and spend') for ADR-012 low-profile reasons is incoherent with the rest of the same viewport: a pulsing badge says 'Live for Claude Pro · Max' directly above the H1, the paragraph opens 'Your Claude limits, reset timers…', the meta description names Claude, and the FAQ names Claude Code. The generic H1 buys no ToS cover while costing the pitch clarity the 2026-07-01 audit flagged as [P1].

**Evidence.** index.astro:83 'Live for Claude Pro · Max' (animated ping badge), :91-93 H1 'See your AI usage and spend, revealed.', :96 'Your Claude limits, reset timers, and extra-usage dollars', :133 'Built for Claude'; config.ts:19 description 'Your Claude limits…'. BACKLOG P3: 'Hero H1 — decided: KEEP GENERIC ("AI usage", per ADR-012's low-profile posture)'.

**Challenges.** BACKLOG P3 sub-task 'Hero H1 — decided: KEEP GENERIC' (an application of ADR-012, not ADR-012 itself) — challenged as internally inconsistent given the surrounding Claude-explicit copy.

**Recommendation.** Make the posture consistent either way: if low-profile matters, the Claude-naming badge and body copy already defeat it, so sharpening the H1 (audit's original recommendation) adds no incremental ToS exposure; if low-profile is real, the badge and 'Built for Claude' line should soften too. Revisit the KEEP-GENERIC decision with this evidence — as applied, it changed the one element that mattered least.

**Verification.** inline evidence only (P2/P3 — not adversarially re-verified)

**Dimension summary.** Audited site/src in full (7 pages, 8 components, config, styles, layout) plus the live production site, and validated PND-SITE-01..08 (7 confirmed, 1 corrected — the dual-nav 'same links' claim is wrong at the accessibility-tree level). The site's install/integrity claims all check out against the repo: the one-liner URL resolves (HTTP 200 at the pinned tag), v0.4.0 is consistent across config.ts, install.sh TAG, the latest GitHub release, and the live version chip; SHA-256 verification, no-sudo, quarantine-strip/no-Gatekeeper, and offer-never-force launch-at-login all match install.sh; 'ad-hoc signed, hardened runtime' matches build.sh:38; the 60s default, widget drag/resize, and menu-bar pinning claims match the app code; and the deployed site is in sync with site/src (distinctive strings verified on all routes). A11y fundamentals in code are genuinely strong (skip link, global :focus-visible, APG tabs with roving tabindex, stepper live regions + focus management, thorough reduced-motion coverage, no-JS fallbacks). The serious problems are accuracy, concentrated on the sub-pages the 2026-07-01 audit never covered: (1) the repo has NO LICENSE while the site claims 'free & open source' five times (GitHub reports license:null) — P1; (2) /reveals advertises a 'Tokens' capability that does not exist in the core data model, against ADR-010 and the FAQ's own honesty promise — P1; (3) /guide's gauge legend (75/90 cutoffs) contradicts the shipped app (60/85), and /reveals' own 72%-amber sample contradicts the legend — P1; (4) the cookie-login copy promises 'sign in once / no repeated logins' while the project's own analysis documents a re-login loop on expiry with the fix frozen by ADR-012 — P1; plus P2s: the hero's 'Nothing leaves your Mac' contradicts /privacy's accurate 'one request leaves', sub-page contrast/size debt (a real AA fail at 12px muted/70 on /reveals, 11px chips, un-lifted #8b5cf6 eyebrows), and present-tense API-tracking copy. ADR-010/011 compliance on /surfaces content is good (one app, both built in, no separate branding); the residual two-product smell is only the plural 'Surfaces' nav label. Two decisions are challenged with evidence: the KEEP-GENERIC hero H1 (incoherent next to the 'Live for Claude Pro · Max' badge) and the DEFERRED trust sentence (the deferral leaves a live self-contradiction, not just an omission).


### D/G. Flows — installer, scripts, release

#### INS-01 · P1 · High/Med/M — release CI (.github/workflows/release.yml)

**Observation.** The release CI has NEVER produced a release: all 4 tag-push runs of 'Release Houdini' (v0.2.0 x2, v0.3.0, v0.4.0) completed 'failure'. v0.3.0 and v0.4.0 both die compiling apps/menubar/Sources/Houdini/WidgetGlass.swift because `.glassEffect` requires the macOS 26 SDK, while release.yml pins `runs-on: macos-14` (Xcode 16.2). The API is runtime-guarded (`#available(macOS 26, *)`) so the app runs on macOS 14+, but it cannot COMPILE on the pinned runner. Every shipped release was built manually on the dev machine (RELEASE.md: 'Built artifacts (CommandLineTools)... gh release create'). Three docs present this workflow as the release automation (CLAUDE.md repo map, scripts/init.sh:91, scripts/README.md).

**Evidence.** gh run list: 'completed failure chore(release): point install to v0.4.0 Release Houdini v0.4.0 push 27843765926' (same for v0.3.0, v0.2.0 x2; zero successes). Run 27843765926 log: 'Using /Applications/Xcode_16.2.0.app' then 'WidgetGlass.swift:149:25: error: value of type Color has no member glassEffect'. release.yml:21 'runs-on: macos-14'. WidgetGlass.swift:149-151 'else if #available(macOS 26, *) { Color.clear.glassEffect(in: shape)'. RELEASE.md v0.4.0 step 3: 'Built artifacts (CommandLineTools), tagged v0.4.0... published gh release create'.

**Challenges.** CLAUDE.md survey claim 'release CI is .github/workflows/release.yml' — the CI exists but has never worked; the de-facto release process is manual.

**Recommendation.** Pick exactly ONE publish path. Either (a) fix CI — move to a runner image with Xcode 26 (macos-26/latest arm64) and make the workflow the sole publisher — or (b) delete/disable release.yml and document the manual RELEASE.md flow as the truth. Today the workflow burns a failed run on every release and falsifies CLAUDE.md, init.sh:91, and scripts/README.md.

**Verification.** CONFIRMED

#### INS-03 · P1 · High/High/S — single-version prune policy (ADR-010 / RELEASE.md §5)

**Observation.** The prune-every-old-release policy has three concrete costs, one already empirically true: (a) any saved copy of the advertised one-liner 404s after the next release — the previous tag's raw install.sh URL is already dead; (b) rollback is impossible: when v0.5.0 ships, v0.4.0's assets and tag are deleted everywhere, so a broken v0.5.0 leaves ZERO installable version (a local rebuild would not match the recorded checksums, since Swift builds are not byte-reproducible across toolchains); (c) the planned P4 `houdini update <version>` can only ever mean 'latest' — downgrade is structurally impossible. ADR-006's claim that 'the pinned one-liner never points at a dead artifact' is false for any copy not re-fetched from the site/README.

**Evidence.** curl -s -o /dev/null -w '%{http_code}' https://raw.githubusercontent.com/vitorsalomao05/houdini/v0.3.0/install.sh → 404 (v0.4.0 → 200). gh release list → only 'Houdini v0.4.0'. git tag -l → only v0.4.0. RELEASE.md:94 'gh release delete vP.Q.R --yes --cleanup-tag (deletes release and remote tag)'. DECISIONS.md:30 (ADR-006): 're-fetching install.sh from the current tag means the pinned one-liner never points at a dead artifact'. ADR-010 trade-off: 'Deleting old tags breaks any deep-link to a retired release (accepted — the user base is ~0…)'.

**Challenges.** ADR-010 (prune rule) and ADR-006 (the 'never points at a dead artifact' claim); RELEASE.md §5.

**Recommendation.** Revise ADR-010: keep superseded releases (mark them pre-release or retitle 'superseded — do not install') and keep tags; delete nothing. 'One advertised version' only requires the site/README/one-liner to point at one version — erasing history buys almost nothing while costing rollback safety, downgrade capability (needed before P4 ships), and pinned-URL stability. If deletion stays, at minimum record 'no rollback exists' as an accepted risk in ADR-010 and correct ADR-006's 'never points at a dead artifact' sentence.

**Verification.** CORRECTED (score → P1 (impact High if a broken release ever ships, risk Med — not High: user base ~)

#### INS-02 · P2 · Med/Med/S — release publishing (dual paths)

**Observation.** Two independent publishers exist for the same tag: the manual `gh release create` from RELEASE.md and release.yml's `gh release create "$TAG"` on tag push. For v0.4.0 the manual release was created 4 seconds BEFORE the CI run started on the same tag. Today CI fails at compile so the race is latent, but if INS-01 is ever fixed without removing one path, whichever publisher wins determines the shipped binaries — and CI-built binaries (different toolchain) would carry different SHA-256s than the checksums recorded in RELEASE.md, while the loser errors out with 'release already exists'.

**Evidence.** release.yml:86 'gh release create "$TAG"' triggered 'on: push: tags: v*.*.*' (release.yml:11-14). gh release view v0.4.0: created 2026-06-19T19:04:53Z; gh run list: CI run 27843765926 for tag v0.4.0 started 2026-06-19T19:04:57Z. RELEASE.md:28-29: manual 'gh release create v0.4.0 with Houdini.app.zip, houdini, SHASUMS256.txt'; RELEASE.md:38-39 records exact checksums 0235f256… / 1d17035e… (match the published SHASUMS256.txt, verified by download).

**Recommendation.** Resolve together with INS-01: exactly one of {manual flow, CI workflow} may own `gh release create`. If CI becomes the publisher, RELEASE.md's build/publish steps become 'push the tag, wait for the run, verify checksums'.

**Verification.** inline evidence only (P2/P3 — not adversarially re-verified)

#### INS-04 · P2 · Med/Med/M — install.sh security model

**Observation.** The SHA-256 verification is integrity-only, not authenticity: SHASUMS256.txt is downloaded from the exact same release, over the same channel, as the assets it verifies — an attacker who can replace the assets (compromised GitHub account/release) replaces the checksum file too. The app is ad-hoc signed (no identity), so there is no second trust anchor. install.sh's success message ('these are the exact bytes published in $TAG') is technically true but implies more than the check delivers; the pinned-tag rationale (install.sh:16-18) would only confer authenticity if the expected checksums were embedded in the tagged script — and the prune policy deletes tags anyway (INS-03), further weakening the pin.

**Evidence.** install.sh:85-87: fetch "SHASUMS256.txt"; fetch "Houdini.app.zip"; fetch "houdini" — all from $REL (same release). install.sh:75-82 verify() checks only against that just-downloaded file. install.sh:92 'checksums match — these are the exact bytes published in $TAG'. apps/menubar/build.sh:37-38 'codesign (ad-hoc, hardened runtime)… codesign --force --options runtime --sign -'.

**Recommendation.** Embed the expected asset SHA-256s in install.sh at release time (order: build → checksum → commit install.sh with checksums → tag → publish), so the pinned script itself authenticates the downloads. Otherwise, keep the check but soften the claim to corruption/truncation protection. Notarization (ADR-006 future option) is the long-term authenticity fix.

**Verification.** inline evidence only (P2/P3 — not adversarially re-verified)

#### INS-05 · P2 · Med/Med/S — install.sh upgrade/failure behavior

**Observation.** install.sh deletes the existing app with `rm -rf "$APP"` BEFORE extracting the new one, and contains no step to quit a running Houdini instance (zero hits for pkill/osascript/quit). Two failure modes: (1) if extraction fails after the rm (e.g. disk full — checksums were verified, so corruption is excluded), the user is left with no app installed; (2) re-running while Houdini is running leaves the old process executing from a deleted bundle while `open` launches the new copy — the 'idempotent (safe to re-run)' claim was only validated in an isolated $HOME where no instance was running (RELEASE.md:36).

**Evidence.** install.sh:97-98: 'rm -rf "$APP"' then 'ditto -x -k "$TMP/Houdini.app.zip" "$APP_DIR"'; install.sh:99 dies if extraction failed (after the old app is already gone). grep -c 'pkill|osascript|quit' install.sh → 0. install.sh:14 'Is idempotent (safe to re-run)'. RELEASE.md:36-37: 'Install validated against the published v0.4.0 tag in an isolated HOME… idempotent re-run.'

**Recommendation.** Extract into $TMP first and swap atomically (`ditto` to $TMP, then rm+mv, or `mv` old aside and restore on failure); before replacing, detect a running instance and quit it (osascript 'quit app "Houdini"') or at least warn. This also becomes a prerequisite for the P4 self-updater, which will hit the running-app case every time.

**Verification.** inline evidence only (P2/P3 — not adversarially re-verified)

#### INS-06 · P2 · Med/Low/M — release process (RELEASE.md checklist vs ADR-010)

**Observation.** ADR-010 asserts the release is atomic — 'the bump+publish+prune steps are scripted to run as one unit' — but no such script exists: scripts/ contains only init.sh (+ a stale README), and RELEASE.md is a manual checkbox list. The checklist also commits and pushes the version bump (README one-liner, site config, install.sh TAG → vX.Y.Z) in §2 before the tag/release exists in §4, so during that window the advertised one-liner 404s (raw URL is tag-addressed) and an install.sh fetched from master dies at fetch. The version is hand-pinned in at least 4 files, synced only by a grep step.

**Evidence.** DECISIONS.md ADR-010 trade-off: 'an interrupted release can briefly leave the repo between versions, so the bump+publish+prune steps are scripted to run as one unit.' ls scripts/ → README.md, init.sh (nothing else). RELEASE.md §2 (bump+commit) precedes §4 'git tag vX.Y.Z && git push… gh release create'. Pins: install.sh:29 TAG="v0.4.0"; site/src/config.ts:8,12 version/installTag; README.md:17,21.

**Challenges.** ADR-010's factual claim that the release steps 'are scripted' — they are not.

**Recommendation.** Write the release script ADR-010 already promises (single command: bump all pins → build → checksum → commit → tag → publish → prune/mark-superseded → verify), or revise ADR-010's wording to say the steps are a manual checklist. The script also closes the mid-release 404 window by making it seconds long and non-forgettable.

**Verification.** inline evidence only (P2/P3 — not adversarially re-verified)

#### INS-07 · P3 · Low/Low/S — scripts/README.md

**Observation.** scripts/README.md describes the directory as holding 'Sign/notarize, install.sh, release automation' — none of which is there: the only script is init.sh, install.sh lives at the repo root, there is no sign/notarize tooling anywhere (notarization was explicitly deferred by revised ADR-006), and release automation lives (broken) in .github/workflows/release.yml.

**Evidence.** cat scripts/README.md → entire content: 'Sign/notarize, install.sh, release automation. See ../DECISIONS.md ADR-006.' ls scripts/ → README.md, init.sh only. install.sh at repo root (install.sh:1). DECISIONS.md:27-32 (ADR-006 revised): notarized DMG/Sparkle 'remain a documented future option'.

**Recommendation.** Rewrite scripts/README.md to describe what is actually there (init.sh bootstrap) and point to RELEASE.md + release.yml for the release flow.

**Verification.** inline evidence only (P2/P3 — not adversarially re-verified)

#### INS-08 · P3 · Low/Low/S — scripts/init.sh

**Observation.** init.sh is functionally correct (toolchain probes, repo map, real build commands, BACKLOG teaser awk all match the repo), but line 91 tells newcomers that a tag push 'triggers .github/workflows/release.yml -> builds, checksums, publishes the Release' — the trigger is real, yet the workflow has failed on all 4 tag pushes ever made and has never published anything; all shipped releases were manual.

**Evidence.** scripts/init.sh:91: 'A tag push (v*.*.*) triggers .github/workflows/release.yml -> builds, checksums, publishes the Release.' gh run list: 4/4 'Release Houdini' runs 'completed failure' (v0.2.0 x2, v0.3.0, v0.4.0); gh release view v0.4.0 assets uploaded by the manual flow (RELEASE.md:28-29).

**Recommendation.** Reword line 91 once INS-01 is resolved (either 'CI publishes the release' when fixed, or 'releases are manual per RELEASE.md; the workflow is currently broken/removed').

**Verification.** inline evidence only (P2/P3 — not adversarially re-verified)

#### INS-09 · P3 · Low/Low/S — install.sh advertised guarantees (verification pass)

**Observation.** Positive result: the advertised installer guarantees all hold in code. Preflight refuses non-macOS, non-arm64, and macOS <14 BEFORE any download; downloads are HTTPS-pinned TLS1.2+ and curl -f aborts on HTTP errors/partial transfers; checksum verification (with a missing-entry count check) runs before anything is installed and aborts on mismatch; the script contains no sudo; quarantine is stripped defensively for the ad-hoc-signed, hardened-runtime app; launch-at-login is strictly opt-in via /dev/tty prompt and defaults to No when no terminal exists. The published SHASUMS256.txt matches RELEASE.md's recorded v0.4.0 checksums byte-for-byte.

**Evidence.** install.sh:62-65 (Darwin/arm64/OS_MAJOR>=14 dies pre-download); :74 'curl -fSL --proto =https --tlsv1.2 … || die'; :78-81 verify with wc -l entry count + 'checksum mismatch — refusing to install'; grep sudo install.sh → 0 hits; :102 'xattr -dr com.apple.quarantine'; :48-58 ask() defaults No without TTY; build.sh:38 'codesign --force --options runtime --sign -'. Downloaded SHASUMS256.txt: 0235f256…  Houdini.app.zip / 1d17035e…  houdini == RELEASE.md:38-39.

**Recommendation.** No code change needed; add a post-publish checklist line comparing the uploaded SHASUMS256.txt to the locally recorded checksums (already done informally in RELEASE.md v0.4.0) so this stays true. Caveats that DO need action are tracked separately: authenticity limits (INS-04) and the rm-rf/running-app gap (INS-05).

**Verification.** inline evidence only (P2/P3 — not adversarially re-verified)

**Dimension summary.** Dimension D/G (installer/scripts/release) audited read-only with live GitHub evidence. First, refuting the earlier scaffold lead: RELEASE.md DOES exist (repo root, 116 lines) and its v0.4.0 record is accurate — the published SHASUMS256.txt matches its recorded checksums byte-for-byte, and gh confirms exactly one release/tag (v0.4.0) as the single-version policy dictates. install.sh's advertised guarantees verify TRUE in code (preflight before download, TLS-pinned fetch, pre-install checksum abort, zero sudo, defensive quarantine strip on an ad-hoc+hardened-runtime-signed app, strictly opt-in login item) — INS-09. The two headline problems: (1) INS-01/INS-02 — the release CI (release.yml) has NEVER succeeded: all 4 tag-push runs failed, v0.3.0/v0.4.0 at compile because `.glassEffect` needs the macOS 26 SDK while the workflow pins macos-14/Xcode 16.2; every real release was manual, three docs falsely present CI as the release automation, and if the compile break is ever fixed the workflow's `gh release create` races the manual publish on the same tag with different binaries/checksums. (2) INS-03 — the ADR-010 prune policy's costs are real and partly already realized: raw v0.3.0 install.sh 404s today (any saved one-liner dies each release, falsifying ADR-006's 'never points at a dead artifact'), rollback after a bad release is impossible (no installable previous version exists anywhere), and P4 `houdini update <version>` downgrade is structurally impossible. Secondary findings: integrity-only checksum model (INS-04), rm-rf-before-extract with no running-app quit (INS-05), ADR-010 falsely claims the release steps 'are scripted' (INS-06), stale scripts/README.md (INS-07) and init.sh:91 CI overstatement (INS-08). All 5 assigned pendências (PND-REL-01..04, PND-TEST-05) are confirmed — PND-TEST-05 is understated (no CI runs on master at all; the only CI has never passed). Seven new pendências added; the inventory's installer section had missed the broken CI entirely.


### H. Documentation accuracy

#### DOC-01 · P1 · High/Med/S — ARCHITECTURE.md + PROVIDERS.md vs core

**Observation.** ARCHITECTURE.md and PROVIDERS.md describe FetcherCore components 'Scheduler (per-provider interval, jitter, exponential backoff on 401/403/429)' and 'Cache (last-good value)' that do not exist anywhere in core/. Scheduling is a plain fixed-interval Timer in the app (apps/menubar UsageModel) and 'last-good' is an ad-hoc keep in the same file. The app's rate-limit UI string even claims 'backing off, will retry' — no backoff logic exists anywhere.

**Evidence.** ARCHITECTURE.md:16-17 'Scheduler (per-provider interval, backoff) / Cache (last-good value…)'; :42 'jitter, exponential backoff on 401/403/429'. PROVIDERS.md:37 'Scheduler (interval + jitter + backoff), Cache (last-good value)'. core/Sources/FetcherCore contains only 9 files (no Scheduler/Cache); `grep -rni 'scheduler|backoff|jitter|lastGood' core/Sources` → 0 hits. apps/menubar/.../UsageModel.swift:100 fixed `Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true)`; :140 '// Last-good cache: keep metrics'; :184 '"Rate limited — backing off, will retry."'

**Recommendation.** Rewrite the FetcherCore component list in ARCHITECTURE.md and PROVIDERS.md:37 to what exists (CredentialStore, providers, parser, models; scheduling+last-good live in the app's UsageModel), or actually implement backoff in core. Independently fix the false 'backing off' user-facing string in UsageModel.swift:184 (it retries at the same fixed interval).

**Verification.** CONFIRMED

#### DOC-02 · P1 · High/Med/S — ARCHITECTURE.md / ROADMAP.md vs apps/menubar + apps/widget

**Observation.** ARCHITECTURE.md's diagram and prose (and ROADMAP Phase 2) state the menu bar app 'writes value to App Group + WidgetCenter.reloadTimelines()' and describe a working WidgetKit widget; neither exists. No WidgetCenter call or App-Group snapshot write exists in apps/menubar, and apps/widget is a one-line README with no Swift target.

**Evidence.** ARCHITECTURE.md:32-33 'writes value to App Group + WidgetCenter.reloadTimelines()'; :50 'Writes latest value into the App Group container and calls WidgetCenter.shared.reloadAllTimelines()'; :65-68 WidgetKit section. ROADMAP.md Phase 2: 'Writes to App Group + reloadTimelines()'. `grep -rn WidgetCenter apps/` → hits only in apps/ios. `ls apps/widget` → README.md only; content is one line: 'WidgetKit / Notification Center widget. Glanceable ~15min…'

**Recommendation.** Mark the App-Group bridge and WidgetKit widget as NOT BUILT in ARCHITECTURE.md (diagram + §Components) and ROADMAP Phase 2/4 — the app's own README (apps/menubar/README.md 'Not in this phase') is currently the only honest doc. For an open-source project selling auditability, the architecture doc must not describe fictional data flows.

**Verification.** CORRECTED (score → P1 (impact High, risk Med, effort S) — unchanged; the claimed priority is fair)

#### DOC-03 · P1 · Med/Med/S — CLAUDE.md + CONTEXT.md survey findings vs shipped code

**Observation.** The 'Survey findings' sections of CLAUDE.md and CONTEXT.md still assert as current fact the PRE-slice-(a) auth code — 'no alternate item names, no ~/.claude/.credentials.json file fallback, no refreshToken use', 'Design, don't build yet' — while the same docs elsewhere say slice (a) shipped exactly those things (ordered discovery + file fallback + refresh machinery). CLAUDE.md's survey also still recommends 'pursue a first-run OAuth PKCE flow as the durable answer', contradicting the ADR-012 freeze recorded in the same file. Cited line numbers are stale too.

**Evidence.** CLAUDE.md §Survey: 'pinned to the single Keychain item… no alternate item names, no ~/.claude/.credentials.json file fallback, no refreshToken use… pursue a first-run OAuth PKCE flow as the durable answer'. CONTEXT.md:100-105 same + 'Design, don't build yet.' vs code: ClaudeOAuthCredentialSource.swift:38 `candidateKeychainServices = [ClaudeOAuthProvider.keychainService, "Claude Code"]`; :153 file fallback; :182 refresh path. CLAUDE.md cites ClaudeOAuthProvider.swift:45 — actual is :46.

**Recommendation.** Rewrite both survey sections in past tense ('at survey time, before slice (a)…') or update them to current state; delete or ADR-012-qualify the PKCE recommendation. These are the operating docs every agent session loads — internal contradictions here directly seed wrong assumptions in future work.

**Verification.** CONFIRMED

#### DOC-04 · P1 · Med/Low/S — Gemini provider claim (README/CONTEXT/CLAUDE/feature_list vs PROVIDERS/ROADMAP)

**Observation.** Google Gemini is advertised as a Planned provider in README.md (intro + providers table), CONTEXT.md, CLAUDE.md, and feature_list.json, but has zero presence in PROVIDERS.md (no adapter spec) and ROADMAP.md (no phase). A conductor prompt records the owner deliberately leaving this mismatch as-is. Judgment: for v1, drop the claim — an unspecced provider row in the README table is the repo-side equivalent of the 'coming soon' copy ADR-010 bans, and it has sat unresolved since 2026-06-30.

**Evidence.** README.md:10 'OpenAI, Gemini, and the Anthropic Console are on the roadmap'; :50 '| **Google Gemini** … | Planned |'. CONTEXT.md:16; CLAUDE.md:10; feature_list.json:17. `grep -in gemini PROVIDERS.md ROADMAP.md` → 0 hits. conductor/prompts/03-doc-fixes.md:6-7 'The owner has explicitly decided to leave the Gemini mismatch as-is — do NOT touch any Gemini reference'. BACKLOG.md:178-179 'spec it or drop the claim.'

**Challenges.** Owner's leave-as-is call recorded in conductor/prompts/03-doc-fixes.md; also tensions with ADR-010's no-vaporware principle

**Recommendation.** Decide now: (a) drop Gemini from README/CONTEXT/CLAUDE/feature_list until a real PROVIDERS.md spec + ROADMAP phase exists (smallest, most honest; recommended), or (b) write the Gemini adapter spec (auth method, endpoints, capabilities) into PROVIDERS.md + a ROADMAP slot. The 'leave as-is' non-decision is the worst of both: it advertises capability the design docs can't back.

**Verification.** CONFIRMED

#### DOC-05 · P2 · Med/Low/S — DECISIONS.md ADR-002 / ADR-003 vs reality

**Observation.** ADR-002 still names Übersicht as a live true-60s surface and states the Notification Center WidgetKit widget 'is shipped as a glanceable, ~15-min surface' — Übersicht was removed (ROADMAP Phase 3) and the widget is a README-only placeholder, so both halves of ADR-002's decision sentence are false today. ADR-003 likewise says 'the Übersicht .jsx calls a tiny Swift CLI'. README.md:35 softens but still says the widget 'exists in the repo'.

**Evidence.** DECISIONS.md ADR-002:11 'the **menu bar app** (and Übersicht). The Notification Center WidgetKit widget is shipped as a *glanceable, ~15-min* surface'; ADR-003:16 'the Übersicht `.jsx` calls a tiny Swift CLI (`houdini`)'. `ls apps/` → ios, menubar, widget (no ubersicht). apps/widget = 1-line README, no target. ROADMAP.md:23-24 'The earlier Übersicht `.jsx` prototype (`apps/ubersicht`) is removed.' README.md:35 'also exists in the repo'.

**Challenges.** Revises ADR-002/ADR-003 wording (decision substance intact)

**Recommendation.** Revise ADR-002/ADR-003 in place with a dated note (the ADR-006 precedent): menu bar app is the sole 60s surface; the WidgetKit widget is a *planned* unadvertised surface, not shipped. Adjust README.md:35 from 'widget… exists in the repo' to 'a placeholder for a future widget'.

**Verification.** inline evidence only (P2/P3 — not adversarially re-verified)

#### DOC-06 · P2 · Low/Low/S — PROVIDERS.md / ARCHITECTURE.md — Keychain item name

**Observation.** PROVIDERS.md says the Claude Code OAuth token lives in a Keychain item 'commonly named Claude Code' and ARCHITECTURE.md says CredentialStore 'can also read the Claude Code OAuth token (~/.claude / Keychain item Claude Code)'. In code the primary item is 'Claude Code-credentials' ('Claude Code' is only the second-tried fallback), and the ~/.claude file read lives in ClaudeOAuthCredentialSource, not CredentialStore.

**Evidence.** PROVIDERS.md:43 'item commonly named `Claude Code`'; ARCHITECTURE.md:41 'Keychain item `Claude Code`'. Code: ClaudeOAuthProvider.swift:46 `public static let keychainService = "Claude Code-credentials"`; ClaudeOAuthCredentialSource.swift:38 `candidateKeychainServices = [ClaudeOAuthProvider.keychainService, "Claude Code"]`; :204-207 `readCredentialsFileData()` reads ~/.claude/.credentials.json (in the credential source, not CredentialStore).

**Recommendation.** Fix PROVIDERS.md:43 and ARCHITECTURE.md:41 to name 'Claude Code-credentials' (primary) with 'Claude Code' + ~/.claude/.credentials.json as ordered fallbacks, and attribute the file read to ClaudeOAuthCredentialSource.

**Verification.** inline evidence only (P2/P3 — not adversarially re-verified)

#### DOC-07 · P2 · Low/Low/S — PROVIDERS.md contract vs shipped provider set

**Observation.** The shipped code registers a second provider id 'claude-cookie' (ClaudeCookieProvider) that appears nowhere in PROVIDERS.md's id list ('claude', 'anthropic-console', 'openai-platform', 'chatgpt-plus'); PROVIDERS.md models the cookie as the 'claude' provider's fallback authMethod, but code implements it as a separate provider with its own id and a duplicate displayName. Also code's claude capabilities statically include .dollarBalance vs the doc's conditional '(+ dollarBalance if Claude Extra)', and ADR-007's 'registry + UI adapt' via capability flags is unrealized — no shipping UI reads `capabilities` (only the PreviewData stub).

**Evidence.** PROVIDERS.md:9 `// "claude", "anthropic-console", "openai-platform", "chatgpt-plus"`; :47 'Fallback auth: .sessionCookie'. Code: ClaudeCookieProvider.swift:13 `public let id = "claude-cookie"`; UsageProvider.swift:43 `ProviderRegistry([ClaudeOAuthProvider(), ClaudeCookieProvider()])`. ClaudeOAuthProvider.swift:40 `capabilities = [.usagePct, .resetTimer, .dollarBalance]`. `grep -rn capabilities apps/menubar/Sources` → only PreviewData.swift:52.

**Recommendation.** Add 'claude-cookie' to the PROVIDERS.md contract (or note that cookie auth is realized as a sibling provider chosen by ClaudeAuthResolver), and soften ADR-007's claim to 'UI renders whatever metrics arrive; capability flags reserved for the future switcher' — otherwise the flags are dead API surface the docs oversell.

**Verification.** inline evidence only (P2/P3 — not adversarially re-verified)

#### DOC-08 · P2 · Med/Low/S — ROADMAP.md phase status markers

**Observation.** ROADMAP status markers remain inconsistent even after the 2026-07-01 'refresh' that BACKLOG.md:175-177 claims resolved them: Phase 2 (menu bar flagship — shipped in v0.4.0) carries no ✅ and still lists the unshipped App-Group bullet; Phase 5's first bullet (Claude .sessionCookie fallback) is built and live but unmarked; Phase 6's decision is finalized (ADR-006 revised) and Phase 7's site is live, both unmarked. A reader cannot tell shipped from unshipped phases.

**Evidence.** ROADMAP.md: Phase 0 ✅, Phase 1 ✅, Phase 3 ✅ — but '## Phase 2 — Menu bar app (flagship)' has no marker and includes 'Writes to App Group + reloadTimelines()' (never shipped); Phase 5 bullet 'Claude `.sessionCookie` fallback (embedded WebView login)' — shipped (ClaudeCookieProvider.swift, ClaudeLoginWindow.swift exist and are registered); Phases 6/7 unmarked though ADR-006 is decided and houdini.salomao.org is live. BACKLOG.md:175-177 'stale ✅ … markers updated'.

**Recommendation.** Do a real marker pass: ✅ Phase 2 (minus the App-Group bullet, moved to Phase 4), partially-✅ Phase 5 (cookie fallback done), ✅ Phase 6 decision + Phase 7. Consider a 'shipped / partial / not started' legend so absence of ✅ is unambiguous.

**Verification.** inline evidence only (P2/P3 — not adversarially re-verified)

#### DOC-09 · P2 · Med/Low/S — feature_list.json — stale and consumer-less

**Observation.** feature_list.json is a hand-generated snapshot (generated_at 2026-07-01) that already misstates priorities — P1 is 'next' though slice (a) shipped and ADR-012 capped it; P4 (in the working tree) is absent — and nothing in the repo consumes it: no script, site, app, or core code references the file (scripts/init.sh reads BACKLOG.md only). It has never been regenerated since creation. It is pure maintenance overhead with no reader.

**Evidence.** feature_list.json:31 `{ "id": "P1", … "status": "next" }` vs BACKLOG.md:11 'P1 … [~]' + ADR-012 cap; :41 `"generated_at": "2026-07-01"`. `grep -rn feature_list scripts/ site/ core/ apps/` → 0 hits; init.sh:94-101 parses BACKLOG.md. `git log --oneline -- feature_list.json` → single commit 1d742ee (creation). Positive check: its install/integrity fields are accurate (release.yml:56 generates SHASUMS256.txt; file absent from repo).

**Recommendation.** Pick one: (a) delete feature_list.json (nothing reads it), or (b) give it a consumer (e.g. init.sh prints from it, or the site build validates version pins against it) plus a mandatory regeneration step in RELEASE.md §7. A machine-readable manifest no machine reads is the definition of doc debt.

**Verification.** inline evidence only (P2/P3 — not adversarially re-verified)

#### DOC-10 · P2 · Low/Low/S — CONTEXT.md / BACKLOG.md — stale 'staleness' claims

**Observation.** CONTEXT.md and BACKLOG.md both still assert that ROADMAP.md Phase 7 says 'Cloudflare Pages' and 'is stale and should be corrected' — but ROADMAP was corrected to Vercel on 2026-07-01, and BACKLOG itself records that fix as RESOLVED 22 lines later. Two docs carry a self-contradicting, already-fixed action item.

**Evidence.** CONTEXT.md:108 '`ROADMAP.md` Phase 7's "Cloudflare Pages" is stale.'; BACKLOG.md:164-165 '`ROADMAP.md` Phase 7 ("Cloudflare Pages") is stale and should be corrected.' vs BACKLOG.md:175-177 'ROADMAP.md refresh — RESOLVED 2026-07-01: Phase 7 corrected to Vercel'. `grep -in cloudflare ROADMAP.md` → 0 hits; ROADMAP.md:39 'deployed on **Vercel**'.

**Recommendation.** Rewrite the two survey bullets in past tense ('was stale; corrected 2026-07-01') so resolved items stop reading as open work.

**Verification.** inline evidence only (P2/P3 — not adversarially re-verified)

#### DOC-11 · P2 · Low/Low/S — WORKFLOW.md — stale executor description, overlapping process doc

**Observation.** WORKFLOW.md's role definition says Claude Code is '(Opus 4.8, in VS Code)' while its own Conventions section — and CLAUDE.md's model-routing — say Fable 5 is the default and Opus is for routine/security-adjacent work. The doc also duplicates CLAUDE.md's 'How we work' content (git rules, budget, evidence) and is absent from CLAUDE.md's source-of-truth doc list and README's repo layout, leaving its authority unclear.

**Evidence.** WORKFLOW.md:5 '**Claude Code** (Opus 4.8, in VS Code): executes prompts…' vs :46-47 '**Model routing:** Fable 5 by default; Opus 4.8 for routine edits…'. CLAUDE.md §Model routing: 'Fable 5 (default)'. CLAUDE.md §Source-of-truth docs lists README/ARCHITECTURE/DECISIONS/PROVIDERS/ROADMAP/CONTEXT/BACKLOG — no WORKFLOW.md, no RELEASE.md. README repo-layout tree also omits both.

**Recommendation.** Fix WORKFLOW.md:5 to the routed reality, then either fold WORKFLOW.md into CLAUDE.md or add it (and RELEASE.md) to CLAUDE.md's source-of-truth list with a one-line scope note — two half-overlapping process docs invite drift like this.

**Verification.** inline evidence only (P2/P3 — not adversarially re-verified)

#### DOC-12 · P3 · Low/Low/S — README.md / scripts/README.md — repo layout inaccuracies

**Observation.** README's repo-layout tree omits six root artifacts (CONTEXT.md, BACKLOG.md, CLAUDE.md, WORKFLOW.md, RELEASE.md, feature_list.json) and conductor/, and labels scripts/ as 'release helpers + init.sh' when scripts/ contains only init.sh + a README; that scripts/README.md in turn says 'Sign/notarize, install.sh, release automation' — all of which live elsewhere (root install.sh, .github/workflows/release.yml).

**Evidence.** README.md:57-71 tree lists only README/ARCHITECTURE/DECISIONS/PROVIDERS/ROADMAP/core/apps/site/install.sh/scripts; :71 'scripts/ ← release helpers + init.sh'. `ls scripts/` → README.md, init.sh. scripts/README.md:1 'Sign/notarize, install.sh, release automation. See ../DECISIONS.md ADR-006.'

**Recommendation.** Update README's tree to include the Build-Conductor docs (or a one-line pointer), correct the scripts/ description to 'developer bootstrap (init.sh)', and rewrite scripts/README.md to describe what the folder actually holds.

**Verification.** inline evidence only (P2/P3 — not adversarially re-verified)

#### DOC-13 · P3 · Low/Low/S — RELEASE.md — checklist vs practiced reality

**Observation.** RELEASE.md's pre-flight requires 'CI passing' though no app/site CI exists (only the tag-triggered release.yml), and its §6 template says deploy with `vercel --prod` while the actually-practiced v0.4.0 go-live (recorded in the same file) used the prebuilt flow `vercel build --prod && vercel deploy --prebuilt --prod`, which CLAUDE.md documents as the method. The template a future release will follow differs from the proven procedure.

**Evidence.** RELEASE.md:69 '`master` is green and clean (`git status` empty, CI passing).'; :102 'Deploy production from `site/`: `vercel --prod`.' vs :32 (v0.4.0 log) '`cd site && vercel build --prod && vercel deploy --prebuilt --prod`'. `ls .github/workflows` → release.yml only. CLAUDE.md: 'deployed manually via the prebuilt CLI (`vercel --prod` from `site/`; prebuilt output in `site/.vercel/output/`)'.

**Recommendation.** Replace 'CI passing' with the checks that actually exist (swift test / selftest, site build) until CI lands (see PND-TEST-02/05), and make §6's deploy command the prebuilt two-step used in practice.

**Verification.** inline evidence only (P2/P3 — not adversarially re-verified)

#### DOC-14 · P3 · Low/Low/S — ADR-001/004/005/006/008/009/010/011/012 — conformance check (mostly clean)

**Observation.** The remaining ADRs match the repo: ADR-001 (URLSession+JSON, scrape demoted) matches ClaudeOAuthProvider; ADR-004 build order matches (only Claude built); ADR-005 matches (Keychain-only, ephemeral WebView); ADR-006 matches install.sh (SHA-256 verify, no sudo, offered login item); ADR-008 scaffold exists with #if os(macOS) guards; ADR-009 names/ids all match; ADR-010 is locally consistent (single v0.4.0 across README/install.sh/site config; one local tag) though GitHub-side release pruning was not network-verified; ADR-011 holds (no provider keys or key UI in site/, no Gemini/OpenAI named on the site); ADR-012 matches code (refresher stays nil in production). Recorded so the audit shows both directions were checked.

**Evidence.** install.sh:8-11 verify+no-sudo; :119-121 'Offer: start at login (never forced)'. ClaudeLoginWindow.swift:40 `.nonPersistent()`. Info.plist: `org.salomao.houdini`, `0.4.0`; ClaudeCookieProvider.swift:23 'Houdini-claude-session'. install.sh:29 TAG=v0.4.0 = README:17 = site/src/config.ts:8,12; `git tag -l` → v0.4.0. site/src/pages/index.astro:133 'Built for Claude — more providers as they open up.' ClaudeOAuthCredentialSource.swift:111 `refresher: Refresher? = nil`.

**Recommendation.** No action beyond the ADR-002/003 revision (DOC-05). Optionally verify GitHub-side single-release state (`gh release list`) at next release per RELEASE.md §5, since ADR-010's pruning claim was only locally verifiable in this audit.

**Verification.** inline evidence only (P2/P3 — not adversarially re-verified)

**Dimension summary.** Docs audit (Dimension H): all 12 ADRs and every root doc were checked against the code. Verified-clean: ADR-001/004/005/006/008/009/011/012 match reality (install.sh integrity claims, Keychain names, single v0.4.0 pin across README/install.sh/site config, refresher-nil freeze, no keys or Gemini/OpenAI on the site); ADR-010 is locally consistent but GitHub-side pruning was not network-verified. The serious drift clusters in ARCHITECTURE.md, which describes two fictional subsystems: (1) the App-Group/WidgetCenter bridge + WidgetKit widget (confirmed absent — apps/widget is a one-line README, no WidgetCenter call in the menubar app), and (2) a NEW finding the pendências inventory missed — nonexistent `Scheduler` (jitter/exponential backoff) and `Cache` components claimed by both ARCHITECTURE.md and PROVIDERS.md, with an app UI string falsely claiming backoff. Second-order drift: CLAUDE.md/CONTEXT.md survey sections still describe pre-slice-(a) auth code (and recommend the frozen PKCE path); CONTEXT/BACKLOG still flag the already-fixed 'Cloudflare Pages' staleness; ROADMAP markers remain incomplete (shipped Phase 2 unmarked) despite BACKLOG claiming they were updated; ADR-002/003 still reference Übersicht and assert the widget 'is shipped'. feature_list.json is stale (P1 'next', no P4), never regenerated, and — new finding — consumed by nothing in the repo. The Gemini claim (README/CONTEXT/CLAUDE/feature_list vs zero spec in PROVIDERS/ROADMAP) is confirmed and judged: drop it for v1 or spec it; the recorded 'leave as-is' non-decision advertises capability the design docs can't back. BACKLOG.md's uncommitted state is exactly the +27-line P4 self-update section. All 11 assigned pendências validated: 9 confirmed, 2 corrected (PND-DOC-02 also covers Phase 2; PND-DOC-05 additionally has zero consumers), 0 refuted. 14 findings (3×P1, 8×P2, 3×P3), 9 new pendências.


### F. DX — build, tests, CI

#### DX-01 · P1 · High/High/M — Release CI / supply chain

**Observation.** The release workflow has NEVER succeeded: all 4 runs of release.yml (v0.2.0 x2, v0.3.0, v0.4.0) completed in failure. The shipped v0.4.0 that install.sh pins was hand-built on the dev machine and uploaded manually — the published SHASUMS256.txt is byte-identical to the local staging dir build/release-v0.4.0/. Yet release.yml's header, scripts/init.sh L91 ('A tag push (v*.*.*) triggers .github/workflows/release.yml -> builds, checksums, publishes the Release'), and CLAUDE.md ('release CI is .github/workflows/release.yml') all present CI as the release builder. Release provenance is actually a single laptop.

**Evidence.** gh run list --workflow=release.yml: 'completed failure ... v0.4.0 ... 30s' / 'failure ... v0.3.0 ... 32s' / 'failure ... v0.2.0 ... 35s' / 'failure ... v0.2.0 ... 51s' (all 4 runs). Local build/release-v0.4.0/SHASUMS256.txt == curl of released SHASUMS256.txt: both '0235f256...  Houdini.app.zip / 1d17035e...  houdini'. Release createdAt 2026-06-19T19:04:53Z vs CI run start 19:04:57Z — release was created manually at tag push, before CI even failed.

**Challenges.** CLAUDE.md repo map ('release CI is .github/workflows/release.yml') and init.sh/RELEASE.md — the documented release story does not match how v0.2.0–v0.4.0 were actually published.

**Recommendation.** Pick one canonical release path and make docs match reality. Either fix the workflow (see DX-02) and let CI build+publish (better provenance for a security-marketed installer), or explicitly document the manual gh-release flow as the shipping path and delete/park release.yml. Do not leave a dead workflow that docs claim is the builder.

**Verification.** CONFIRMED

#### DX-02 · P1 · High/Med/S — Release CI root cause / toolchain skew

**Observation.** release.yml fails because apps/menubar/Sources/Houdini/WidgetGlass.swift:149 calls Color.clear.glassEffect(in:) behind a runtime #available(macOS 26,*) check with no compile-time guard — compiling it requires the macOS 26 SDK. The workflow deliberately prefers Xcode 16 ('ls -d /Applications/Xcode_16*.app') on a macos-14 runner, which lacks that SDK, so the build is guaranteed to fail. The local dev machine compiles fine (CommandLineTools, Swift 6.3.2, target macosx26.0). Doc claims 'Swift 6 / Xcode 16+' (init.sh L48, release.yml header) are therefore stale — an Xcode 16 contributor cannot build apps/menubar.

**Evidence.** CI log (run 27843765926): 'WidgetGlass.swift:149:25: error: value of type Color has no member glassEffect ... 147 | } else if #available(macOS 26, *)'. release.yml L30: XC="$(ls -d /Applications/Xcode_16*.app ...)". WidgetGlass.swift has no '#if compiler'/'#if canImport' guards (grep empty). Local: 'Apple Swift version 6.3.2 ... Target: arm64-apple-macosx26.0'; ./build.sh release → 'Build complete! ... ==> built: .../build/Houdini.app' (exit 0).

**Challenges.** release.yml's 'It needs only a Swift 6 toolchain' design assumption — the codebase now requires the macOS 26 SDK, which Swift-6-era Xcode 16 does not provide.

**Recommendation.** Wrap the Liquid Glass branch in a compile-time guard (e.g. #if compiler(>=6.2) / SDK check) so the code builds on both toolchains, AND/OR move the runner to an image shipping Xcode 26 and update the Xcode-selection glob. Then correct 'Xcode 16+' claims in init.sh, release.yml comments, and README.

**Verification.** CONFIRMED

#### DX-03 · P1 · High/Med/S — Test runner integrity (swift test no-op)

**Observation.** On this CommandLineTools-only machine — the primary dev machine — `swift test` in core/ exits 0 while executing ZERO tests (the swift-testing runner no-ops; `swift test list` also lists nothing). The 28 @Test functions in FetcherCoreTests never run locally; the only real local gate is remembering to run `swift run houdini-selftest` (29 checks, PASS). A regression that breaks every test would still show a green `swift test`. The docs know it 'no-ops' but nothing guards against mistaking that for a pass, and there is no CI to run the suite for real (see DX-04).

**Evidence.** `cd core && swift test` output in full: 'Building for debugging... Linking FetcherCorePackageTests / Build complete! (0.62s)' — no 'Test run' line, exit 0. `swift test list` → 'Build complete!' only. `swift run houdini-selftest` → 'PASS — 29 checks'. core/Package.swift L9-12 documents the no-op. @Test counts: 9+15+4=28 across the 3 test files.

**Recommendation.** Make a full-Xcode CI runner execute `swift test` (it runs normally there per Package.swift's own comment — unverified here) so the suite has one place it actually executes. Cheap local mitigation: init.sh (or a `make test` wrapper) should detect the CLT toolchain and print 'swift test NO-OPS here — run houdini-selftest', or fail if 0 tests executed.

**Verification.** CONFIRMED

#### DX-04 · P1 · High/Med/S — CI baseline (PR/push)

**Observation.** There is no CI on push or PR at all — .github/workflows/ contains only release.yml (tag-triggered, and broken per DX-01). Nothing ever builds core/, apps/menubar, or site/ on a commit; site has no lint/test scripts either. The repo is PUBLIC, so GitHub-hosted macOS runners are free — the usual cost objection does not apply. A v1-worthy baseline is one small workflow: (1) core: swift build + swift test + swift run houdini-selftest; (2) menubar: ./build.sh release + run the binary's --widgettest (the one smoke flag with real exit codes); (3) site: npm ci && npm run build. All three were exercised locally in this audit and are scriptable.

**Evidence.** ls .github/workflows/ → 'release.yml' (only file). site/package.json scripts: only dev/build/preview. gh repo view → {"isPrivate":false,"visibility":"PUBLIC"}. Local proof each step works: core swift build 'Build complete!', houdini-selftest 'PASS — 29 checks', build.sh release '==> built: .../Houdini.app', --metrictest exit 0.

**Recommendation.** Add one ci.yml on push/PR with the three jobs above on a macos-15/26 runner (Linux can additionally do the site job for speed). This simultaneously fixes DX-03 (tests actually execute) and makes RELEASE.md's 'CI passing' pre-flight (PND-TEST-05) meaningful.

**Verification.** CONFIRMED

#### DX-05 · P2 · Med/Med/M — Test coverage shape (core)

**Observation.** Coverage is good where it is pure and absent where it is risky. Covered: usage-parser dialect equivalence, reset-date tolerance, org selection, OAuth credential discovery/refresh/resolver (all seam-injected, no network). NOT covered anywhere: the HTTP status→error mapping in both providers (401/403→.authExpired, non-2xx→.http), the CredentialRedirectGuard.sameSite cross-site header-stripping logic (security-relevant, a pure static function that is trivially testable today), and CredentialStore's parsing of /usr/bin/security output. Both providers call URLSession.shared directly — there is no transport seam, so HTTP-layer tests need URLProtocol stubbing or an injected transport.

**Evidence.** grep 'statusCode|RedirectGuard|sameSite|CredentialStore|HTTP' core/Tests/FetcherCoreTests/*.swift → ZERO hits. ClaudeOAuthProvider.swift L113-122: 'switch http.statusCode ... throw ProviderError.authExpired ... throw ProviderError.http(...)'; ClaudeCookieProvider.swift L99-108 same shape; both use 'URLSession.shared.data(' (L103/L89). HTTPRedirectGuard.swift L33-35: static func sameSite(_ a: String, _ b: String) -> Bool { a == b || a.hasSuffix("."+b) || b.hasSuffix("."+a) } — untested.

**Recommendation.** Start with the free win: unit-test sameSite (it guards cookie/bearer leakage on redirects — worth adversarial cases like 'evil-claude.ai' and bare-TLD hosts). Then add a transport seam (protocol or URLProtocol) to cover the status-code mapping for both providers. CredentialStore parsing can be tested by injecting fake `security` output.

**Verification.** inline evidence only (P2/P3 — not adversarially re-verified)

#### DX-07 · P2 · Med/Med/S — Menubar smoke flags as test substitute

**Observation.** The smoke-flag story is weaker than the docs imply: of the app's headless modes, only --widgettest (and --setloginitem) can actually FAIL — SelfTest.swift's --selftest, --metrictest and the --snapshot renderer unconditionally exit(0), printing output for a human to eyeball. So the gauge/formatting logic with real branching (auto tightest-limit primary selection, 5-hour-missing fallback, '$93/100' dollar formatting, ring clamp at WidgetRingGauge.swift:25) has no machine-checked regression gate at all; a wrong menu-bar string would still be a green run.

**Evidence.** grep exit( SelfTest.swift: L55 exit(0), L103 exit(0) (metricTest ends exit(0) with no failure path), Snapshotter.swift L39 exit(0); only WidgetTest.swift L102 'exit(fail == 0 ? 0 : 1)' and SelfTest L122 'exit(ok ? 0 : 1)'. Live run: '.../Houdini --metrictest' printed 'Auto (tightest limit) → "95%" ... saved=extra usage → "$93/100"', EXIT=0 — informative but assertion-free.

**Challenges.** CLAUDE.md's framing of smoke flags as the apps/menubar test story — as implemented, 3 of the 4 flags cannot fail, so they verify 'does not crash', not correctness.

**Recommendation.** Convert --metrictest's known-answer prints into check()-style assertions with a non-zero exit (the expected strings are already deterministic PreviewData), and add it plus --widgettest to the CI job from DX-04. Longer term, the pure formatting/selection logic could move to a testable target.

**Verification.** inline evidence only (P2/P3 — not adversarially re-verified)

#### DX-11 · P2 · Med/Med/S — Release flow conflict (manual vs CI)

**Observation.** RELEASE.md's checklist and history document MANUAL `gh release create` as the real flow (v0.3.0/v0.4.0 logs), while release.yml also runs `gh release create` on the same tag push. If DX-02 is fixed and CI starts succeeding, the two paths collide: whichever runs second fails because the release already exists (v0.4.0 shows the manual release created at 19:04:53Z, 4s before the CI run started). Minor extra: the workflow's actions/checkout@v4 triggers Node-20 deprecation warnings on current runners.

**Evidence.** RELEASE.md L29: '[x] ... gh release create v0.4.0 with Houdini.app.zip, houdini, SHASUMS256.txt' (manual, logged done); release.yml L86: 'gh release create "$TAG" ...'. Release createdAt 2026-06-19T19:04:53Z vs run 27843765926 started 19:04:57Z. CI log: 'Node.js 20 is deprecated ... actions target Node.js 20 ... actions/checkout@v4'.

**Challenges.** RELEASE.md §1/§4 process design — its pre-flight and publish steps assume two release creators can coexist; they cannot for the same tag.

**Recommendation.** When choosing the canonical path (DX-01): if CI publishes, strip `gh release create` from RELEASE.md (checklist verifies the CI-made release instead); if manual stays, make the workflow build-only (artifact upload, no release creation). Bump checkout to a Node-24 release.

**Verification.** inline evidence only (P2/P3 — not adversarially re-verified)

#### DX-06 · P3 · Med/Low/M — houdini-selftest duplicate maintenance

**Observation.** FetcherCoreTests (28 @Test) and houdini-selftest/main.swift (239 lines, 29 checks) are hand-maintained duplicates of the same assertions — the selftest exists solely because swift test no-ops on CLT (DX-03). Nothing checks parity: a test added to one and forgotten in the other silently diverges, and the CLT machine would silently lose that coverage. The mirror is a reasonable workaround, but it is standing tech debt whose justification disappears the day CI runs swift test for real.

**Evidence.** houdini-selftest/main.swift L4-11: 'reading the SAME committed fixtures as Tests/FetcherCoreTests ... swift-testing ... no-ops under swift test'; L129: 'Mirrors ClaudeAuthResolverTests.swift'. Counts: 28 @Test vs 'PASS — 29 checks'. No script/CI compares the two.

**Recommendation.** Once CI executes swift test (DX-04), demote the selftest to a smoke subset or generate both from one table of cases; at minimum add a comment-pinned checklist or a count assertion so drift is noticed.

**Verification.** inline evidence only (P2/P3 — not adversarially re-verified)

#### DX-08 · P3 · Med/Low/S — Build reproducibility / toolchain pinning

**Observation.** Dependency-level reproducibility is fine: zero third-party Swift dependencies (so no Package.resolved is needed — its absence is NOT a defect), swift-tools-version pinned to 6.0, and site/package-lock.json is committed. Toolchain-level reproducibility is not: no .swift-version/DEVELOPER_DIR pin or documented required Xcode/SDK, and the dev-machine-vs-CI SDK skew (macOS 26 SDK vs Xcode 16) already broke the only pipeline (DX-02). Shipped binaries are currently only reproducible by this one machine's toolchain.

**Evidence.** find . -name Package.resolved (excl. .build/node_modules) → none; core/Package.swift 'dependencies:' absent, apps/menubar depends only on '.package(path: "../../core")'. git ls-files site | grep lock → site/package-lock.json. swift --version → 'Apple Swift version 6.3.2 ... arm64-apple-macosx26.0'; xcode-select -p → /Library/Developer/CommandLineTools.

**Recommendation.** Once DX-02 lands, state the minimum toolchain (Swift/SDK version) in README + init.sh and have init.sh probe the SDK (not just `swift` presence). CI on a pinned runner image then becomes the reference build environment.

**Verification.** inline evidence only (P2/P3 — not adversarially re-verified)

#### DX-09 · P3 · Low/Low/S — .gitignore hygiene

**Observation.** Hygiene is largely good: no build artifacts are tracked (git ls-files shows none), .build/, DerivedData/, node_modules/, dist/ and secrets patterns are ignored. Two notes: (1) the unanchored 'build/' pattern ignores BOTH the root build/ (which holds the v0.4.0 manual-release staging: Houdini.app.zip, houdini, SHASUMS256.txt, NOTES.md — the actual provenance record of the shipped release, existing only on this laptop and referenced by no doc) AND apps/menubar/build/, plus any future source dir named 'build'; (2) 'conductor/prompts/' is ignored, yet audit/03-pendencias-todos.md cites conductor/prompts/*.md file:line as evidence — those sources are unrecoverable from the repo for anyone else.

**Evidence.** .gitignore: 'build/' (L21, unanchored), 'dist/', 'conductor/prompts/'. git check-ignore -v build/release-v0.4.0 → '.gitignore:21:build/'. git ls-files | grep -iE '\.build/|^build/|/build/|\.app|DerivedData' → empty. ls build/release-v0.4.0 → Houdini.app.zip, NOTES.md, SHASUMS256.txt, houdini (Jun 19, same day as the v0.4.0 tag). grep 'build/release|stage' RELEASE.md → no hits.

**Recommendation.** Anchor the pattern as '/build/' and 'apps/menubar/build/' if a source dir named build ever becomes plausible (optional). More importantly: either commit release-staging NOTES/SHASUMS (not binaries) or document in RELEASE.md where manual-release provenance lives; stop citing gitignored conductor/prompts paths as evidence in committed audit docs.

**Verification.** inline evidence only (P2/P3 — not adversarially re-verified)

#### DX-10 · P3 · Low/Low/S — scripts/init.sh correctness

**Observation.** init.sh runs clean (exit 0, correct toolchain probes, prints real commands and the top BACKLOG item) but has one false report: on this CommandLineTools-only machine it prints 'xcodebuild: present (full Xcode)' because /usr/bin/xcodebuild is a CLT shim that satisfies `command -v` while actually erroring when invoked. A new contributor is told they have full Xcode when they do not (which matters for apps/ios). Its 'Xcode 16+' hint is also stale per DX-02.

**Evidence.** init.sh run: '✓ swift — ... 6.3.2 ... / xcodebuild: present (full Xcode). Not required...' EXIT=0. But: command -v xcodebuild → /usr/bin/xcodebuild; xcodebuild -version → 'xcode-select: error: tool xcodebuild requires Xcode, but active developer directory /Library/Developer/CommandLineTools is a command line tools instance'. init.sh L54 uses `have xcodebuild` (command -v only).

**Recommendation.** Probe with `xcodebuild -version >/dev/null 2>&1` (or `xcode-select -p` contains 'Xcode.app') instead of command -v; update the 'Xcode 16+' string when DX-02's real minimum is settled.

**Verification.** inline evidence only (P2/P3 — not adversarially re-verified)

**Dimension summary.** Dimension F ran the full local pipeline: core `swift build` passes, `houdini-selftest` passes (29 checks), apps/menubar/build.sh release builds and signs, init.sh runs clean, --metrictest works. The headline finding is that the release CI story is fiction: all 4 release.yml runs ever have FAILED (a glassEffect/macOS-26-SDK compile error the Xcode-16-pinned runner can never pass), and the shipped v0.4.0 was hand-built on this laptop — its published SHASUMS256.txt is byte-identical to the local gitignored build/release-v0.4.0/ staging dir — while release.yml, init.sh, and CLAUDE.md all claim CI builds releases. Second headline: on this CLT-only dev machine `swift test` exits 0 while running ZERO tests, so the real 28-test suite never executes anywhere (no PR/push CI exists at all); the hand-maintained houdini-selftest mirror is the only live gate. Coverage itself is solid on pure logic (parser, org selection, auth resolver) but absent on the risky paths: HTTP status→error mapping, the security-relevant redirect-guard sameSite predicate, and CredentialStore parsing — and providers lack a transport seam to test them. The menubar smoke-flag substitute is weaker than advertised: 3 of 4 flags cannot fail (always exit 0). Repo is public, so a pragmatic v1 CI baseline (core build+test+selftest, menubar build+--widgettest, site npm build) costs nothing but ~30 lines of YAML and would make RELEASE.md's currently-unsatisfiable 'CI passing' pre-flight real. Gitignore hygiene and dependency reproducibility are fine (zero third-party Swift deps, lockfile committed); toolchain pinning is not (docs say Xcode 16+, code requires the macOS 26 SDK). PND-TEST-01 confirmed, PND-TEST-05 confirmed (stronger than written), PND-TEST-02 corrected: not just 'no CI' — the only workflow is broken and releases are manual. Nine new pendências filed.


### J. Security / privacy / ToS

#### SEC-01 · P1 · Med/Med/S — core/ network layer (Keychain-only claim)

**Observation.** Both Claude providers use URLSession.shared with the default (non-ephemeral) configuration and never disable cookie acceptance or the disk-backed URLCache. Any Set-Cookie returned by claude.ai on the cookie-authenticated GETs would be accepted into persistent HTTPCookieStorage (written under ~/Library/HTTPStorages/org.salomao.houdini), and cacheable responses can land in Cache.db on disk — both would put session material / account data outside the Keychain, contradicting the CLAUDE.md guardrail 'never log, transmit, cache to disk'. The WebView login is correctly ephemeral; the polling session is not.

**Evidence.** ClaudeOAuthProvider.swift:103 and ClaudeCookieProvider.swift:89 both call `URLSession.shared.data(for: request, delegate: CredentialRedirectGuard.shared)`. grep for `httpShouldSetCookies|HTTPCookieStorage|URLCache|cachePolicy|ephemeral` across core/ and apps/ returns ZERO matches — no client-side hardening exists; the guarantee currently rests on Anthropic's server cache/cookie headers, which were not verified. Contrast ClaudeLoginWindow.swift:40 `config.websiteDataStore = .nonPersistent()` (deliberate, ADR-005).

**Recommendation.** Add one shared static URLSession built from URLSessionConfiguration.ephemeral with httpShouldSetCookies=false, httpCookieAcceptPolicy=.never and urlCache=nil, and use it in both providers (and the future admin-key adapters). ~10 lines, no behavior change, makes the 'nothing hits disk' claim true by construction instead of by server courtesy.

**Verification.** CONFIRMED

#### SEC-02 · P1 · High/Med/S — ADR-012 / user-facing transparency

**Observation.** Houdini tells users the mechanism ('reuses the Claude Code OAuth token') but nowhere — app Settings, site privacy page, README, install flow — discloses that Anthropic's Consumer Terms prohibit third-party use of subscription OAuth/cookies and that enforcement (account bans) is active, with the risk landing on the user's own account. ADR-012 §6 itself recommends the disclosure line but defers it as 'optional'. A product whose entire pitch is trust ('An app that touches your logins should earn it', privacy.astro:46) that silently uses a credential its vendor has explicitly banned from third-party tools is internally inconsistent; the deferral is the wrong call.

**Evidence.** ADR-012 L67: 'Optional (recommended, not yet adopted)… Deferred'. grep for terms/ToS/discretion across apps/menubar and site/src: no user-facing hit. SettingsView.swift:104 'Reusing the Claude Code OAuth token — no separate login needed.' privacy.astro:15 'Houdini reuses the Claude Code OAuth token… never logged' (no ToS caveat). External: Anthropic updated legal terms 2026-02-20 — OAuth tokens from Free/Pro/Max 'in any other product, tool, or service… is not permitted'; server-side blocks 2026-01-09, full enforcement 2026-04-04, auto-bans reported (theregister.com/2026/02/20, winbuzzer.com, gigazine.net — web-search verified).

**Challenges.** ADR-012 §6 (transparency line 'optional, deferred' → should be required for v1)

**Recommendation.** Adopt posture (b): keep the frozen read-only integration but make the transparency line mandatory for v1 — one sentence in app Settings next to the auth status and one on the site privacy page ('Houdini reads your existing Claude credential; Anthropic's terms restrict third-party use of subscription auth; use at your discretion'). Revise ADR-012 §6 from 'optional/deferred' to 'required'. Cost is one line of copy; it converts a silent grey-zone into informed consent and is the only option that is consistent with the product's own trust story. Options (c) refresh and (d) PKCE should stay frozen (see SEC-07/SEC-08).

**Verification.** CONFIRMED

#### SEC-03 · P2 · Med/Low/M — install.sh supply chain

**Observation.** The checksum verification is self-attesting: release.yml generates SHASUMS256.txt in the same CI job and uploads it to the same GitHub Release that install.sh downloads both from. The SHA-256 check therefore protects against download corruption/truncation, CDN tampering of a single asset, and asset/checksum mismatch — but NOT against a compromised GitHub account, a malicious tag push, or compromised CI, since any attacker who can replace Houdini.app.zip can regenerate SHASUMS256.txt in the same place. The trust root is entirely 'the vitorsalomao05 GitHub account at release time'. Site/README copy ('checksum-verified', 'verifies their SHA-256') is factually true and config.ts frames it correctly ('the bytes you run are the bytes published in the tag'), but a casual reader will infer stronger protection than exists.

**Evidence.** release.yml:56 `( cd "$STAGE" && shasum -a 256 Houdini.app.zip houdini > SHASUMS256.txt )` then uploaded with the same assets (L91). install.sh:30 `REL="https://github.com/$REPO/releases/download/$TAG"`; L85–87 fetches SHASUMS256.txt, Houdini.app.zip, houdini all from $REL; L74 `curl -fSL --proto '=https' --tlsv1.2`. index.astro:108 'No Gatekeeper prompt · checksum-verified · nothing leaves your Mac'.

**Challenges.** ADR-006 (partially — its 'we counter curl|bash with SHA-256 verification' framing overstates what a same-source checksum counters)

**Recommendation.** Two cheap upgrades: (1) sign SHASUMS256.txt with a maintainer-held key independent of GitHub (minisign or `ssh-keygen -Y sign`; publish the public key on houdini.salomao.org, which is a separate trust domain) and have install.sh verify the signature when the tool is present; (2) add one honest sentence to README/install page stating what the checksum does and does not protect against. Do not weaken existing checks (guardrail).

**Verification.** inline evidence only (P2/P3 — not adversarially re-verified)

#### SEC-04 · P2 · Med/Low/S — install.sh / site copy (Gatekeeper)

**Observation.** install.sh strips the quarantine attribute (`xattr -dr com.apple.quarantine`) so the ad-hoc-signed, unnotarized app launches with no Gatekeeper evaluation, and the site markets 'No Gatekeeper prompt' as a pure convenience feature (hero line, install page, FAQ). Functionally this removes macOS's malware scan/notarization check for this binary; combined with SEC-03's self-attesting checksum, the user has no Apple-side integrity check at all. That is an accepted ADR-006 trade-off, but advertising the bypass as a benefit without one sentence of context sits oddly on a trust-first product.

**Evidence.** install.sh:100–102 '# …strip it defensively so the ad-hoc-signed app opens without a Gatekeeper prompt.' `xattr -dr com.apple.quarantine "$APP"`. index.astro:108 'No Gatekeeper prompt · checksum-verified'; config.ts:103 'ad-hoc signed with a hardened runtime, so it opens with no Gatekeeper prompt'; install.astro:339 'One line, no Gatekeeper prompt, nothing leaves your Mac.'

**Recommendation.** Add one honest clause where 'no Gatekeeper prompt' is advertised (e.g. 'the app is ad-hoc signed, not Apple-notarized — the installer verifies checksums instead'), and keep notarized-DMG (ADR-006 future option) as the eventual fix. Do not change install.sh behavior without sign-off (gated file).

**Verification.** inline evidence only (P2/P3 — not adversarially re-verified)

#### SEC-07 · P2 · Med/Med/S — ADR-012 risk record accuracy

**Observation.** ADR-012's 'read-only, judged low risk' framing understates two facts the record should own. (1) Houdini does not merely 'read' a credential — it actively impersonates other clients on the wire: the OAuth path sends `User-Agent: claude-code/<version>` and the cookie path sends a fake Safari UA; after Anthropic's Jan-2026 server-side third-party OAuth blocks, this impersonation is precisely what keeps the calls working, i.e. the app functions by evading an enforcement mechanism, not just by being unobtrusive. (2) PROVIDERS.md calls the risk 'low (own account, low-frequency)' while the default poll is 60s ≈ 1,440 requests/day — automated-looking traffic of exactly the shape abuse filters flag. The decision itself (frozen read-only, usage-only endpoint, no inference — outside the token-arbitrage pattern that drove documented bans) remains defensible; the record and the risk language are what's wrong.

**Evidence.** ClaudeOAuthProvider.swift:96 `request.setValue("claude-code/\(clientVersion)", forHTTPHeaderField: "User-Agent")`; ClaudeCookieProvider.swift:79–83 sends 'Mozilla/5.0 (Macintosh…) Safari/605.1.15'. ClaudeOAuthProvider.swift:41 `refreshInterval: TimeInterval = 60`. PROVIDERS.md L47 'Risk: low (own account, low-frequency)'. ADR-012 L64 concedes the mimicry only for *future* work ('would escalate the signal that Houdini's traffic mimics the Claude Code client'). External: server-side third-party OAuth checks deployed 2026-01-09, full enforcement 2026-04-04 (theregister.com, natural20.com — web-search verified).

**Challenges.** ADR-012 (risk framing) and PROVIDERS.md L47 ('low-frequency')

**Recommendation.** Revise ADR-012 to state plainly that both paths spoof another client's identity and that this is what evades the Jan-2026 blocks; fix PROVIDERS.md's 'low-frequency' claim. Consider lowering the default poll (e.g. 120–300s) or making the interval a visible setting — it reduces the automated-traffic signal at negligible UX cost. This pairs with SEC-02: the user carrying the ban risk should know what the app sends on their behalf.

**Verification.** inline evidence only (P2/P3 — not adversarially re-verified)

#### SEC-05 · P3 · Low/Low/S — core/ ClaudeOAuthProvider (process hygiene)

**Observation.** Every OAuth fetch (60s poll) spawns `/usr/bin/env claude --version` to build the User-Agent, because `clientVersion` is a computed property with no caching. This (1) launches the Node-based Claude Code CLI up to 1,440×/day, (2) resolves the binary via PATH from a credential-handling app — a user-writable PATH entry earlier than the real `claude` gets executed by Houdini (only exploitable by an attacker who already has user-level write access, so low severity), and (3) is wasted work since the result is effectively constant per session.

**Evidence.** ClaudeOAuthProvider.swift:130–132 `private var clientVersion: String { explicitVersion ?? Self.detectedClientVersion() }` — called from fetchUsage's header build (L96) on every fetch; L142–144 `proc.executableURL = URL(fileURLWithPath: "/usr/bin/env"); proc.arguments = ["claude", "--version"]`. No memoization anywhere in the type.

**Recommendation.** Detect the version once (static lazy / actor-cached) and reuse it for the process lifetime; optionally resolve `claude` to an absolute path under ~/.local/bin//opt/homebrew/bin and skip `/usr/bin/env`. Also note GUI-launched instances usually have a minimal PATH, so today the code silently falls back to the pinned '2.1.178' — meaning the spoofed UA version can drift stale, which is also a detectability concern (see SEC-07).

**Verification.** inline evidence only (P2/P3 — not adversarially re-verified)

#### SEC-06 · P3 · Low/Low/S — Verification record — Keychain-only + no-server claims

**Observation.** The core privacy claims substantially hold at the code level. (1) The /usr/bin/security shell-out does NOT leak the secret via argv (visible in ps): arguments are only `find-generic-password -s <service> -w`; the secret returns via a stdout pipe. (2) No token/cookie is printed, logged, or written to UserDefaults/disk anywhere in core/ or apps/ — the only credential writes are Keychain SecItemAdd/Update; both login WebViews (macOS + iOS) use .nonPersistent() stores. (3) 'No server' verified: the only remote endpoints in app code are api.anthropic.com/api/oauth/usage, claude.ai/api/organizations{,/{id}/usage}, claude.ai/login; install.sh talks only to github.com/raw.githubusercontent.com; the site is static Astro with self-hosted @fontsource fonts, no fetch()/analytics/external scripts. None is Houdini-operated. Residual gaps are SEC-01 (URLSession config) and SEC-05.

**Evidence.** CredentialStore.swift:72–77 `var args = ["find-generic-password", "-s", service, "-w"] … proc.standardOutput = out` (secret via pipe, not argv). grep print/NSLog/os_log ∩ token/cookie/session/secret across all Swift sources → only a selftest banner string. URL grep across core+apps → exactly the 5 URLs above. site/package.json deps: astro, tailwind, @fontsource only; grep analytics/gtag/posthog/script-src → no hits. houdini/main.swift:6 'NEVER prints the OAuth token' — confirmed by inspection of its output path (encodes snapshot only).

**Recommendation.** Encode the verified properties as cheap regression guards: a CI grep denylist (no print/os_log of token-bearing vars, no URLSession.shared once SEC-01 lands, endpoint allowlist) so future provider adapters can't silently regress the posture.

**Verification.** inline evidence only (P2/P3 — not adversarially re-verified)

#### SEC-08 · P3 · Med/Low/S — ADR-012 options (c)/(d) — merits check

**Observation.** The freeze on token refresh (option c) and PKCE 'Connect' (option d) is correct, and for a stronger reason than ADR-012 records. (c): using the stored refreshToken would hit Anthropic's token endpoint with Claude Code's client identity, and if Anthropic rotates refresh tokens on use (standard OAuth practice), Houdini's deliberately in-memory-only design — 'never persisted back to the Keychain item Claude Code owns' — would strand the user's Claude Code CLI with a revoked refresh token and silently break their CLI login. (d): no sanctioned public OAuth client exists for third parties (Anthropic's Feb-2026 legal text limits consumer OAuth to Claude Code/claude.ai), so a Houdini PKCE flow would have to pose as Claude Code end-to-end — the clearest possible violation, against demonstrated enforcement (OpenClaw ban).

**Evidence.** ClaudeOAuthCredentialSource.swift:26–27 'The refreshed token is held in memory only — never persisted back to the Keychain item Claude Code owns, nor to disk'; L111 production init defaults `refresher: Refresher? = nil`. ADR-012 L64 freezes both but cites only 'escalate the signal'. External: 'Using OAuth tokens obtained through Claude Free, Pro, or Max accounts in any other product, tool, or service… is not permitted' (Anthropic legal page, 2026-02-20, per theregister.com — web-search verified).

**Recommendation.** Keep the freeze; add the refresh-token-rotation hazard to ADR-012's Why section so a future unfreeze discussion starts from the real failure mode (breaking the user's CLI login), not just 'signal escalation'. If the freeze is ever lifted, refresh must be redesigned (persist rotated tokens — which means writing to Claude Code's Keychain item, a much bigger decision).

**Verification.** inline evidence only (P2/P3 — not adversarially re-verified)

#### SEC-09 · P3 · Low/Low/S — core/ CredentialStore (cookie item protection class)

**Observation.** Houdini's own cookie Keychain item is written with kSecAttrAccessibleAfterFirstUnlock, deliberately so the login-item agent can read it at login. This is a reasonable trade-off but is one notch broader than kSecAttrAccessibleWhenUnlocked: the sessionKey is decryptable while the Mac is locked (post-first-unlock), e.g. by processes running during a locked session. Documented in-code; acceptable, worth recording as a conscious choice.

**Evidence.** CredentialStore.swift:141–149 'Stored `AfterFirstUnlock` so the menu bar agent can read it when launched at login' … `kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock`.

**Recommendation.** Keep as-is (launch-at-login requires it), but note the choice in PROVIDERS.md/ARCHITECTURE so a future security review doesn't rediscover it; if launch-at-login is off, WhenUnlocked would be strictly better — a conditional class is possible but likely over-engineering now.

**Verification.** inline evidence only (P2/P3 — not adversarially re-verified)

**Dimension summary.** Dimension J (security/privacy/ToS) audit of Houdini. The headline claims mostly survive scrutiny: the /usr/bin/security shell-out passes only the service name in argv (secret returns via stdout pipe, no ps leak); no token/cookie is logged or written outside the Keychain; both login WebViews use ephemeral stores; every remote endpoint in code is Anthropic-owned (api.anthropic.com, claude.ai) or GitHub (installer), with a static, tracker-free site — 'no Houdini server' is true (SEC-06). Two real gaps: (1) the polling layer uses URLSession.shared with default config — no ephemeral session, cookie acceptance and disk URLCache left on — so the 'nothing hits disk' guarantee currently depends on server headers, not client code (SEC-01, P1, small fix); (2) install.sh's SHA-256 check is self-attesting (checksums generated and hosted alongside the artifacts), protecting transport integrity but not against a compromised GitHub account, while site copy sells 'checksum-verified · no Gatekeeper prompt' — mildly overstated; add an independent signing key and one honest sentence (SEC-03/04, P2). On ADR-012: the frozen read-only posture is the right call — unfreezing refresh risks breaking the user's Claude Code login via refresh-token rotation (SEC-08), and PKCE has no sanctioned client to use — but the record understates that Houdini actively spoofs the claude-code and Safari UAs at 1,440 req/day, which is what evades Anthropic's Jan-2026 third-party OAuth blocks (SEC-07). The one decision this audit challenges outright is ADR-012 §6: deferring the user-facing transparency line is indefensible for a trust-first product whose users personally carry a documented account-ban risk — recommend posture (b): keep the freeze, ship the disclosure in Settings + privacy page for v1 (SEC-02, P1). All four seeded pendências (PND-SEC-01..04) confirmed; six new pendências added.


### C. Organization & process

#### ORG-01 · P1 · Med/Med/M — root docs — duplication & contradiction

**Observation.** The same load-bearing facts are hand-maintained in 5+ root docs and already disagree. P1's status exists in three incompatible versions: feature_list.json says "next", BACKLOG.md says in-progress `[~]`, CONTEXT.md says decided/capped with focus moved to P2. The ADR-012 freeze is restated in 5 files (BACKLOG 11 mentions, CONTEXT 3, CLAUDE 3, DECISIONS 1, PROVIDERS 1), so every future auth decision must be edited in 5 places or drift.

**Evidence.** feature_list.json L31: P1 "status": "next" · BACKLOG.md L11: "## P1 · App — Login / credential refactor  `[~]`" · CONTEXT.md L85–88: "Login refactor — DECIDED / CAPPED (ADR-012)… Active focus has moved to #2." grep -c 'ADR-012': BACKLOG=11, CONTEXT=3, CLAUDE=3, PROVIDERS=1, DECISIONS=1, feature_list=0.

**Recommendation.** Assign one owner per fact class: work status lives ONLY in BACKLOG.md; decision text ONLY in DECISIONS.md; CONTEXT/CLAUDE link to them instead of restating. Do one dedup pass now and enforce "link, don't restate" in CLAUDE.md's build-loop step 3.

**Verification.** CONFIRMED

#### ORG-02 · P1 · Med/Med/S — git hygiene — uncommitted BACKLOG P4 WIP

**Observation.** The entire uncommitted change to BACKLOG.md is the 27-line P4 self-update section, deliberately kept out of git for 2+ days by instructions that live only in gitignored prompt files. This is fragile (a `git add BACKLOG.md`, checkout, or stash loses or accidentally commits it), it makes the committed backlog lie about what's planned, and it keeps `git status` permanently dirty — which RELEASE.md's own pre-flight ("git status empty") can never pass.

**Evidence.** git diff --stat BACKLOG.md → "1 file changed, 27 insertions(+)" = exactly "## P4 · App — Self-update…" (L121–146). conductor/prompts/10-doc-tidy-push.md L13: "BACKLOG.md has an uncommitted '## P4 · App — Self-update' WIP section — leave it exactly as-is." RELEASE.md L69: "[ ] `master` is green and clean (`git status` empty, CI passing)."

**Challenges.** The conductor/prompts/09+10 instruction to keep P4 uncommitted — reasonable for one orchestration pass, wrong as a standing state.

**Recommendation.** Commit the P4 section (it is plain backlog text with zero runtime risk) as `docs(backlog): capture P4 self-update requirements`. Retire the "keep WIP uncommitted indefinitely" pattern — backlog capture belongs in history, drafts belong in branches.

**Verification.** CONFIRMED

#### ORG-03 · P1 · Med/Med/S — process artifacts — conductor/ vs audit/ sprawl

**Observation.** Process artifacts live in three homes with three different git treatments and no stated convention: conductor/audits (tracked, 1 file), conductor/prompts (gitignored, 10 files), and audit/ (entirely untracked, 9 files / 1,596 lines including this audit's charter and the pendências inventory). The untracked audit corpus can be lost to any clean/clone, and the inventory cites gitignored conductor/prompts files as evidence sources, so its citations are unverifiable from a fresh checkout.

**Evidence.** git ls-files conductor → only "conductor/audits/2026-07-01-site-audit.md". .gitignore L27: "conductor/prompts/". git status → "?? audit/"; wc -l audit/*.md → 1,596 total. audit/03-pendencias-todos.md PND-REL-02 sources: "conductor/prompts/09-orchestrate-site-p2.md L22; conductor/prompts/10-doc-tidy-push.md L13" — both gitignored.

**Recommendation.** Pick one convention: track audit/ (or move it under conductor/audits/) so the audit corpus is versioned, and either track prompts or stop citing them as sources in tracked/deliverable docs. Document the convention in CLAUDE.md's repo map.

**Verification.** CORRECTED (score → P1 (impact Med, risk Med, effort S) — unchanged; the score is fair given the unt)

#### ORG-04 · P2 · Med/Med/M — Build Conductor process — cost/benefit at v1

**Observation.** Judged impartially, the process layer's docs are lean in absolute size (1,068 root-doc lines vs ~15.8k code lines) but its redundancy generates measurable overhead: since FRAME (2026-06-30), 7 of 11 commits are docs/process and only 4 are code; the seeded inventory tags 8 of 53 pendências stale-doc; and ROADMAP re-drifted within a day of a dedicated "refresh stale ROADMAP" commit (bdb1ea7). For a solo OSS project the loop itself (backlog → small units → evidence) is working — the burden is specifically the 11-doc surface that must be synced after every unit.

**Evidence.** git log since 1d742ee: docs/process = 1d742ee, bdb1ea7, 6c6a627, 329e992, f93bb0e, 33f1d22, 34f8bc5 (7) vs code = d7a2f40, 78e2bf3, 19d3ed0, 1d8912b (4). audit/03 tag table: stale-doc = 8/53. LOC: root *.md = 1,068; Swift = 5,864; site src = 9,929. ROADMAP.md Phase 2 still stale post-bdb1ea7 (see ORG-06).

**Challenges.** The FRAME-pass doc-set design in CLAUDE.md (three conductor docs + WORKFLOW + feature_list on top of the six product docs).

**Recommendation.** Keep the loop, shrink the surface: merge WORKFLOW.md into CLAUDE.md, delete or auto-generate feature_list.json (ORG-05), demote ROADMAP.md to explicit history or fold into BACKLOG, and let CONTEXT link rather than restate status. Target ~7 root files whose facts each live in exactly one place.

**Verification.** inline evidence only (P2/P3 — not adversarially re-verified)

#### ORG-05 · P2 · Low/Low/S — feature_list.json — no consumer, no generator

**Observation.** feature_list.json has zero consumers: no code, script, workflow, or site file reads it (scripts/init.sh does not reference it), and despite declaring "generated_from"/"generated_at" there is no generator script — it is hand-written and already stale (P1 "next" contradicts ADR-012's cap; the priorities array omits P4). It is a third hand-synced copy of facts in README/PROVIDERS/BACKLOG.

**Evidence.** grep -rn 'feature_list' (all tracked types) → hits only in BACKLOG.md L168, CLAUDE.md L142 ("both created this pass") and audit/*.md; zero hits in core/, apps/, site/, scripts/, .github/. feature_list.json L31 P1 "status": "next"; L40–41 "generated_from": […], "generated_at": "2026-07-01"; ls scripts → README.md, init.sh only.

**Challenges.** The FRAME decision (BACKLOG.md L168–169 / CLAUDE.md L142–143) to create feature_list.json.

**Recommendation.** Delete it, or make it real: write the generator it claims to have and give it a consumer (e.g. init.sh prints from it, or the site builds the providers table from it). An unconsumed machine-format snapshot is pure maintenance tax.

**Verification.** inline evidence only (P2/P3 — not adversarially re-verified)

#### ORG-06 · P2 · Med/Low/S — ROADMAP.md — drift survived its own refresh

**Observation.** ROADMAP.md is stale beyond what the inventory already lists, one day after a dedicated refresh commit: Phase 2 (menu bar app) carries no ✅ although the app shipped in v0.4.0 and Phases 1/3 are marked; Phase 2 still promises "Writes to App Group + reloadTimelines()" which was never built; and Phase 5 lists the "Claude .sessionCookie fallback (embedded WebView login)" as future work although the cookie WebView shipped. This corrects BACKLOG's "ROADMAP.md refresh — RESOLVED 2026-07-01" claim.

**Evidence.** ROADMAP.md L15 "## Phase 2 — Menu bar app (flagship)" (no ✅; L8 Phase 1 and L20 Phase 3 have ✅); L18 "Writes to App Group + reloadTimelines()."; L30 Phase 5: "Claude .sessionCookie fallback (embedded WebView login)." vs CONTEXT.md L54–55 (cookie path live) and RELEASE.md L13 (v0.4.0 shipped). BACKLOG.md L175–177 claims the refresh "RESOLVED".

**Challenges.** BACKLOG.md L175–177 "ROADMAP.md refresh — RESOLVED 2026-07-01" — the resolution was incomplete.

**Recommendation.** Mark Phase 2 shipped minus the App-Group bullet (move that to Phase 4 where the WidgetKit dependency lives), strike the shipped cookie item from Phase 5, and revise BACKLOG L175–177 from "RESOLVED" to partially done — or demote ROADMAP to explicit history per ORG-04.

**Verification.** inline evidence only (P2/P3 — not adversarially re-verified)

#### ORG-07 · P2 · Low/Low/S — BACKLOG.md — internal self-contradiction

**Observation.** BACKLOG.md contradicts itself within one file: line 96 marks P2 slice 2 (visual polish + shared tokens) `[x]` DONE with commit 1d8912b, while the "Immediate next steps" section still lists the same slice as `[~]` current focus. The P1 header also stays `[~]` although ADR-012 capped it and CONTEXT says active focus moved to P2.

**Evidence.** BACKLOG.md L96: "- [x] Visual polish pass on both surfaces… *(P2 slice 2 — **DONE:** …)*" vs L189: "1. [~] **P2 slice 2** — visual polish + shared visual tokens across the menu bar and desktop widget." L11: P1 header "`[~]`" vs CONTEXT.md L88: "Active focus has moved to #2."

**Recommendation.** Update "Immediate next steps" to slice 3 as the single current item, and mark P1 `[x]` with a "capped by ADR-012" annotation so the header state matches the decision. Consider deleting the "Immediate next steps" section entirely — it duplicates the priority headers and is the part that rots fastest.

**Verification.** inline evidence only (P2/P3 — not adversarially re-verified)

#### ORG-08 · P2 · Low/Low/S — WORKFLOW.md — contradiction + duplication with CLAUDE.md

**Observation.** WORKFLOW.md defines the coding agent as "Claude Code (Opus 4.8, in VS Code)" in its role definition, contradicting both its own Conventions section and CLAUDE.md, which say Fable 5 is the default and Opus is for routine/security-adjacent work. Its Conventions block also restates CLAUDE.md's git rules, model routing, gated actions, and budget rule nearly verbatim — a second copy that must be kept in sync.

**Evidence.** WORKFLOW.md L5: "**Claude Code** (Opus 4.8, in VS Code): executes prompts inside this repo" vs L46–47: "Model routing: Fable 5 by default; Opus 4.8 for routine edits…" and CLAUDE.md §Model routing: "**Fable 5 (default)**". WORKFLOW.md L49–52 duplicate CLAUDE.md §Git workflow (branch-per-unit, no AI trailer, 🔴 gated actions) line for line in substance.

**Recommendation.** Merge WORKFLOW.md's unique content (the Brain⇄Builder response format) into CLAUDE.md as a short section and delete the file, or reduce WORKFLOW.md to the response-format template plus a link. Fix the L5 model label either way.

**Verification.** inline evidence only (P2/P3 — not adversarially re-verified)

#### ORG-09 · P3 · Low/Low/S — monorepo layout — verdict + apps/widget placeholder

**Observation.** The core/ vs apps/ vs site/ split earns its keep: core is a genuinely shared SwiftPM package consumed by path from the menubar app (and the iOS scaffold), with clean boundaries (75/32/21 tracked files in apps/site/core, no cross-imports found). The one weak spot is apps/widget: a directory containing exactly one single-line README, while ARCHITECTURE.md documents it as a working component — the directory's existence overstates the surface.

**Evidence.** apps/menubar/Package.swift L14: ".package(path: \"../../core\")". git ls-files top-level counts: apps=75, site=32, core=21. find apps/widget -type f → only apps/widget/README.md, whose full content is: "WidgetKit / Notification Center widget. Glanceable ~15min (Apple limit, ADR-002)." vs ARCHITECTURE.md L65–68 describing its TimelineProvider/App-Group behavior.

**Challenges.** Mildly challenges keeping the ADR-002 surface as a physical placeholder directory rather than a documented plan.

**Recommendation.** Keep the layout as-is. Either delete apps/widget until a real target exists (ROADMAP Phase 4 + ADR-002 preserve the intent) or expand its README to state explicitly "no target exists yet; see PND-NCW-01" so the tree doesn't imply a buildable surface.

**Verification.** inline evidence only (P2/P3 — not adversarially re-verified)

#### ORG-10 · P3 · Low/Low/S — naming consistency

**Observation.** Naming is consistent across the repo: bundle id org.salomao.houdini (menubar), org.salomao.houdini.mobile + group.org.salomao.houdini (iOS scaffold), domain houdini.salomao.org, repo vitorsalomao05/houdini, Keychain items "Houdini-claude-session"/"Claude Code-credentials". All remaining "Tally" references are intentional: the ADR-009 rebrand record, release-note history, and the tally.salomao.org → houdini 308 redirect in site/vercel.json. No action needed.

**Evidence.** apps/menubar/Info.plist L14: "org.salomao.houdini"; apps/ios/project.yml L42/L48: "org.salomao.houdini.mobile", "group.org.salomao.houdini". grep -rni tally (tracked sources) → only site/vercel.json L6/L12 (host redirect), DECISIONS.md ADR-009, RELEASE.md L33/L61 (redirect smoke-tests).

**Recommendation.** No change. If the iOS app ever ships, confirm the placeholder TODO_TEAM_ID and the .mobile suffix scheme then (already tracked as PND-IOS-03).

**Verification.** inline evidence only (P2/P3 — not adversarially re-verified)

#### ORG-11 · P3 · Low/Low/S — git hygiene — .gitignore coverage & branch state

**Observation.** .gitignore coverage is solid: build/, .build/, node_modules, .env*, secrets/ are ignored; zero build artifacts, .env files, or .DS_Store are tracked; the untracked root build/ holds local v0.4.0 release artifacts and site/.vercel (with a pulled .env.production.local) is ignored via site/.gitignore. Two wrinkles: .claude/ is ignored only via machine-local excludes (.git/info/exclude + ~/.config/git/ignore), so fresh clones on other machines will see .claude/ noise; and work is accumulating on the unmerged docs branch chore/fable-ready (1 commit ahead of master) mixing unrelated units (Fable conventions, audit corpus, P4 WIP) against the stated branch-per-unit convention.

**Evidence.** git ls-files | grep -E 'DS_Store|build/|\.env' → empty. .gitignore L21 "build/"; find build → build/release-v0.4.0/{houdini, SHASUMS256.txt, Houdini.app.zip, NOTES.md}. git check-ignore -v .claude/scheduled_tasks.lock → ".git/info/exclude:8". git branch -vv → "* chore/fable-ready 34f8bc5" vs "master 33f1d22 [origin/master]"; git status → M BACKLOG.md, ?? audit/.

**Recommendation.** Add `.claude/` to the repo .gitignore (keeping settings.local.json ignored for all contributors), merge or close chore/fable-ready, and start distinct branches for the audit corpus and the P4 commit per the documented branch-per-unit rule.

**Verification.** inline evidence only (P2/P3 — not adversarially re-verified)

#### ORG-12 · P3 · Low/Low/S — README/CLAUDE repo maps — omit half the doc set

**Observation.** The repo-layout diagram in README.md — the first map a newcomer reads — lists only 5 of the 11 root docs (README, ARCHITECTURE, DECISIONS, PROVIDERS, ROADMAP) and omits CONTEXT.md, BACKLOG.md, CLAUDE.md, WORKFLOW.md, RELEASE.md, feature_list.json, and conductor/ entirely; CLAUDE.md's own repo map likewise omits conductor/ and audit/. A contributor cannot discover which docs are load-bearing versus process residue from the maps provided.

**Evidence.** README.md L57–72 layout block ends at "scripts/ ← release helpers + init.sh" with no CONTEXT/BACKLOG/CLAUDE/WORKFLOW/RELEASE/feature_list/conductor entries. CLAUDE.md "This is a monorepo" block lists core/, apps/*, site/, install.sh, scripts/ — no conductor/ or audit/. ls root shows all 11 docs + conductor/ + audit/ present.

**Recommendation.** After the ORG-04 consolidation, list the surviving docs in README's layout with one-line roles (or a single line: "process docs: CONTEXT/BACKLOG/CLAUDE — see CLAUDE.md"), and add conductor/ (and audit/, once its tracking is decided) to CLAUDE.md's map.

**Verification.** inline evidence only (P2/P3 — not adversarially re-verified)

**Dimension summary.** Repo organization is structurally sound but process-layer redundancy is its real weakness. The monorepo split (core/ shared SwiftPM package consumed by path from apps/menubar, site/ isolated, 145 tracked files) earns its keep, naming is fully consistent (org.salomao.houdini everywhere; Tally residue is intentional redirect/history), and .gitignore coverage is clean (no tracked artifacts/env/DS_Store). The eleven root docs, however, hand-duplicate the same facts across 5+ files and already disagree: P1's status exists in three incompatible versions (feature_list \"next\" / BACKLOG \"[~]\" / CONTEXT \"capped, moved on\"), BACKLOG contradicts itself about P2 slice 2, WORKFLOW.md contradicts CLAUDE.md on the default model, and ROADMAP re-drifted within a day of its dedicated refresh commit. Measured cost of the Build Conductor layer: 7 of 11 commits since FRAME are docs/process, and 8 of 53 seeded pendências are stale-doc — yet the root docs total only 1,068 lines against ~15.8k lines of code, so the fix is consolidation (merge WORKFLOW into CLAUDE, delete or generate feature_list.json which has zero consumers and no generator, single-owner per fact), not abandoning the process. Git hygiene has two live risks: the 27-line P4 BACKLOG section is deliberately kept uncommitted (protected only by gitignored prompt files, and it blocks RELEASE.md's own \"git status empty\" pre-flight), and the entire 1,596-line audit corpus is untracked while citing gitignored conductor/prompts sources. All three assigned pendências (PND-DOC-06, PND-SITE-01, PND-REL-02) are confirmed as written; seven new pendências were added.


### K. Completeness-critic findings (gaps)

#### GAP-02 · P1 · High/Low/S — cross-finding contradiction — ADR-012 refresh freeze (CORE-02 vs SEC-08)

**Observation.** The audit corpus contains two findings giving OPPOSITE verdicts on the same decision (ADR-012 option (c), the OAuth-refresh freeze), and no finding reconciles them. CORE-02 challenges the freeze: 'freezing refresh does not reduce ToS exposure … The freeze shifts users to the weaker credential rather than avoiding risk.' SEC-08 endorses it: 'The freeze on token refresh (option c) … is correct, and for a stronger reason than ADR-012 records' — arguing that using the stored refreshToken with in-memory-only rotation would strand the user's Claude Code CLI with a revoked refresh token. A reader of the final report gets contradictory guidance on the audit's most-challenged ADR. Both can be partially right: SEC-08's rotation-hazard is a technical blocker CORE-02 never addresses, while CORE-02's UX observation (expired-at-launch CLI users are funneled to the ephemeral cookie WebView — the SAME prohibited surface) survives regardless of whether refresh is unfrozen.

**Evidence.** CORE-02 (verification: CORRECTED): 'Judgment challenging ADR-012 §3: freezing refresh does not reduce ToS exposure … The freeze shifts users to the weaker credential rather than avoiding risk.' SEC-08: 'The freeze on token refresh (option c) and PKCE "Connect" (option d) is correct, and for a stronger reason than ADR-012 records. (c): … would strand the user's Claude Code CLI with a revoked refresh token and silently break their CLI login.' Both texts are in the findings set handed to the report writer; no third finding reconciles them.

**Challenges.** Reconciles CORE-02 vs SEC-08; net position revises ADR-012 §3's rationale, not its outcome

**Recommendation.** Reconcile before writing the report: state that the freeze on ACTIVE refresh stands for SEC-08's rotation-hazard reason (superseding ADR-012's stated rationale), while CORE-02's real defect is the resolution/UX layer — an expired token should surface 'token expired, run claude to re-auth' and re-detect the restored credential (CORE-01/MB-02), not silently route the user to the cookie WebView. One combined recommendation, two distinct fixes.

**Verification.** inline evidence only (P2/P3 — not adversarially re-verified)

#### GAP-01 · P2 · Med/Med/S — install.sh / uninstall story

**Observation.** The uninstall story is incomplete and undocumented anywhere users can find it later. install.sh's header claims it 'prints exactly how to uninstall' (L14), but the printed steps (L138-141) remove only the login item, the app bundle, and the CLI — they leave behind the 'Houdini-claude-session' Keychain item holding the user's live claude.ai session cookie (which the in-app Sign out DOES delete via nativeDeleteGenericPassword, ClaudeSession.swift:79-80), the app's UserDefaults preferences, and any URLSession disk cookie/cache storage SEC-01 identifies under ~/Library/HTTPStorages. Neither the site (FAQ/install/guide) nor README mentions uninstalling at all — the instructions exist only in the terminal scrollback at install time. For a trust-first product, uninstall-without-prior-signout strands a live credential in the Keychain indefinitely.

**Evidence.** install.sh:14 '# 5. Is idempotent (safe to re-run) and prints exactly how to uninstall.'; install.sh:138-141 prints only: '--unregister-login-item', 'rm -rf $APP', 'rm -f $BIN_DIR/houdini'. ClaudeCookieProvider.swift:23 'public static let keychainService = "Houdini-claude-session"'. ClaudeSession.swift:79-80 'func signOut() { try? store.nativeDeleteGenericPassword('. grep -rn -i uninstall over *.md/*.astro/*.ts returns hits ONLY in install.sh, Main.swift comment, and audit/07 — zero in site/ or README.md.

**Recommendation.** Extend the uninstall printout to include credential cleanup ('open Houdini and Sign out first, or: security delete-generic-password -s Houdini-claude-session' plus 'defaults delete org.salomao.houdini'), and add an uninstall answer to the site FAQ so the steps survive the terminal session. Fold the owned-file manifest idea from PND-REL-03 into the same list.

**Verification.** inline evidence only (P2/P3 — not adversarially re-verified)

#### GAP-03 · P2 · Med/Low/S — cross-finding tension — DX-04 CI baseline cannot build the menubar app as recommended (vs DX-02)

**Observation.** DX-04 (P1) recommends a CI baseline including 'menubar: ./build.sh release + run the binary's --widgettest' on free GitHub-hosted macOS runners, but DX-02's own root-cause analysis proves that exact build fails on the runner class the repo's workflow pins: WidgetGlass.swift's `.glassEffect(in:)` call requires the macOS 26 SDK, and release.yml pins macos-14 and deliberately selects Xcode 16. As written, adopting DX-04 reproduces the INS-01 failure in the new PR workflow on day one. No finding's recommendation names the prerequisite: either bump the runner image/Xcode to one shipping the macOS 26 SDK, or add a compile-time guard (e.g. `#if compiler`/SDK-availability check) around the glassEffect branch so the app compiles on older SDKs.

**Evidence.** WidgetGlass.swift:149-151: '} else if #available(macOS 26, *) { … Color.clear.glassEffect(in: shape)' (runtime guard only, no compile-time guard). release.yml:21 'runs-on: macos-14'; :30 'XC=$(ls -d /Applications/Xcode_16*.app …)'; :33 'sudo xcode-select -s'. DX-04 text: '(2) menubar: ./build.sh release + run the binary's --widgettest'. DX-02 text: 'compiling it requires the macOS 26 SDK … the build is guaranteed to fail.'

**Challenges.** Qualifies DX-04's recommendation using DX-02's own evidence

**Recommendation.** Amend DX-04's recommendation in the report to include the prerequisite from DX-02: pick a runner image whose Xcode ships the macOS 26 SDK (or pin DEVELOPER_DIR to it), or gate the glassEffect call behind a compile-time SDK check so build.sh compiles on Xcode 16. State which one the report endorses so the CI unit is actionable in a single pass.

**Verification.** inline evidence only (P2/P3 — not adversarially re-verified)

#### GAP-04 · P2 · Med/Med/S — .github / vulnerability-disclosure policy (SECURITY.md)

**Observation.** No audit finding covers the security-disclosure channel. The repo has no SECURITY.md, CONTRIBUTING.md, or CODE_OF_CONDUCT anywhere; .github/ contains only workflows/release.yml; and the site's only outbound contact surfaces are the GitHub repo and releases links — no mailto, no security contact. For a public repo marketed as 'free & open source' whose app handles Keychain credentials and OAuth tokens, the only way for a researcher to report a token-handling vulnerability today is a public GitHub issue, i.e. immediate 0-day disclosure. This is the one repo-hygiene file with real security consequence, and it costs minutes to add.

**Evidence.** `git ls-files | grep -iE 'security|contributing|code_of_conduct|license|copying'` → no output, exit=1. `ls -R .github` → 'workflows/ release.yml' only. site/src/config.ts:27-29: github: 'https://github.com/vitorsalomao05/houdini', changelog: '.../releases' — grep for 'mailto|contact' across site/src returns only these GitHub links.

**Recommendation.** Add SECURITY.md (supported version = the single pinned release per ADR-010, private reporting route) and enable GitHub Private Vulnerability Reporting on the repo. Optionally fold a 'report a security issue' line into the site privacy page, which already leads with 'An app that touches your logins should earn it'.

**Verification.** inline evidence only (P2/P3 — not adversarially re-verified)

#### GAP-05 · P3 · Med/Low/S — README.md — zero product imagery

**Observation.** The root README — the page the site's 'Open source' trust chip and install-page links send visitors to — contains no screenshot or image of any kind (79 lines, no image syntax), for a product whose entire pitch is visual (menu bar + desktop widget). Polished, current assets already exist in-repo (apps/menubar/docs/screenshots/menubar-dark.png, popover-dark.png; site/src/assets/desktop-widget.png is a real screenshot per SITE-08), so this is pure assembly work. No audit finding covers README's presentation; DOC-12 covers only its repo-layout tree.

**Evidence.** `grep -rn -iE 'screenshot|\!\[|\.png|\.jpg' README.md` → no hits (only apps/menubar/README.md:23 matches, and that is the --snapshot command). `grep -c '' README.md` → 79 lines. In-repo assets exist: apps/menubar/docs/screenshots/{menubar-dark,popover-dark,settings-dark}.png (git-tracked), site/src/assets/desktop-widget.png.

**Recommendation.** Add one hero screenshot (menu bar + popover, dark) near the top of README, sourced from the existing docs/screenshots corpus after regenerating it (see GAP-06). One image; keep the zero-clutter ethos.

**Verification.** inline evidence only (P2/P3 — not adversarially re-verified)

#### GAP-06 · P3 · Low/Low/S — apps/menubar/docs + design — unexamined 5.6MB tracked screenshot corpus, stale vs shipped UI

**Observation.** Nobody in the audit examined apps/menubar/docs/ or design/. docs/ holds 5.6MB across 32 git-tracked files; the 25-PNG docs/review/ set was last committed 2026-06-19 (df3d8fe), BEFORE the P2 accessibility and visual-polish slices shipped (2026-07-01/02, commits 19a... and 1d8912b 'visual polish + shared tokens'), so the tracked visual 'review' record documents the pre-polish UI and no longer matches the shipped app. Every clone pays the 5.6MB; the review set has no current consumer (README references only docs/screenshots as the --snapshot output dir). design/ (icon/glyph render scripts + AppIcon sources) is fine and current.

**Evidence.** `git ls-files apps/menubar/docs apps/menubar/design | wc -l` → 32; `du -sh apps/menubar/docs` → 5.6M. `git log --oneline -1 -- apps/menubar/docs/review` → 'df3d8fe feat(menubar): finish popover to match the desktop widget' (Jun 19). P2 polish landed later: '1d8912b feat(menubar): visual polish + shared tokens (P2 slice 2)' (recent commits list). apps/menubar/README.md:23: './build/Houdini.app/Contents/MacOS/Houdini --snapshot docs/screenshots' — review/ is referenced nowhere.

**Recommendation.** Regenerate docs/screenshots from the current build (the --snapshot flag makes this one command) and delete or regenerate docs/review/ — it is a one-time review artifact of a superseded UI. Decide whether review corpora belong in git at all or in the (already gitignored) build/ scratch area.

**Verification.** inline evidence only (P2/P3 — not adversarially re-verified)

**Dimension summary.** Completeness pass over the 106-finding corpus. Charter dimensions A–J all have corresponding findings, and all 53 seeded PND rows carry validations — no unvalidated inventory rows remain. Six real gaps found. Two are cross-finding coherence problems the report writer MUST resolve: (GAP-02) CORE-02 and SEC-08 give opposite verdicts on the ADR-012 refresh freeze — reconcilable because SEC-08's refresh-token-rotation hazard is a technical blocker CORE-02 never addresses, while CORE-02's UX complaint survives either way; (GAP-03) DX-04's P1 CI recommendation ('./build.sh release' on GitHub runners) fails per DX-02's own root cause (WidgetGlass.swift:149 needs the macOS 26 SDK; release.yml pins macos-14/Xcode 16) unless a runner bump or compile-time guard is named. Four are coverage blind spots: the uninstall story leaves a live claude.ai session cookie in the Keychain and is documented only in install-time scrollback (GAP-01); no SECURITY.md/disclosure channel exists for a credential-handling 'open source' app (GAP-04); README has zero product imagery (GAP-05); and the unexamined apps/menubar/docs/ dir carries a 5.6MB tracked screenshot corpus whose review set predates the shipped P2 polish (GAP-06). Blind spots checked and CLEAN (no finding warranted): app icon exists and is wired (Resources/AppIcon.icns + CFBundleIconFile, build.sh guard); macOS version gating is correct (Info.plist LSMinimumSystemVersion 14.0 + install.sh preflight); the Apple Silicon-only requirement is stated consistently on site, README, and installer (config.ts:127 even says 'No Intel build is shipped'); the site handles prefers-reduced-motion properly (global.css:170,410, Stepper, Layout); in-app Sign out does delete the Houdini Keychain item; favicon/og assets exist; no .DS_Store or build artifacts are tracked; crash-reporting posture (none) is consistent with the no-telemetry guardrail. One audit-artifact correction for the writer: the charter scaffold's dimension-D lead claims 'RELEASE.md … does not exist' — it exists at the repo root (5,963 bytes) and a dozen findings correctly cite it; the charter lead is stale, not the findings. Duplicate-pair note for editing: ARC-07/CORE-10, CORE-03/SEC-05, MB-01/SITE-04, MB-06/CORE-06(rate-limit copy), INS-04/SEC-03 cover the same defects and should be merged or cross-referenced in the final report.

## 3. Cross-cutting consolidation (what the 112 findings actually mean)

Many findings across dimensions are facets of one defect. The canonical themes, used by
`04` (opportunities) and `05` (v1 plan):

| Theme | Canonical statement | Member findings | Gate for v1? |
|---|---|---|---|
| **T1 · Release pipeline is fiction** | CI never built a release (4/4 failed on the glassEffect/macOS-26-SDK skew); shipped binaries are hand-built; two publishers race the same tag; RELEASE.md §2 omits the Info.plist bump; zero verification before publish | INS-01, INS-02, INS-06, DX-01, DX-02, DX-11, MB-08, MB-09 | **Yes (P0)** |
| **T2 · Verification is silently green** | `swift test` exits 0 running 0 tests on the dev machine; 3 of 4 app smoke flags cannot fail; no PR/push CI at all; selftest is a hand-kept duplicate | DX-03, DX-04, DX-06, DX-07, CORE-09, DX-05 | **Yes (P1)** |
| **T3 · Sticky signed-out auth** | Credential appearance/expiry is never re-detected at runtime — a user who installs Houdini first and logs into Claude Code second stays signed out until relaunch | CORE-01, MB-02, ARC-04 | **Yes (P0)** |
| **T4 · Site states falsehoods** | No LICENSE yet "open source" everywhere; /reveals sells a nonexistent Tokens capability; /guide teaches the wrong threshold scale; cookie copy promises "no repeated logins" that ADR-012 froze away; API-usage copy in present tense | SITE-01, SITE-02, SITE-03, SITE-04, SITE-07, MB-01 | **Yes (P0)** |
| **T5 · Docs describe a fictional architecture** | App-Group/WidgetKit bridge, phantom Scheduler/Cache + backoff, "Claude Code" item name, Übersicht-as-live, stale survey sections, self-contradicting BACKLOG/ROADMAP | ARC-01, ARC-02, DOC-01..03, DOC-05, DOC-06, DOC-08, DOC-10, PER-02, ORG-06, ORG-07 | **Yes (P1)** |
| **T6 · ToS posture is silent** | A privacy-first product reads a ToS-restricted credential and spoofs the claude-code UA without telling the user; ADR-012 §6 made the disclosure optional | SEC-02, SEC-07, SEC-08 (reconciled: freeze stands, disclosure becomes mandatory) | **Yes (P0 decision)** |
| **T7 · WidgetKit is hard-blocked; NSPanel is the strategy** | Ad-hoc signing cannot use App Groups (macOS 15+, DTS-confirmed); sandboxed-appex + SPM-cannot-build-appex stack on top; NSPanel is current, supported API and the only 60s surface — needs an ADR | ARC-05, ARC-09, PER-01, spec-06 review + research | Decision (ADR-013) |
| **T8 · Update feature is viable with 5 corrections** | Option (a) endorsed; CLI must rename-aside before delegating (cp-in-place = kernel signature-cache crash); pre-stash the .app (required); latest-only `<version>`; TAG-match guard; tty-detached spawn for login-item neutrality | spec-07 review + research | Phase 3 |
| **T9 · Prune policy overreaches** | Deleting old releases+tags kills rollback, breaks saved one-liners (v0.3.0 URL already 404), and `update <old>` is a null set — "one advertised version" needs only the *pointers* pruned | INS-03 | Decision (revise ADR-010) |
| **T10 · Small security hardening** | Ephemeral URLSession (no cookie jar/disk cache on credentialed GETs); redirect-guard scheme check; per-poll `claude --version` spawn; Gatekeeper-copy honesty; uninstall leaves credentials; no SECURITY.md | SEC-01, SEC-03, SEC-04, SEC-05, CORE-07, GAP-01, GAP-04 | P1/P2 mix |
| **T11 · Process layer costs more than it returns** | Same facts hand-kept in 5+ docs already disagree; feature_list.json consumer-less; WORKFLOW.md contradicts CLAUDE.md; audit/ untracked; P4 deliberately uncommitted | ORG-01..05, ORG-08, DOC-09, DOC-11 | **Yes (P1, slim it)** |
| **T12 · A11y follow-through** | Sub-pages missed by the landing-only fix; menu-bar color-only severity likely fails AA in light mode; Settings has no Dynamic Type; desktop-widget keyboard path unverified | SITE-06, MB-04, MB-07, MB-12, MB-03 | P1/P2 mix |

## 4. What was checked and found healthy (for balance)

- **install.sh delivers every advertised guarantee** — preflight, TLS-pinned fetch, SHA-256 abort-on-mismatch, no-sudo, quarantine strip, offered-not-forced login item, idempotence (INS-09, verified line-by-line).
- **The Keychain-only / no-server privacy claims hold at the code level** — no token/cookie ever hits disk/logs; both WebViews use ephemeral stores; every reachable endpoint is Anthropic-owned or GitHub; the `security` shell-out does not leak via argv (SEC-06, ARC-06).
- **v0.4.0 release integrity checks out** — published SHASUMS256.txt matches RELEASE.md's recorded checksums and the local staging dir byte-for-byte; exactly one release/tag exists as ADR-010 dictates.
- **apps/menubar is a genuinely solid v1 flagship** — all five UX states rendered distinctly on both surfaces from one shared component/token layer; generation-stamped single-in-flight polling; strong VoiceOver/Dynamic Type/Reduce-Motion work from P2 slices 1–2 (menubar dimension summary).
- **core/ is small, Swift-6-Sendable-clean, with excellent injectable seams** and token-safe error messaging (CORE-12).
- **Naming and monorepo layout earn their keep** (ORG-09, ORG-10); .gitignore hygiene is clean (DX-09).
