# 03 — Pendências & TODOs (neutral, sourced inventory)

> **Purpose.** A single, exhaustive, *factual* consolidation of every PENDING item in the
> Houdini monorepo — open work, gaps, ideas, decisions, stale docs, test holes, tech debt, and
> WIP. It is compiled by scanning the docs, the Build-Conductor artifacts, and the code.
>
> **This is not a prioritization.** No item is ranked, judged, or scheduled here; a later
> impartial audit will do that. Items already marked "decided" elsewhere (notably ADR-012) are
> recorded as **OPEN DECISIONS the audit is free to revisit**, not as settled truth — the tag
> `open-decision` on such rows means "a decision exists and can be challenged," not "unresolved."
>
> **Every row carries:** a stable id, a one-line description, a SOURCE (file:line or doc §), and
> one raw tag from: `bug` · `missing-feature` · `idea` · `open-decision` · `stale-doc` ·
> `test-gap` · `tech-debt` · `wip`.
>
> Line numbers reflect the repo at the time of writing (post-v0.4.0). Paths are repo-relative.
> Scan date: 2026-07-02.
>
> **VALIDATED by the impartial deep audit, 2026-07-03.** Every one of the 53 rows was
> re-derived from the repo by an independent agent: **48 confirmed as written, 5 corrected**
> (PND-DOC-02, PND-DOC-03, PND-DOC-05, PND-SITE-04, PND-TEST-02 — corrections applied inline
> below, marked `[CORRECTED]`), **0 refuted**. The audit also surfaced **~59 additional
> pendências** — see the new section "Additions from the deep audit" at the end. Full
> evidence for every validation and addition: `02-technical-diagnosis.md`.

---

## Count tables

### Items per area

| Area | Count |
|---|---:|
| App / core | 6 |
| Menu bar + desktop widget | 6 |
| Notification Center widget (`apps/widget`) | 3 |
| iOS (`apps/ios`) | 6 |
| Site | 8 |
| Installer / scripts / release | 4 |
| Providers | 5 |
| Testing / CI | 5 |
| Docs / process | 6 |
| Security / ToS | 4 |
| **Total** | **53** |

### Items per tag

| Tag | Count |
|---|---:|
| `open-decision` | 11 |
| `missing-feature` | 10 |
| `stale-doc` | 8 |
| `test-gap` | 6 |
| `tech-debt` | 5 |
| `wip` | 5 |
| `idea` | 4 |
| `bug` | 2 |
| `placeholder / scaffold` (sub-set of missing-feature, called out where relevant) | — |
| **Total** | **53** |

> Tag totals sum to 53 (each item has exactly one tag).

---

## App / core (`core/`)

| ID | Description | Source | Tag |
|---|---|---|---|
| PND-APP-01 | P1 login/credential refactor is **capped at slice (a)** (broadened discovery of an *existing* credential). A user with **no** Claude Code credential anywhere is out of scope *by decision* — the whole cap is challengeable. | `BACKLOG.md` §"P1 · App — Login / credential refactor" L11–L83; `DECISIONS.md` ADR-012 §Decision.5 L66 | open-decision |
| PND-APP-02 | OAuth **token refresh is built but deliberately unwired** — `ClaudeOAuthCredentialSource` ships with `refresher == nil`, so an expired access token degrades to `.authExpired` exactly as before (frozen by ADR-012, not merely awaiting sign-off). | `core/Sources/FetcherCore/ClaudeOAuthCredentialSource.swift` L20–L27, L108–L117; `BACKLOG.md` L54–L57 | open-decision |
| PND-APP-03 | Candidate **(c) first-run OAuth PKCE "Connect"** — Houdini obtaining its own refreshable, revocable, Keychain-only Anthropic token — designed and named as the durable answer for true non-CLI users, but **frozen / not pursued**. | `BACKLOG.md` L61–L70; `conductor/prompts/02-p1-login-refactor.md` L202–L206; `DECISIONS.md` ADR-012 §Decision.3 L64 | missing-feature |
| PND-APP-04 | Candidate **(b) claude.ai cookie-flow hardening** (persistent/shared WebView store or paste-session, proactive expiry re-auth) — frozen; would need an ADR-005 revision. | `BACKLOG.md` L58–L60; `conductor/prompts/02-p1-login-refactor.md` L199–L201; `DECISIONS.md` ADR-012 §Decision.3 L64 | missing-feature |
| PND-APP-05 | `CredentialStore.readGenericPassword` still shells out to `/usr/bin/security` on every 60s poll; TODO to migrate the default to the native `SecItemCopyMatching` path once Houdini ships as a signed app added to the Keychain item's ACL. | `core/Sources/FetcherCore/CredentialStore.swift` L48–L54 (`TODO(phase ≥2, signed app)`) | tech-debt |
| PND-APP-06 | Root-cause **C** (from FRAME): even real CLI users silently lose OAuth when the access token expires (`refreshToken` never used in production). Left in place because refresh is frozen (see PND-APP-02); the underlying degradation persists. | `BACKLOG.md` L47–L48 (Root cause C) | tech-debt |

---

## Menu bar + desktop widget (`apps/menubar/`)

| ID | Description | Source | Tag |
|---|---|---|---|
| PND-MB-01 | **P2 slice 3 — verify gauges / reset timers / overage against real Claude Pro/Max data** (limits, timers, extra-usage) — the last open P2 sub-task. | `BACKLOG.md` L97, L190 (`[ ] Verify against real Claude Pro/Max data`); `conductor/prompts/08-p2-widget-a11y.md` L11 | test-gap |
| PND-MB-02 | Menu bar app does **not** write a snapshot to an App Group container and does **not** call `WidgetCenter…reloadTimelines()`, though ARCHITECTURE.md's diagram + prose say it does ("writes value to App Group + `WidgetCenter.shared.reloadAllTimelines()`"). The only `UserDefaults(suiteName:)` uses are test/snapshot harnesses. | code: `apps/menubar/Sources/Houdini/` (no `WidgetCenter`/`reloadAllTimelines`/App-Group write; suiteName only in `WidgetTest.swift` L30/L33, `SelfTest.swift` L79/L86, `Snapshotter.swift` L61) vs `ARCHITECTURE.md` L32–L33, L50 & `apps/menubar/README.md` L63–L65 ("Not in this phase … WidgetKit/App-Group writes") | stale-doc |
| PND-MB-03 | App README explicitly defers **other providers, WidgetKit/App-Group writes, and distribution** to "later phases." | `apps/menubar/README.md` L63–L65 | missing-feature |
| PND-MB-04 | Launch-at-login toggle works on this ad-hoc-signed build, but a **Developer ID signature** is what "guarantees it everywhere" — noted as an open gap dependent on signing. | `apps/menubar/README.md` L44–L46 | tech-debt |
| PND-MB-05 | P2 is `[~]` in progress at the top level (slices 1 & 2 done, slice 3 open) — the surface is not signed off as fully polished end to end. | `BACKLOG.md` L85 (`P2 … [~]`), L97 | wip |
| PND-MB-06 | Cross-cutting **accessibility baseline** (WCAG 2.1 AA across app UI, no regressions) is an open, ongoing checklist item, not a closed deliverable. | `BACKLOG.md` L154 (`[ ] Accessibility baseline`) | open-decision |

---

## Notification Center widget (`apps/widget/`)

| ID | Description | Source | Tag |
|---|---|---|---|
| PND-NCW-01 | `apps/widget` is a **README-only placeholder** — one line, **no Swift target / no built widget** in the tree — despite ARCHITECTURE.md describing a full `TimelineProvider`/App-Group WidgetKit widget. | `apps/widget/README.md` (only file; single line) vs `ARCHITECTURE.md` §"WidgetKit widget — `apps/widget`" L65–L68; `feature_list.json` L10 (`"status":"planned"`, "README placeholder today (no built target in tree)") | missing-feature |
| PND-NCW-02 | WidgetKit widget capped by Apple at ~15 min refresh (ADR-002) and intentionally **unadvertised** on the site — an accepted constraint recorded as a standing surface, not shipped. | `DECISIONS.md` ADR-002 L10–L13; `README.md` L35–L37; `feature_list.json` L10 | open-decision |
| PND-NCW-03 | The App-Group bridge the widget depends on (host app writing the cached snapshot) is itself unbuilt — see PND-MB-02; the widget cannot function until both halves land. | `ARCHITECTURE.md` L65–L68 (widget "reads only the cached value from the App Group") + PND-MB-02 | missing-feature |

---

## iOS (`apps/ios/`)

| ID | Description | Source | Tag |
|---|---|---|---|
| PND-IOS-01 | Entire iOS app + WidgetKit extension are **source + scaffold only, never compiled** — needs full Xcode + iOS SDK (CommandLineTools cannot build them). | `apps/ios/README.md` L1–L6; `apps/ios/PLAN.md` L1–L7, L231–L245; `DECISIONS.md` ADR-008 L41 | missing-feature |
| PND-IOS-02 | Blocked on the **Apple Developer Program ($99/yr)** — no free install-by-link on iOS; TestFlight → App Store is the only path. | `apps/ios/PLAN.md` L117–L140, L231–L245; `apps/ios/README.md` L54–L59; `ROADMAP.md` Phase 9 L50–L51 | open-decision |
| PND-IOS-03 | **Placeholder Team ID + bundle IDs** — `DEVELOPMENT_TEAM: "TODO_TEAM_ID"`, bundle IDs `org.salomao.houdini.*`, App Group `group.org.salomao.houdini` all marked TODO; unblocked only after enrollment. | `apps/ios/project.yml` L7–L8, L22; `apps/ios/PLAN.md` L241–L242; `apps/ios/HoudiniMobile/HoudiniMobileApp.swift` L6; `apps/ios/Shared/SharedSnapshot.swift` L12 | placeholder / scaffold |
| PND-IOS-04 | iOS-readiness of FetcherCore is a **documented assumption, not verified** — the `#if os(macOS)` guards are mechanical but iOS compilation "can only be verified in Xcode," so it stays unproven. | `apps/ios/PLAN.md` L173–L177 (§5 Validation) | test-gap |
| PND-IOS-05 | `HoudiniWidget` iOS widget target is a "placeholder, but structurally complete" WidgetKit extension — builds only in Xcode. | `apps/ios/HoudiniWidget/HoudiniWidget.swift` L5, L12; `apps/ios/HoudiniWidgetBundle.swift` L7; `apps/ios/README.md` L32 | placeholder / scaffold |
| PND-IOS-06 | **iOS App Store distribution** (TestFlight beta → public App Store, Beta App Review, App Review) is a whole unbuilt release track. | `apps/ios/PLAN.md` §4 L117–L140, §7 L204–L228; `ROADMAP.md` Phase 9 L50–L51 | missing-feature |

---

## Site (`site/`)

| ID | Description | Source | Tag |
|---|---|---|---|
| PND-SITE-01 | **P3 top-level `[~]`** — "ongoing site polish + feature/idea stream" remains open; the Parking lot is empty and waiting for ideas. | `BACKLOG.md` L99, L119, L194–L196 | wip |
| PND-SITE-02 | Audit finding **B/[P1] "sharpen the hero H1 toward Claude/menu-bar"** — decided KEEP GENERIC (ToS-gated per ADR-012), i.e. intentionally *not* actioned; the audit's recommendation is unshipped and the decision is challengeable. | `conductor/audits/2026-07-01-site-audit.md` §B L37–L39, §F.4 L93; `BACKLOG.md` L116–L117; `DECISIONS.md` ADR-012 | open-decision |
| PND-SITE-03 | Audit finding **D "explicit 'Mac → Anthropic, no Houdini server' trust sentence"** — decided DEFERRED/optional (ToS-gated per ADR-012); the explicit sentence is only *implied* on the landing page today. | `conductor/audits/2026-07-01-site-audit.md` §D L70–L80; `BACKLOG.md` L117–L118; `DECISIONS.md` ADR-012 §Decision.6 L67 | open-decision |
| PND-SITE-04 | **[CORRECTED 2026-07-03]** The "same links twice" claim is wrong at the accessibility-tree level: mobile "Primary" exposes only logo/GitHub/Install while "Sections" holds the routes, and on desktop "Sections" is `display:none` (removed from the AT tree) — the two navs never expose the same links simultaneously; distinctly-labelled landmarks are the APG-recommended pattern. Residual issue is at most cosmetic DOM duplication. **Downgraded to a P3 nicety / non-issue.** | `site/src/components/Nav.astro:17-20` (`hidden md:flex`) vs `:60-63` (`md:hidden`); original claim `conductor/audits/2026-07-01-site-audit.md` §B[P3] L48–L49 | tech-debt |
| PND-SITE-05 | Audit **P3 — pervasive 12px supporting text** (meta lines, trust chips, footer) near the legibility floor; suggested bump to 13–14px or lighten. Not in the shipped quick-wins. | `conductor/audits/2026-07-01-site-audit.md` §B[P3] L50–L51, §C[P3-adjacent] | tech-debt |
| PND-SITE-06 | Audit **watch-item — plural "Surfaces" nav + "menu bar AND on your desktop" phrasing** risks a two-product smell (ADR-010/011 compliance watch). Flagged, no change recorded. | `conductor/audits/2026-07-01-site-audit.md` §B[P2] L46–L47, §E.1 L83–L85; nav still `{label:"Surfaces"}` at `site/src/config.ts` L54 | idea |
| PND-SITE-07 | Sub-pages **/install, /guide, /privacy, /reveals, /surfaces, /faq were NOT audited** (landing page only) — the two-product / Notification-Center / a11y checks do not cover them; a `/surfaces` page could still describe multiple surfaces. | `conductor/audits/2026-07-01-site-audit.md` §"COULD NOT / DID NOT CHECK" L96–L102 | test-gap |
| PND-SITE-08 | Audit could not render below ~406px CSS width; 390px was **approximated at 406px**, and screen-reader/keyboard were DOM/focus-*simulated*, not a live AT session — borderline ~4.66:1 contrasts "verify with a formal tool." | `conductor/audits/2026-07-01-site-audit.md` §"COULD NOT / DID NOT CHECK" L96–L102, §C note L67–L68 | test-gap |

---

## Installer / scripts / release

| ID | Description | Source | Tag |
|---|---|---|---|
| PND-REL-01 | **P4 · `houdini update` self-update / clean-upgrade command** — one command to SHA-256-verify + install the latest release, clean up old-version artifacts, and report the new version. Full requirements captured but **not scheduled** (future wave after P1–P3). | `BACKLOG.md` §"P4 · App — Self-update" L121–L146 | missing-feature |
| PND-REL-02 | The **P4 section is uncommitted WIP** — two conductor prompts explicitly instruct leaving the "uncommitted P4 · Self-update WIP section" untouched, i.e. it is not yet part of committed backlog state. | `conductor/prompts/09-orchestrate-site-p2.md` L22; `conductor/prompts/10-doc-tidy-push.md` L13 | wip |
| PND-REL-03 | P4 open questions: (a) **owned-file manifest** needed so cleanup is exhaustive-but-safe (least-privilege); (b) **decide the surface** — CLI subcommand vs menu-bar "Check for updates" vs both. No `update`/`upgrade` subcommand exists in the CLI today. | `BACKLOG.md` L143–L146; code: `core/Sources/houdini/main.swift` (no `update`/`upgrade` handling) | open-decision |
| PND-REL-04 | **Sparkle auto-update + notarized DMG + Homebrew cask** remain a documented *future* option (deferred, not blocking) per ADR-006; the $99-program decision is explicitly left "decide then." | `DECISIONS.md` ADR-006 L29–L32 (Future decision, deferred); `ROADMAP.md` Phase 8 L43 | open-decision |

---

## Providers

| ID | Description | Source | Tag |
|---|---|---|---|
| PND-PROV-01 | **Gemini gap** — Google Gemini is advertised as a "Planned" provider in `README.md`, `CONTEXT.md`, and `feature_list.json`, but has **no entry in `PROVIDERS.md` and no phase in `ROADMAP.md`**. BACKLOG flags: "spec it or drop the claim." | `README.md` L10, L50; `CONTEXT.md` L16; `feature_list.json` L17 vs absence in `PROVIDERS.md` & `ROADMAP.md`; `BACKLOG.md` L178–L179, L191–L193; `CLAUDE.md` §Open questions L157–L158 | stale-doc |
| PND-PROV-02 | **OpenAI Platform adapter** (2nd provider; org admin key, `$` + tokens, keys Keychain-only) — designed in ADR-011 / PROVIDERS.md, **not built in this round**. | `PROVIDERS.md` §openai-platform L59–L62, §"OpenAI Platform = the planned 2nd provider" L105–L109; `DECISIONS.md` ADR-011 L56; `ROADMAP.md` Phase 5 L31 | missing-feature |
| PND-PROV-03 | **Anthropic Console admin-API adapter** (usage_report / cost_report) — secondary provider, specced, not built. | `PROVIDERS.md` §anthropic-console L54–L57; `ROADMAP.md` Phase 5 L31; `README.md` L51 | missing-feature |
| PND-PROV-04 | **ChatGPT Plus experimental adapter** — best-effort "limited / OK" state (no reliable gauge); explicitly experimental, not built. | `PROVIDERS.md` §chatgpt-plus L64–L67, build order L76; `ROADMAP.md` Phase 5 L32; `feature_list.json` L19 | missing-feature |
| PND-PROV-05 | **Provider switcher UI in app Settings** (registry-driven rows, per-`authMethod` connect flows) — design only, "not yet built." | `PROVIDERS.md` §"Provider switcher (app Settings) — design, not yet built" L79–L118; `ARCHITECTURE.md` §"Provider switcher…" L70–L80; `DECISIONS.md` ADR-011 L56 | missing-feature |

---

## Testing / CI

| ID | Description | Source | Tag |
|---|---|---|---|
| PND-TEST-01 | **No automated tests in `apps/menubar`, `apps/widget`, `apps/ios`, or `site/`** — only `core/` has real tests (`FetcherCoreTests` + `houdini-selftest`); the apps rely on built-binary smoke flags (`--selftest`/`--metrictest`/`--snapshot`/`--launchtest`). | `CLAUDE.md` §Survey findings "Test setup" L128–L133; `BACKLOG.md` L166–L167; dirs confirm (no `Tests/` under `apps/*`, `site/`) | test-gap |
| PND-TEST-02 | **[CORRECTED 2026-07-03]** No CI exists for site or apps — AND the only workflow (`release.yml`) is **broken: every run has failed** (4/4 tag pushes — v0.2.0 ×2, v0.3.0, v0.4.0 — die compiling `WidgetGlass.swift:149` `glassEffect`, which needs the macOS 26 SDK the pinned Xcode 16 runner lacks). All shipped releases were **built and uploaded manually from the dev machine**, contradicting release.yml/init.sh/CLAUDE.md which describe CI as the release builder. | `gh run list --workflow=release.yml` → 4× `completed failure`; local `build/release-v0.4.0/SHASUMS256.txt` byte-identical to the published asset; `.github/workflows/` contains only `release.yml` | test-gap |
| PND-TEST-03 | **End-to-end coverage for the non-CLI cookie user is still missing** — slice (a) added resolver + selftest tests for OAuth discovery/refresh, but the cookie-user path is untested (part of frozen (b)/(c)). | `BACKLOG.md` L77–L80 ("Still open: end-to-end coverage for the non-CLI cookie user") | test-gap |
| PND-TEST-04 | **P2 real-data verification** (gauges/timers/overage vs real Claude Pro/Max) is an untested-against-reality gap. (Duplicate lens of PND-MB-01, listed here as a test hole.) | `BACKLOG.md` L97 | test-gap |
| PND-TEST-05 | RELEASE.md pre-flight assumes "**`master` is green and clean … CI passing**," but there is no app/site CI gate to enforce it — an unmet process assumption. | `RELEASE.md` §"1 · Pre-flight" L69; cf. PND-TEST-02 | tech-debt |

---

## Docs / process

| ID | Description | Source | Tag |
|---|---|---|---|
| PND-DOC-01 | **Übersicht still referenced as a live surface** in ADR-002 ("the menu bar app **and Übersicht**") and ADR-003 (the "Übersicht `.jsx` calls a tiny Swift CLI"), although Übersicht was removed (ROADMAP Phase 3 says the `apps/ubersicht` prototype "is removed"). Historical ADR text flagged for revision. | `DECISIONS.md` ADR-002 L11, ADR-003 L16 vs `ROADMAP.md` L23–L24; `CLAUDE.md` §Open questions L159–L160 | stale-doc |
| PND-DOC-02 | **[CORRECTED 2026-07-03] `ROADMAP.md` Phase 2 AND 5–8 status markers are stale** — Phase 2 (menu bar flagship, shipped in v0.4.0) carries no ✅ and still lists the never-shipped "Writes to App Group + reloadTimelines()" bullet; Phase 5's cookie-fallback bullet is actually BUILT (`ClaudeCookieProvider.swift` + `ClaudeLoginWindow.swift`) yet unmarked; Phase 6 decided (ADR-006), Phase 7 live — all unmarked. BACKLOG.md:176's claim that markers were "updated" was an incomplete fix. | `ROADMAP.md` L15–L19 (Phase 2), L29–L43 (Phases 5–8); `BACKLOG.md` L175–177 | stale-doc |
| PND-DOC-03 | **[CORRECTED 2026-07-03] ARCHITECTURE.md over-claims the built system in TWO ways** — (a) the App-Group write + WidgetKit widget + `reloadTimelines` described as wired (see PND-MB-02, PND-NCW-01); (b) **phantom FetcherCore components**: a `Scheduler` ("per-provider interval, jitter, exponential backoff on 401/403/429") and a `Cache` (last-good value) that exist **nowhere** in code — `grep -rni 'backoff\|jitter\|scheduler'` across core/ + apps/ → 0 hits; polling + last-good caching actually live in the app's `UsageModel`, with **no backoff at all** (and the shipped 429 copy "backing off, will retry" is false). PROVIDERS.md L37 duplicates claim (b). | `ARCHITECTURE.md` L16–17, L22–L33, L42, L50, L65–L68; `PROVIDERS.md` L37; `apps/menubar/.../UsageModel.swift:100` (fixed Timer), `:184` (false copy) | stale-doc |
| PND-DOC-04 | **`CredentialStore` doc / ARCHITECTURE mention Keychain item `"Claude Code"`** as the source, but the live primary is `"Claude Code-credentials"` (with `"Claude Code"` only a fallback added in slice (a)); PROVIDERS.md still says the item is "commonly named `Claude Code`." Minor naming drift. | `PROVIDERS.md` L43; `ARCHITECTURE.md` L41 vs `core/Sources/FetcherCore/ClaudeOAuthCredentialSource.swift` L34–L38 | stale-doc |
| PND-DOC-05 | **[CORRECTED 2026-07-03] `feature_list.json` is stale AND consumer-less** — beyond the seeded staleness (P1 "next" though slice (a) shipped and ADR-012 capped it; no P4), **no code, script, or site consumes it** (`grep -rn feature_list scripts/ site/ core/ apps/` → 0 hits; `init.sh` reads BACKLOG.md, not it), it declares `generated_from`/`generated_at` but **no generator exists**, and it was never regenerated after its creation commit (`1d742ee`). The decision is consumer-or-delete, not just cadence. | `feature_list.json` L30–L42; `git log -- feature_list.json` → 1 commit; grep → 0 consumers | stale-doc |
| PND-DOC-06 | **Cross-cutting "keep trust/privacy messaging accurate" and "installer-integrity as `install.sh` evolves"** are standing open process checklist items (never "done"). | `BACKLOG.md` §Cross-cutting L152–L156 | open-decision |

---

## Security / ToS

| ID | Description | Source | Tag |
|---|---|---|---|
| PND-SEC-01 | **ADR-012 — the whole Claude subscription-auth ToS posture.** Recorded as *decided* (keep read-only, freeze expansion, don't seek permission, don't pivot, accept residual account-ban risk) but the ADR itself says "**Revisit if Anthropic's terms/enforcement change or if the product pivots**." Logged here as an OPEN DECISION the audit may challenge in full. | `DECISIONS.md` ADR-012 L58–L69; `CONTEXT.md` L54–L61; `CLAUDE.md` §Open questions L152–L155 | open-decision |
| PND-SEC-02 | **Optional user-facing transparency line** (app/site: "Houdini reads your existing Claude credential; Anthropic's terms restrict third-party use of subscription OAuth; use at your discretion") — recommended by ADR-012 but **deferred / not yet adopted**. | `DECISIONS.md` ADR-012 §Decision.6 L67; `BACKLOG.md` L13; `PROVIDERS.md` L51 (one-line stance only) | open-decision |
| PND-SEC-03 | **Browser-scrape last-resort fallback adapter** — reserved in ADR-001/architecture for providers with no readable endpoint; any such elevated permission "must be provably secure and least-privilege before it ships." Unbuilt; a future security-gated item. | `DECISIONS.md` ADR-001 L6–L8; `ARCHITECTURE.md` §"Fetch mechanism priority" L97–L101; `CONTEXT.md` L48–L49; `BACKLOG.md` L152–L153 | idea |
| PND-SEC-04 | **A full security review** of the Claude auth path is only triggered "if refresh / PKCE is ever unfrozen" — i.e. deferred and contingent on unfreezing PND-APP-02/03. | `BACKLOG.md` L81–L83; `conductor/prompts/02-p1-login-refactor.md` L224 | open-decision |

---

## Notable findings beyond the pre-listed "known threads"

The task listed a set of already-surfaced threads (Gemini gap, Übersicht, P2 slice 3, `apps/widget`
placeholder, `apps/ios` scaffold, the transparency line, and the ADR-012 ToS posture) — all verified
and captured above. The following were **surfaced additionally** during this scan and were **not** on
that list:

1. **PND-MB-02 / PND-DOC-03 — the App-Group bridge is undocumented-as-missing.** The menu bar app has
   **no** `WidgetCenter.reloadAllTimelines()` call and **no** App-Group snapshot write, yet
   ARCHITECTURE.md's diagram *and* prose assert it does. This is the linchpin that also makes the
   WidgetKit widget (`apps/widget`) non-functional even once built — the two are coupled. The app's own
   README (§"Not in this phase", L63–65) is the only doc that admits it.
2. **PND-APP-05 — a live `TODO(phase ≥2, signed app)` in security-adjacent code.** `CredentialStore`
   spawns `/usr/bin/security` on every 60s poll; the native `SecItemCopyMatching` migration is gated on
   shipping a signed app added to the item's ACL. It's a real performance + hygiene debt in the
   credential path (Opus-routing territory per CLAUDE.md).
3. **PND-REL-02 — the P4 backlog section is uncommitted WIP.** Two orchestration prompts explicitly
   protect an "uncommitted P4 · Self-update WIP section" — so the P4 requirements exist in the working
   tree but are not part of committed backlog state.
4. **PND-DOC-02 / PND-DOC-04 / PND-DOC-05 — additional doc drift** beyond Übersicht: ROADMAP Phase 5–8
   status markers are unmaintained; PROVIDERS.md/ARCHITECTURE.md still call the Keychain item
   `"Claude Code"` (primary is `"Claude Code-credentials"`); and `feature_list.json` is a dated snapshot
   (2026-07-01) that already lags (P1 "next", no P4).
5. **PND-SITE-07 / PND-SITE-08 — the site audit's own scope caveats.** Six sub-pages were never audited,
   and the "passing" a11y verdict was DOM/focus-*simulated* (not a live assistive-tech session), with
   sub-406px widths approximated and borderline contrasts flagged "verify with a formal tool." The clean
   audit result is narrower than it reads at a glance.
6. **PND-TEST-05 — RELEASE.md assumes a CI gate that doesn't exist.** The pre-flight checklist says
   "`master` is green … CI passing," but there is no app/site CI to enforce it (only `release.yml`).

Marker scan for reference: `grep -rniE "TODO|FIXME|HACK|XXX|BUG|deprecated|placeholder|not implemented|stub"`
across `core/ apps/ site/ scripts/ install.sh` returned matches in ~21 source files, but the overwhelming
majority are **legitimate code**, not action items — e.g. `StubProvider`/`stub` provider used for timing
tests (`PreviewData.swift` L48–50, `SelfTest.swift` L19/L22), `isPlaceholder` loading-skeleton flags
(`WidgetRingGauge.swift`, `SharedUI.swift`, `Theme.swift`), and "OBVIOUSLY-FAKE placeholder" test tokens.
The only genuinely actionable code markers are `CredentialStore.swift:48` (PND-APP-05) and the
`apps/ios` `// TODO(xcode)` / `TODO_TEAM_ID` scaffold markers (PND-IOS-01/03). No `FIXME`/`HACK`/`XXX`
action items exist in source.

---

## Additions from the deep audit (2026-07-03) — new pendências

> Surfaced by the 43-agent impartial audit; deduplicated across dimensions. Same row format.
> IDs continue the area families with a `-N` suffix (e.g. `PND-APP-07` follows PND-APP-06).
> Cross-references in parentheses point to `02-technical-diagnosis.md` finding IDs.

### App / core

| ID | Description | Source | Tag |
|---|---|---|---|
| PND-APP-07 | **Sticky signed-out auth** — `ClaudeSession.refresh()` runs only at init, prefer-cookie toggle, login-window close, and sign-out; a credential that appears (or expires) while Houdini runs is never detected. Worst case fully confirmed: launch signed-out → every poll early-returns at `UsageModel.swift:115-124` **without any Keychain read** — a user who installs Houdini first and logs into Claude Code second stays signed out until relaunch. (CORE-01/MB-02/ARC-04) | `ClaudeSession.swift` L21/L34/L39/L73/L85; `UsageModel.swift:115-124` | bug |
| PND-APP-08 | **No backoff exists anywhere** despite ARCHITECTURE.md L42 + PROVIDERS.md L37 claiming jitter/exponential backoff, and the shipped 429 copy **"Rate limited — backing off, will retry" is false** — the fixed 30/60/120s timer keeps firing; no Retry-After handling. (ARC-02/CORE-06/MB-06) | `UsageModel.swift:100` (fixed Timer), `:184` (copy); grep backoff → 0 hits | bug |
| PND-APP-09 | `ClaudeOAuthProvider.clientVersion` is an **uncached computed property spawning `/usr/bin/env claude --version` (a Node CLI) synchronously on every 60s poll**, blocking a cooperative thread — the dominant per-poll cost, bigger than the `security` spawn (PND-APP-05). (CORE-03/SEC-05) | `ClaudeOAuthProvider.swift:130-132`, `:140-162` | tech-debt |
| PND-APP-10 | `ClaudeCookieProvider.fetch()` re-fetches `GET claude.ai/api/organizations` on **every** poll (2 requests/tick; 4/min at the 30s setting) for a session-stable orgId. (ARC-07/CORE-10) | `ClaudeCookieProvider.swift:60-66` | tech-debt |
| PND-APP-11 | Both providers use `URLSession.shared` (default config): server-set cookies and disk-cached responses are accepted on credentialed GETs — should be an ephemeral session with `httpShouldSetCookies=false`, `urlCache=nil`. (SEC-01) | `ClaudeOAuthProvider.swift:103`; `ClaudeCookieProvider.swift` | tech-debt |
| PND-APP-12 | `CredentialRedirectGuard` compares **hosts but not schemes** — a same-host https→http redirect keeps `Authorization`/`Cookie` on a cleartext request; the guard has zero unit tests. (CORE-07) | `HTTPRedirectGuard.swift:19-35`; core/Tests (no reference) | tech-debt |
| PND-APP-13 | **Staleness is invisible on the primary surface**: on fetch error with retained metrics, the popover shows a banner and the widget a chip, but the menu bar label renders the last-good number with normal colors and no cue. (MB-03/CORE-05) | `MenuBarLabelContent.swift:12-20` | tech-debt |
| PND-APP-14 | `houdini` CLI has **no `--help`, no `--version`**; unknown flags silently ignored (`--jsn` behaves like `--json`); exit codes documented only in a source comment. Blocks the P4 update feature's version primitive. (CORE-08) | `core/Sources/houdini/main.swift:14-28` | missing-feature |
| PND-APP-15 | Dead protocol surface: `UsageProvider.refreshInterval` and `capabilities` have **zero production consumers** — app cadence comes solely from `AppSettings`; ADR-007's "capability flags drive the UI" mechanism is not the one implemented. (ARC-03/CORE-11) | `UsageProvider.swift:8-9`; grep `.capabilities` | tech-debt |
| PND-APP-16 | **No user-visible version anywhere in the product** — no About/version row in Settings, no CLI `--version`; the app never reads its own bundle version. (critic) | `SettingsView.swift` (no version row); `ProviderGlyph.swift:50` (only Bundle.main use) | missing-feature |
| PND-APP-17 | Houdini's cookie Keychain item uses `kSecAttrAccessibleAfterFirstUnlock` (needed for launch-at-login) — one notch broader than `WhenUnlocked`; deliberate, but undocumented in PROVIDERS/ARCHITECTURE. (SEC-09) | `CredentialStore.swift:149` | tech-debt |

### Menu bar + desktop widget

| ID | Description | Source | Tag |
|---|---|---|---|
| PND-MB-07 | Menu bar number's threshold color is likely an **AA contrast failure in light mode** (systemGreen ≈2.2:1 on a light bar) and is the **only channel** encoding severity there — the P2 slice-1 "accessibility pass DONE" covered popover+widget but not the bar label. (MB-04) | `MenuBarLabelContent.swift`; `Formatting.swift:8-11`; BACKLOG.md:95 | bug |
| PND-MB-08 | `SettingsView` is excluded from the Dynamic Type work: raw fixed `.font(.system(size:10-15))` throughout + fixed 360pt panel width (popover/widget use `scaledFont`). (MB-07) | `SettingsView.swift` | tech-debt |
| PND-MB-09 | Desktop widget "Connect Claude" button likely has **no keyboard path** (non-activating panel, `.ignoresCycle`, becomes key only on click) — unverified with live AT; popover parity is the fallback. (MB-12) | `DesktopWidgetController.swift:93,108,115` | test-gap |
| PND-MB-10 | Manual Refresh gives no visible feedback once data exists (`refreshNow()` silently no-ops mid-flight; loading state only pre-first-data). (MB-11) | `UsagePopover.swift:169`; `UsageModel.swift` | tech-debt |
| PND-MB-11 | app README claims Settings controls are "drawn in pure SwiftUI (not native Picker/Toggle) so they render via ImageRenderer" — the **exact inverse** of the code (native Picker/Toggle used). | `apps/menubar/README.md:56-57` vs `SettingsView.swift` | stale-doc |
| PND-MB-12 | `--widgettest` and `--register/--unregister-login-item` exist in the binary but are absent from the app README's documented flag list. (MB-10) | `Main.swift:23-40` vs `apps/menubar/README.md:23-32` | stale-doc |

### Site

| ID | Description | Source | Tag |
|---|---|---|---|
| PND-SITE-09 | **No LICENSE file exists** (GitHub API: `license: null`) while "free & open source" is claimed on /, /install, /faq, /privacy and is a CLAUDE.md guardrail — the claim is legally false today (default all-rights-reserved). (SITE-01) | `find . -name 'LICENSE*'` → none; `api.github.com/repos/vitorsalomao05/houdini` | bug |
| PND-SITE-10 | **/reveals advertises a "Tokens" capability that does not exist in code** ("burned through each window, kept current to the minute", 1.24M sample, meta "tokens burned") — `Capabilities` has no token flag, no parser field, no UI row. Violates ADR-010's no-vaporware rule. (SITE-02) | `site/src/config.ts:74-77`, `reveals.astro:126-141` vs `core/.../Models.swift`, `UsageProvider.swift` | bug |
| PND-SITE-11 | **/guide's gauge legend teaches 0–74/75–89/90–100 but the app ships <60/60–85/>85**; /reveals and /surfaces render 72% as amber, contradicting the guide's own legend. (SITE-04/MB-01) | `guide.astro:28-30` vs `Formatting.swift:8-11` | bug |
| PND-SITE-12 | Cookie-path copy promises "sign in to claude.ai once … no repeated logins" (/install, /guide; /faq says "grant once") — false: the cookie is short-lived and non-refreshable, and hardening is **frozen by ADR-012 decision**, so re-login is the designed behavior. (SITE-03) | `install.astro:140-145`, `guide.astro:240-244`, `config.ts:107` vs BACKLOG root-cause B + ADR-012 | bug |
| PND-SITE-13 | /guide presents API-usage tracking in **present tense** for an unbuilt capability ("Houdini shows: $ spent this period + token counts"; audience card "watch the dollars … in real time") — no API provider exists. (SITE-07) | `guide.astro:144-148`, `:352-356` vs core (Claude-only) | bug |
| PND-SITE-14 | **Sub-page a11y debt** the landing-only fix (78e2bf3) missed: /reveals 12px `text-muted/70` ≈3.8:1 (fails AA), sub-page eyebrows still `#8b5cf6` ≈4.65:1 (landing got `#9d7bf7`), plus the pervasive-12px classes on sub-pages. (SITE-06) | `reveals.astro:83`; `SectionHeader.astro`; `guide.astro:164` | tech-debt |
| PND-SITE-15 | Hero "Nothing leaves your Mac" is contradicted by the site's own /privacy ("one request, signed with your credential, leaves your Mac") — replace with the precise, stronger claim. (SITE-05) | `index.astro` hero vs `privacy.astro` | tech-debt |
| PND-SITE-16 | /surfaces renders a fabricated gauge mock (34/72/91%) beside a "Live · every 60s" chip with **no "Illustrative sample" disclaimer** (unlike /reveals which labels its mocks). (SITE-08) | `surfaces.astro:9-13`, `:82-104` | idea |
| PND-SITE-17 | Dead site artifacts: `popover-light.png` imported nowhere; `config.ts` reveals `icon` fields reference a nonexistent component; no branded 404 page; no robots.txt/sitemap. (SITE-09 + critic) | grep popover-light → 0; `config.ts:60-81`; `site/public/` | tech-debt |
| PND-SITE-18 | The KEEP-GENERIC-H1 decision is **internally incoherent**: a pulsing "Live for Claude Pro · Max" badge sits directly above the generic H1 and the body copy names Claude — the low-profile rationale is already defeated in the same viewport. (SITE-10) | `index.astro` hero block; BACKLOG.md:114-116 | open-decision |

### Installer / scripts / release

| ID | Description | Source | Tag |
|---|---|---|---|
| PND-REL-05 | **release.yml has NEVER succeeded** — all 4 tag-push runs failed (v0.2.0 ×2, v0.3.0, v0.4.0); root cause: `WidgetGlass.swift:149` `glassEffect` needs the macOS 26 SDK, the workflow pins Xcode 16. Every shipped release was hand-built + manually published; docs (CLAUDE.md, init.sh:91) describe CI as the release path. (INS-01/DX-01/DX-02) | `gh run list --workflow=release.yml`; `release.yml:21`; `WidgetGlass.swift:147-152` | bug |
| PND-REL-06 | **Two publishers race the same tag**: manual `gh release create` (RELEASE.md) and release.yml's `gh release create "$TAG"` — v0.4.0's manual release beat the CI run by 4 seconds; if CI is ever fixed, they collide. (INS-02/DX-11) | `release.yml:86` vs `RELEASE.md:28-29` | tech-debt |
| PND-REL-07 | **ADR-010 prune policy overreaches**: deleting old releases+tags makes rollback/downgrade impossible (v0.3.0 raw install.sh already 404s), breaks saved one-liners, and makes `houdini update <old>` a null set — "one advertised version" only requires the *pointers* to be current. (INS-03) | `RELEASE.md:91-96`; ADR-010; live 404 probes | open-decision |
| PND-REL-08 | ADR-010 claims the bump+publish+prune steps "are scripted to run as one unit" — **no such script exists** (scripts/ = init.sh only); scripts/README.md describes "Sign/notarize, install.sh, release automation" that isn't there. (INS-06/INS-07) | DECISIONS.md ADR-010 §Trade-off; `ls scripts/` | stale-doc |
| PND-REL-09 | install.sh `rm -rf "$APP"` **before** extracting the replacement, never quits a running instance, and installs the CLI with `cp -f` (in-place same-inode write — the exact pattern Apple warns causes kernel signature-cache crashes; critical for the P4 self-update where the CLI overwrites itself). (INS-05 + research) | `install.sh:97-98,107,116-117`; Apple "Updating Mac Software" | tech-debt |
| PND-REL-10 | SHA-256 verification is **self-attesting** (SHASUMS256.txt from the same release as the assets — integrity, not authenticity), and the "No Gatekeeper prompt" copy sells the *removal of macOS's malware check* as pure convenience without disclosure. (INS-04/SEC-03/SEC-04) | `install.sh:85-91,100-102`; `release.yml:45-56`; site copy | open-decision |
| PND-REL-11 | RELEASE.md §2 "single source of truth" bump list **omits `apps/menubar/Info.plist`** (CFBundleShortVersionString/CFBundleVersion), and its `grep "vP.Q.R"` safety net cannot match the un-prefixed plist value — yet Info.plist is the authoritative installed-version marker the update feature depends on. (MB-09) | `RELEASE.md:74-79` vs `Info.plist:19-22` | tech-debt |
| PND-REL-12 | **Uninstall leaves credentials/state behind**: the printed steps remove login item, app, CLI — but not the `Houdini-claude-session` Keychain item or the app's UserDefaults; no uninstall doc exists anywhere users can find later. (GAP-01) | `install.sh:138-141` | missing-feature |
| PND-REL-13 | **No SECURITY.md / vulnerability-disclosure channel** (no CONTRIBUTING/CODE_OF_CONDUCT either; .github/ = release.yml only) for a security-marketed product. (GAP-04) | `ls .github/`; site contact surfaces | missing-feature |

### Testing / CI

| ID | Description | Source | Tag |
|---|---|---|---|
| PND-TEST-06 | **`swift test` exits 0 while executing ZERO tests** on the CommandLineTools-only dev machine (`swift test list` empty) — a silent-green verification loop; the 28 `@Test` functions have never run there. (DX-03) | observed: `cd core && swift test` → "Build complete!", 0 tests | test-gap |
| PND-TEST-07 | **No push/PR CI at all** — nothing builds core/, apps/menubar, or site/ on commit; repo is public so GitHub-hosted macOS runners are free. (DX-04) | `.github/workflows/` = release.yml only | test-gap |
| PND-TEST-08 | Smoke flags `--selftest`, `--metrictest`, `--snapshot` **unconditionally exit(0)** — human-eyeball output, no assertions; only `--widgettest` can fail. The documented "smoke via built binary flags" story overstates them. (DX-07) | `SelfTest.swift:55,103`; `Snapshotter.swift:39` | test-gap |
| PND-TEST-09 | Zero coverage of the riskiest core paths: HTTP status→error mapping (both providers), the 401→refresh→retry branch, cookie two-request flow, `CredentialRedirectGuard.sameSite()`, `CredentialStore`. (CORE-09/DX-05) | `core/Tests/FetcherCoreTests/` (3 files) vs providers | test-gap |
| PND-TEST-10 | `houdini-selftest` hand-duplicates ~240 lines of the swift-testing suite with **no parity check** — assertions can silently drift between the two. (DX-06) | `houdini-selftest/main.swift:4-11,128-131` | tech-debt |
| PND-TEST-11 | FetcherCore-for-iOS compilation (PND-IOS-04) is verifiable **for free today** — release.yml already runs on macos-14 runners with full Xcode; a small simulator-destination build job settles it. (PER-05) | `release.yml:10,21,33`; `core/Package.swift:34` (.iOS(.v17)) | test-gap |

### Docs / process

| ID | Description | Source | Tag |
|---|---|---|---|
| PND-DOC-07 | CLAUDE.md + CONTEXT.md "Survey findings" still assert **pre-slice-(a) auth code as current fact** ("no alternate item names, no file fallback, no refreshToken use"; "Design, don't build yet") — slice (a) shipped all three. The operating docs mislead every future session. (DOC-03) | CLAUDE.md §Survey; CONTEXT.md L96-105 vs `ClaudeOAuthCredentialSource.swift` | stale-doc |
| PND-DOC-08 | CONTEXT.md L108 + BACKLOG.md L163-165 still flag ROADMAP's "Cloudflare Pages" as needing correction — it was corrected 2026-07-01; BACKLOG contradicts itself 12 lines later. (DOC-10) | CONTEXT.md L108; BACKLOG.md L163-165 vs L175-177 | stale-doc |
| PND-DOC-09 | WORKFLOW.md L5 defines the executor as "Claude Code (**Opus 4.8**, in VS Code)", contradicting its own L46-47 and CLAUDE.md ("Fable 5 default"); the doc also duplicates CLAUDE.md conventions and is absent from CLAUDE.md's source-of-truth list. (DOC-11/ORG-08) | WORKFLOW.md L5 vs L46-48; CLAUDE.md | stale-doc |
| PND-DOC-10 | BACKLOG.md self-contradicts: L96 marks P2 slice 2 `[x]` DONE while "Immediate next steps" L189 lists the same slice as `[~]` current focus; P1 header stays `[~]` though capped/decided. (ORG-07) | BACKLOG.md L11, L96, L189 | stale-doc |
| PND-DOC-11 | PROVIDERS.md's contract omits the **shipped `claude-cookie` provider id** (registered in `ProviderRegistry.makeDefault`) — the doc models cookie auth as a mode of the single `claude` provider. (DOC-07) | PROVIDERS.md L9,L47 vs `ClaudeCookieProvider.swift:13` | stale-doc |
| PND-DOC-12 | README claims the NC widget "also exists in the repo" (L35) while its own tree note says "placeholder today" (L67); repo maps in README/CLAUDE.md omit 6 root docs + conductor/; scripts/ mislabeled. (ARC-08/ORG-12/DOC-12) | README.md:35 vs :67; L55-75 | stale-doc |
| PND-DOC-13 | **No ADR records the NSPanel desktop-widget decision** — the shipped desktop surface (in-process NSPanel, replacing Übersicht, WidgetKit rejected) has no decision record; ADR-002/003 still present Übersicht as live. → proposed **ADR-013**. (ARC-05) | DECISIONS.md (no desktop-widget ADR); ADR-002 L11, ADR-003 L16 | stale-doc |
| PND-DOC-14 | ADR-012's risk record understates reality: both paths **actively impersonate other clients** (OAuth sends `claude-code/<v>` UA; cookie mimics the web app) — that's what evades the Jan-2026 blocks; PROVIDERS.md calls 1,440 req/day "low-frequency"; the refresh-rotation hazard (unfreezing could strand the user's CLI login) is absent from the Why. (SEC-07/SEC-08) | ADR-012; PROVIDERS.md L47; `ClaudeOAuthProvider.swift:41,96` | stale-doc |
| PND-DOC-15 | apps/ios docs over-claim: README "iOS-ready … done and **verified**" + ROADMAP Phase 9 ✅ vs PLAN.md §5's own "documented assumption"; project.yml's widget→app dependency is **inverted** vs XcodeGen convention; Lock-Screen Gauge takes unclamped pct; iOS Theme mirrors the pre-rebrand palette while claiming site lockstep. (PER-04/06/08 + MB) | `apps/ios/README.md:57-59`; ROADMAP:47; `project.yml:57-59`; `HoudiniWidget.swift:76` vs `:96`; `ios/Shared/Theme.swift:3-16` | stale-doc |
| PND-DOC-16 | `apps/menubar/docs/review/` is a 25-PNG ≈4.5MB tracked corpus of the **pre-P2-polish UI** (2026-06-19, before commits 19d3ed0/1d8912b) with no consumer; README has **zero product imagery** for a visual product. (GAP-05/GAP-06) | `git log -- apps/menubar/docs/review` (df3d8fe); README.md (no images) | stale-doc |
| PND-DOC-17 | `Houdini.entitlements` comment documents outbound HTTPS "to api.anthropic.com" only — the app equally talks to claude.ai (cookie API + login WebView); comment drift in a security-adjacent file. | `apps/menubar/Houdini.entitlements` | stale-doc |
| PND-DOC-18 | `scripts/init.sh` misreports "xcodebuild: present (full Xcode)" on CLT-only machines (the CLT shim satisfies `command -v` but errors on invocation), and L91 tells newcomers the tag push triggers a CI release — see PND-REL-05. (DX-10/INS-08) | `init.sh:42,54,91`; observed `xcodebuild -version` error | stale-doc |
| PND-ORG-01 | The same load-bearing facts are hand-maintained in 5+ root docs and already disagree (P1 status exists in 3 incompatible versions: feature_list "next" / BACKLOG `[~]` / CONTEXT "decided, focus moved"). No owner-per-fact convention. (ORG-01) | feature_list.json:31; BACKLOG.md:11; CONTEXT.md:85-88 | tech-debt |
| PND-ORG-02 | The **audit corpus itself is untracked** (audit/ = 10 files incl. the v1 plan and both feature specs), and tracked docs cite gitignored conductor/prompts file:line as evidence sources — unreviewable citations. (ORG-03) | `git status` → `?? audit/`; `.gitignore:27` | wip |
| PND-ORG-03 | `.claude/` is ignored only via machine-local excludes (`.git/info/exclude`, `~/.config/git/ignore`), not the repo .gitignore — contributors on other machines would see untracked noise. (ORG-11) | `git check-ignore -v .claude/…` | tech-debt |

> **Reconciliation note (GAP-02).** Two findings judge ADR-012's refresh freeze in opposite
> directions: CORE-02 (freezing refresh shifts users to the weaker cookie path without reducing
> ToS exposure) vs SEC-08 (the freeze is right, for a stronger reason than ADR-012 records —
> refresh-token rotation could strand the user's own Claude Code login). **Resolution adopted
> by this audit:** the freeze on *active* refresh **stands** (SEC-08's rotation hazard is
> decisive); CORE-02's real, actionable residue is the S-effort copy fix — the expired-at-launch
> state should say "run `claude` to refresh your token" instead of funneling CLI users to the
> cookie WebView — plus recording the rotation hazard in ADR-012's Why (PND-DOC-14).
