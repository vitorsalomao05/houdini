# 08 · Implementation Instructions — Claude Code Fable 5 Ultracode  ·  FILLED 2026-07-03

> **Status: READY.** Derived from `05-v1-plan.md` (phases A–G) and the evidence in `02`.
> Finding IDs in parentheses anchor each unit to its evidence. Units within a phase are
> ordered; phases B, C, D may run in parallel **after A5+A2 land** (disjoint file scopes —
> use `git worktree` for true parallelism, one commit per unit, never two concurrent
> commits on one working tree).

## Operating rules (fixed — from CLAUDE.md)

- **Model routing:** Fable 5 default. **Opus** for security-adjacent units — marked
  `[OPUS]` below (auth/credential/Keychain/network-trust paths, and line-level review of
  E2). ADR-012's freeze stands: **no** unit below wires token refresh, PKCE, or cookie
  hardening.
- **Git:** Builder owns git; branch per unit (`feat/…` `fix/…` `chore/…` `docs/…`);
  Conventional Commits; **no AI-attribution trailer**; small reviewable commits.
- 🔴 **Gated actions (explicit owner sign-off first):** `push --force`, `reset --hard`,
  notarization/signing/release steps, **any change touching `install.sh` or
  `SHASUMS256.txt`**, tag/publish/deploy in Phase G. *Note: every unit below is designed to
  need **zero** install.sh/SHASUMS edits; if an implementation discovers otherwise, STOP
  and get the gate.*
- **Evidence, not reasoning:** every unit ends with pasted build/test/grep output.
- **Anti-over-engineering:** smallest change that satisfies the unit; stop & re-plan if a
  unit balloons.
- **Verify per change:** build + smoke/tests; a11y not regressed; no credential leak; no
  telemetry/trackers.

## Phase A0 — Decisions (owner, one sitting — unblocks everything)

**Unit A0 — Ratify the §3 decision batch from `05-v1-plan.md`.** Outcomes to record:
(1) ADR-013 approved (NSPanel = desktop surface; WidgetKit deferred w/ triple blocker);
(2) ADR-002/003 revision approved; (3) ADR-012 §6 transparency → **mandatory**;
(4) ADR-010 prune revision (keep superseded releases + Immutable Releases) — approve/reject;
(5) release publisher = CI (recommended) or manual — pick one; (6) Gemini claim dropped;
(7) `apps/widget/` deleted vs honest README; (8) `houdini update` in v1 — confirm;
(9) hero-H1 coherence direction. *No code. The answers parameterize D2, A2, E, F3.*

## Phase A — Truth & release integrity (P0 gate)

**Unit A1 — LICENSE.** *Goal:* make "free & open source" true (SITE-01). *Scope:* new
`LICENSE` (owner picks MIT or Apache-2.0), README footer line. *Acceptance:* GitHub API
shows a detected license. *Verify:* `gh api repos/:owner/:repo --jq .license` after push;
`ls LICENSE`. *Commit:* `chore: add MIT license` (or Apache-2.0).

**Unit A2 — Make the app compile on both toolchains (release-CI root cause).** *Goal:* fix
the 4/4-failed workflow's compile error (DX-02, GAP-03). *Scope:*
`apps/menubar/Sources/Houdini/WidgetGlass.swift` (~L147-152): wrap the
`Color.clear.glassEffect(in:)` branch in a compile-time guard (`#if compiler(>=6.2)` or an
SDK-availability check) so Xcode-16 SDKs build the `NSVisualEffectView` fallback; keep the
runtime `#available(macOS 26,*)` behavior identical on new SDKs. *Guardrails:* zero visual
change on macOS 26; fallback identical to today's 14/15 path. *Acceptance:* `build.sh
release` passes on BOTH a macOS-26-SDK machine and an Xcode-16 runner (CI proves the
latter). *Verify:* paste both build outputs (local + `gh run view` of a workflow run on a
test branch). *Commit:* `fix(menubar): compile-time guard for glassEffect so pre-26 SDKs build`.

**Unit A3 — One release publisher + verified pipeline.** *Goal:* end the two-publisher race
and the zero-verification publish (INS-01/02, DX-01/11, MB-08). *Scope:*
`.github/workflows/release.yml`, `RELEASE.md`. Per A0(5) — recommended shape: release.yml
becomes the sole publisher; add pre-publish steps `swift test` (core, on the full-Xcode
runner), `swift run houdini-selftest`, built-binary `--metrictest` + `--widgettest`;
RELEASE.md §3-4 rewritten to "push the tag; verify the CI-published release", §1 "CI
passing" replaced with the real checks, §2 gains the `apps/menubar/Info.plist` bump line
(MB-09), §6 deploy command becomes the practiced prebuilt two-step (DOC-13). *Guardrails:*
does NOT touch install.sh/SHASUMS256.txt; no release is actually published in this unit
(🔴 gate stays for real tags). *Acceptance:* a dry-run tag on a test branch produces a
draft/pre-release with all three assets + checksums and green verification steps; RELEASE.md
matches. *Verify:* `gh run view <id> --log` excerpts; `gh release view <draft>` asset list.
*Commit:* `ci(release): single publisher with pre-publish verification` +
`docs(release): align RELEASE.md with the real flow`.

**Unit A4 — Site truth pass.** *Goal:* remove the seven live falsehoods (SITE-02/03/04/05/07,
MB-01). *Scope:* `site/src/config.ts`, `site/src/pages/{reveals,guide,install,faq if
config-driven,index}.astro`. Changes: drop/rescope the Tokens reveal (config `reveals` entry
+ reveals.astro panel); fix the /guide legend to 0–59/60–84/85–100; cookie copy → "sign in
in a native window; the session is kept in your Keychain and reused until it expires —
you'll sign in again when it does"; /guide API copy → forward-looking; hero → "No account,
no server — your Mac talks only to your provider." *Guardrails:* zero-clutter + AA
preserved; no new sections (ADR-010 adapt-don't-stack). *Acceptance:* no user-facing string
contradicts the shipped app/core; `npm run build` passes. *Verify:* `grep` proofs
(75/89/90 gone; "no repeated logins" gone; Tokens entry gone), build output, before/after
screenshots of the three pages. *Commit:* `fix(site): truth pass — thresholds, tokens claim,
cookie copy, hero precision`.

**Unit A5 — Sticky-auth fix.** *Goal:* a credential that appears/expires while Houdini runs
is detected without relaunch (CORE-01, MB-02). *Scope:* `apps/menubar/Sources/Houdini/
UsageModel.swift` (`refreshNow()` / tick path), `ClaudeSession.swift`. Change: when the
resolved provider is nil (`.signedOut`) — and after an `.authExpired` failure — call
`session.refresh()` before giving up; also refresh on popover open and the manual Refresh
button. *Guardrails:* [OPUS review — auth path]. No new Keychain writes; ~1-3 extra
`security` spawns only in signed-out/error states. *Acceptance:* launch signed-out → run
`claude` login → within one tick Houdini connects, no relaunch. *Verify:* scripted
reproduction (launch with renamed Keychain item, restore item, observe state flip in log /
`--snapshot`); paste before/after. *Commit:* `fix(menubar): re-resolve credentials on
signed-out/error ticks`.

## Phase B — Core reliability + security polish

**Unit B1 — Honest failure behavior.** *Goal:* stop claiming backoff that doesn't exist;
stop re-spawning `claude --version` per poll (ARC-02, CORE-03/06, MB-06). *Scope:*
`UsageModel.swift` (skip-N-ticks multiplicative backoff on `.rateLimited`, reset on
success — or, minimal variant per owner taste, fix the copy to "will retry at the next
refresh"); `core/.../ClaudeOAuthProvider.swift` (cache `detectedClientVersion()` once per
process — `static let`/actor; probe absolute paths before `/usr/bin/env`). *Acceptance:*
a stubbed persistent 429 shows the interval actually widening (or the honest copy); exactly
one `claude --version` spawn per process lifetime. *Verify:* selftest/`--selftest` output;
`log stream`/dtrace or a counter print proving single spawn. *Commit:*
`fix(core,menubar): real 429 backoff + cache claude-version probe`.

**Unit B2 [OPUS] — Network-layer hardening.** *Goal:* credentialed requests can't leak into
cookie jars/disk caches; redirect guard can't keep credentials on a downgrade (SEC-01,
CORE-07). *Scope:* new shared session in `core/Sources/FetcherCore/` (ephemeral config,
`httpShouldSetCookies=false`, `httpCookieAcceptPolicy=.never`, `urlCache=nil`, explicit
~20s timeout) used by both providers; `HTTPRedirectGuard.swift` strips credentials when
`scheme != "https"`; new `FetcherCoreTests` for `sameSite` (exact host, subdomain both
directions, `evil-claude.ai` lookalike, scheme downgrade). *Acceptance:* no
`URLSession.shared` remains in providers; guard tests pass. *Verify:* grep + `swift test`
output (on CI runner per C1) + selftest mirror. *Commit:* `fix(core): ephemeral pinned
URLSession + redirect scheme guard`.

**Unit B3 — Staleness + expiry UX.** *Goal:* stale data and expired auth are visible and
actionable (MB-03/04, CORE-02/05). *Scope:* `MenuBarLabelContent.swift` (stale cue when
`state.isError` — dim/glyph, not color-only), `UsageModel.message(for:)` (authExpired copy
for CLI users: "run `claude` to refresh your token"), light-mode contrast measurement and,
if failing, explicit light/dark threshold color pairs in `Formatting.swift`. *Guardrails:*
severity never color-only; AA in both appearances. *Acceptance:* error-with-cache shows a
bar-level cue; measured contrast ≥4.5:1 (text) in light mode. *Verify:* `--snapshot` renders
(light+dark) + contrast numbers. *Commit:* `fix(menubar): stale cue on bar label + AA
light-mode threshold colors + honest expiry copy`.

**Unit B4 [OPUS] — Transparency line (from A0.3).** *Goal:* disclose the ToS posture
(SEC-02). *Scope:* `SettingsView.swift` (one sentence next to auth status),
`site/src/pages/privacy.astro` (one sentence). Text per ADR-012 §6. *Guardrails:* no
scare-copy; factual; zero-clutter. *Acceptance:* both surfaces show it; ADR-012 §6 updated
in D2. *Verify:* screenshot + grep. *Commit:* `feat: ToS transparency line in Settings +
privacy page`.

**Unit B5 — Version primitives.** *Goal:* the product knows and shows its version (CORE-08,
critic; prereq for E). *Scope:* `core/Sources/houdini/main.swift` (+ small `Version.swift`
generated/injected in the **shared build path** — `build.sh` + a build-tool step or a
committed constant bumped by RELEASE.md §2), `--version`/`--help`/usage-on-unknown-flag;
`SettingsView.swift` About row reading `CFBundleShortVersionString`. *Acceptance:*
`houdini --version` → `houdini 0.4.0`; `houdini --nonsense` → usage + exit 64; Settings
shows the version. *Verify:* pasted CLI runs; screenshot. *Commit:* `feat(cli): --version/
--help + verb-ready arg dispatch; feat(menubar): About version row`.

## Phase C — Verification baseline

**Unit C1 — ci.yml.** *Goal:* tests execute somewhere real; PRs can't silently break the
build (DX-03/04/07, PER-05). *Scope:* new `.github/workflows/ci.yml` (push/PR): job1
`swift test` + `swift run houdini-selftest` in core/ on a full-Xcode macOS runner; job2
`apps/menubar/build.sh release` + `--metrictest` + `--widgettest` (depends on A2); job3
`cd site && npm ci && npm run build`; optional job4 FetcherCore iOS-simulator compile.
Convert `--metrictest` prints to `check()` assertions with non-zero exit
(`SelfTest.swift`). *Acceptance:* CI green on a no-op PR; red when a known-answer metric
string is deliberately broken (prove once, revert). *Verify:* two `gh run view` links/log
excerpts (green + deliberately-red). *Commit:* `ci: push/PR baseline (core tests, app
smoke, site build)` + `test(menubar): make metrictest assert`.

**Unit C2 — Risky-path core tests.** *Goal:* the failure modes users actually hit are
covered (CORE-09, DX-05). *Scope:* `core/Tests/FetcherCoreTests/` — injectable transport
(URLProtocol or closure seam, matching existing style): OAuth 200/401/429/5xx mapping,
401→refresh→retry-once (fake refresher), cookie flow (orgs→usage, notFound→needsLogin);
mirror the critical subset into `houdini-selftest` with a parity count assertion (DX-06).
*Acceptance:* new tests fail when the mapping is deliberately broken. *Verify:* `swift
test` output on CI; selftest count. *Commit:* `test(core): provider status-mapping +
refresh-retry + cookie-flow coverage`.

## Phase D — Docs & process hygiene

**Unit D1 — ARCHITECTURE/PROVIDERS truth pass.** *Goal:* docs describe the built system
(ARC-01/02/06, DOC-01/02/06/07). *Scope:* `ARCHITECTURE.md` (diagram third arm + L32/50 →
"planned, not built"; L65-68 marked DESIGNED-NOT-BUILT; Scheduler/Cache → UsageModel
reality; Keychain item names; add the 4-endpoint table), `PROVIDERS.md` (L37 cross-cutting
services; L43 item name; add `claude-cookie`; fix "low-frequency" → ~1,440/day),
`apps/menubar/Houdini.entitlements` comment (+ claude.ai). *Verify:* grep proofs that the
false claims are gone. *Commit:* `docs(architecture,providers): match the code that exists`.

**Unit D2 — ADR pass (from A0).** *Goal:* decision records match decisions (DOC-05, ARC-05,
SEC-07/08/09, INS-03). *Scope:* `DECISIONS.md` — revise ADR-002/003 in place (dated note;
Übersicht historical; NC widget *planned*, menu bar sole 60s surface); write **ADR-013**
(NSPanel architecture + WidgetKit triple blocker + re-entry trigger); amend ADR-010 per
A0(4) (+ "scripted as one unit" wording fixed to reality per A3); amend ADR-012 (§6
mandatory per A0(3), add UA-spoofing honesty + refresh-rotation hazard to Why); note the
cookie item's AfterFirstUnlock choice in PROVIDERS/ARCHITECTURE. *Commit:* `docs(adr):
revise 002/003/010/012, add ADR-013`.

**Unit D3 — Operating-docs pass.** *Goal:* the docs Claude/contributors load are current
(DOC-03/08/09/10/11/12, ORG-01/06/07/08, DX-10, INS-07/08). *Scope:* `CLAUDE.md` +
`CONTEXT.md` (survey → past tense; monorepo maps + conductor/), `BACKLOG.md` (self-
contradictions; P1 `[x]` capped; next steps → slice 3), `ROADMAP.md` (real marker pass;
App-Group bullet moved to the deferred WidgetKit line), `WORKFLOW.md` → merged into
CLAUDE.md (keep the response-format template) and deleted, `feature_list.json` deleted per
A0 (or generator+consumer built), `README.md` (repo map, NC-widget phrasing per ARC-08,
Gemini row dropped per A0(6), scripts/ description), `scripts/README.md`, `scripts/init.sh`
(xcodebuild probe via `xcode-select -p`; L91 release-flow line per A3). *Verify:* grep
proofs per fix. *Commit:* several `docs:`/`chore:` commits, one concern each.

**Unit D4 — Org hygiene.** *Goal:* working-tree state matches intent (ORG-02/03/11,
PER-01/04/06/08). *Scope:* commit the P4 BACKLOG section (`docs(backlog): capture P4
self-update requirements`); `git add audit/` (track the corpus); `.gitignore` + `.claude/`;
delete `apps/widget/` per A0(7); apps/ios honesty (README "verified" reword, ROADMAP Phase-9
marker qualified, project.yml dependency direction flipped, Lock-Screen Gauge clamp —
mechanical, no build possible). *Verify:* `git status` clean-of-surprises; grep proofs.
*Commit:* separate commits per concern.

**Unit D5 — Trust completeness.** *Goal:* uninstall doesn't strand credentials; researchers
can report vulns (GAP-01/04). *Scope:* `SECURITY.md` (supported version = current release;
private reporting route), enable GitHub Private Vulnerability Reporting, uninstall section
on `site/src/pages/install.astro` (or /guide) + README covering the Keychain item
(`security delete-generic-password -s Houdini-claude-session`), `defaults delete`, login
item. **install.sh's printed steps are NOT edited (gated)** — the doc surfaces carry it.
*Verify:* pages render; grep. *Commit:* `docs: SECURITY.md + complete uninstall story`.

## Phase E — `houdini update` (per revised `07` — R3 conditions are law)

**Unit E1 — Resolver + `--check`.** *Goal:* read-only, dogfoodable version check. *Scope:*
`core/Sources/houdini/` — installed version (Info.plist read + own `--version`), latest via
`api.github.com/releases/latest` (unauthenticated, explicit timeout, no credential — this
call must go through the B2 session), semver compare, `--check` (+`--json`) output.
*Acceptance:* correct output in the three states (current / behind / app-missing); zero
disk mutation (verified). *Verify:* pasted runs against the live repo; `fs_usage`/absence
proof of writes. *Commit:* `feat(cli): houdini update --check`.

**Unit E2 [OPUS review] — The mutation.** *Goal:* one command updates safely through the
verified path. *Scope:* `core/Sources/houdini/` update verb implementing, in order:
unmanaged-install guard (running binary resolves to `~/.local/bin/houdini`, app at
`~/Applications/Houdini.app`, else refuse) → resolve target (latest-only `<version>`
semantics per 07 R2) → fetch per-tag `install.sh` → **TAG-match guard** → **rename-aside
the CLI** (`houdini.old`) → **pre-stash the app** (rename-aside) → spawn installer
**tty-detached, no HOUDINI_YES** → on exit 0: verify installed Info.plist == target, delete
stashes, report (incl. still-running-app message per install.sh's `open`); on non-zero:
restore both stashes, report unchanged. *Guardrails:* 🔴 zero edits to install.sh/SHASUMS;
no credential/Keychain access anywhere in the path; no telemetry. *Acceptance:* the §7
edge-case matrix of `07` passes on a real machine (update, re-run no-op, checksum-fail
simulation via tampered local copy → abort+restore, Ctrl-C mid-run → restore). *Verify:*
pasted terminal transcripts per case. *Commit:* `feat(cli): houdini update — verified
delegated install with rollback`.

**Unit E3 — Cleanup + docs.** *Goal:* close the story. *Scope:* owned-file manifest cleanup
(report-don't-delete outside the two owned paths; legacy `/Applications` copy detection);
README "Update" section (`houdini update`); RELEASE.md post-release step: `houdini update
--check` smoke; BACKLOG P4 → done. *Verify:* pasted cleanup run; grep. *Commit:*
`feat(cli): update cleanup manifest + docs`.

## Phase F — Surface polish end-to-end

**Unit F1 — P2 slice 3 (real-data verification).** *Goal:* gauges/reset timers/overage
verified against a real Claude Pro/Max account (PND-MB-01/PND-TEST-04) — also validates
B1/B3. *Scope:* no code expected; fixes filed/made if mismatches surface. *Verify:* pasted
`houdini --json` vs claude.ai/settings/usage screenshot comparison; popover/widget
screenshots. *Commit:* `docs(backlog): P2 slice 3 verified` (+ any fix commits).

**Unit F2 — A11y completion.** *Goal:* AA off the landing page too (SITE-06, MB-07/12).
*Scope:* `site/src` sub-pages (muted/70 → muted or 13px floor; eyebrow token → the
landing's `#9d7bf7`-class fix, ideally a shared `--color-accent-text` token),
`SettingsView.swift` → `scaledFont` + flexible width; live-AT session on the desktop
widget's Connect button — if unreachable, document popover parity as the keyboard path in
the app README. *Verify:* contrast numbers per element; VoiceOver/keyboard session notes;
`npm run build`. *Commit:* `fix(site,menubar): AA on sub-pages + Settings Dynamic Type`.

**Unit F3 — Site niceties.** *Goal:* close the small honesty/hygiene gaps (SITE-08/09).
*Scope:* /surfaces mock gets the "Illustrative sample" caption (or swap in the real
screenshot); delete `popover-light.png` + dead `icon` config; add branded `404.astro`;
robots.txt + `@astrojs/sitemap`. *Verify:* build + 404 route check + grep. *Commit:*
`chore(site): mock caption, dead assets, 404, sitemap`.

**Unit F4 (optional, non-gating) — README imagery.** Regenerate `--snapshot` screenshots;
one hero image in README; delete/regenerate `docs/review/` (GAP-05/06). *Commit:*
`docs: README hero screenshot; refresh screenshot corpus`.

## Phase G — Final QA + tag v1.0.0 (🔴 gated throughout)

**Unit G1 — Full verification matrix.** Fresh-machine (isolated `$HOME`) install → connect
via OAuth path AND cookie path → `houdini update --check`/`update` → uninstall per the new
docs; live site re-audit (all 7 pages, visual + a11y, Claude in Chrome); CI green on
master. *Verify:* the complete pasted matrix. *No commit (report).*

**Unit G2 — Release v1.0.0.** Per the A3-fixed flow and A0(4)'s ADR-010: bump (config.ts,
README, Info.plist, CLI version), tag, CI publishes + verifies, prune *pointers* (and
releases per the ratified policy), deploy site, post-release `houdini update --check`
smoke from a v0.4.0 install (the first real update!). **Every step owner-signed.**
*Verify:* release URL, checksums, live-site checks, update transcript.

## Cadence

One unit → discovery-first → implement → verify (pasted evidence) → update BACKLOG/docs →
commit → report. Ultracode may parallelize units with disjoint file scopes (B/C/D after
A2+A0); E is serial after B5; F after B; G last. If any unit finds its premise changed
(this audit is 2026-07-03-fresh), re-verify against HEAD before building.
