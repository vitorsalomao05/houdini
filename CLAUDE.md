# CLAUDE.md — Houdini (operating guide for Claude Code)

> This is the **Build Conductor** operating layer for the Houdini monorepo. It tells
> Claude Code *how to work here*. For the *product & why*, see [`CONTEXT.md`](CONTEXT.md).
> For *what to build next*, see [`BACKLOG.md`](BACKLOG.md).

## What Houdini is (one line)

A local-first **macOS app** for subscription consumption, limits, and quota resets — in
the menu bar and on the desktop. **Claude (Pro/Max) is live today**; Claude official-client
connections and **ChatGPT · Codex** limits are the accepted work in validation. No Houdini
account or server; see ADR-004/011/012 for provider scope and credential boundaries.

Pitch we lead with on the site: *"See your Claude spend at a glance, right from your
Mac's menu bar."*

## This is a monorepo

```
core/            FetcherCore Swift package (shared data layer) + `houdini` / `houdini-selftest` CLI
apps/menubar/    SwiftUI menu bar app + native desktop widget (flagship) — SPM exe wrapped by build.sh
apps/ios/        Native iOS app + widget scaffold (cookie auth, XcodeGen; not yet built — ADR-008)
site/            Astro + Tailwind landing page (houdini.salomao.org; deploys via Vercel)
install.sh       one-liner installer (SHA-256-verified download from a pinned Release)
scripts/         developer bootstrap (`init.sh`) — release CI is .github/workflows/release.yml
conductor/       Build Conductor artifacts — `audits/` is tracked; `prompts/` is local-only (gitignored)
audit/           v1 audit corpus (charter, diagnosis, plan — 2026-07-03)
```

**Environment:** macOS 14+ / Apple Silicon. App = Swift / SwiftUI (menu bar + desktop
widget ship as one SwiftPM executable; no `.xcodeproj`, no full Xcode required — build via
`apps/menubar/build.sh`). Site = Astro 5 + Tailwind 4. Installer is pinned to a release tag
(currently `v1.0.0`). New here? Run `scripts/init.sh` to verify your toolchain and print the
repo map + real commands + the top BACKLOG item.

## Source-of-truth docs (read before changing related areas)

- `README.md` — install, core idea, providers table, repo layout, privacy posture.
- `ARCHITECTURE.md` — system design + diagram.
- `DECISIONS.md` — ADRs. **Respect these unless we explicitly revise one.**
- `PROVIDERS.md` — provider-adapter contract + per-provider specs.
- `ROADMAP.md` — phased plan.
- `RELEASE.md` — release checklist + per-release go-live records.
- `CONTEXT.md` / `BACKLOG.md` — the Build Conductor product context and work queue.
- **Subscription login, quota reads, or provider switching:** read
  `docs/plans/subscription-connections.md` for the accepted scope and validation criteria,
  then `DECISIONS.md` ADR-004/005/011/012 and `PROVIDERS.md` for the integration boundaries.

## How we work (Build Conductor)

1. **FRAME** (now): interview → these three docs → repo survey → baseline commit.
2. **Build loop**: pull the top `BACKLOG.md` item → discovery-first (map current state,
   confirm assumptions) → implement in a small, reviewable change → verify → update
   `BACKLOG.md` → commit.
3. Keep `BACKLOG.md` and `CONTEXT.md` current as reality changes. **Link, don't restate:**
   work status lives only in `BACKLOG.md` and decision text only in `DECISIONS.md` — other
   docs point at them instead of copying. Prefer proposing and discussing before any large
   rebuild — everything is open to change, but not silently.

### Brain ⇄ Builder handoff (response format)

*(Merged from the former `WORKFLOW.md`, 2026-07-03.)* Two roles: the **Brain** (planning
agent) researches, decides, reviews, and emits one copy-paste **PROMPT** per unit of work;
the **Builder** (Claude Code) executes it in this repo. Every prompt ends by requiring this
structured response, so each handoff stays compact and verifiable:

```
### RESULT
status: success | partial | blocked
summary: <2–4 sentences>

### CHANGES
- <path> — <what changed>

### COMMANDS_RUN
- <cmd> → <result/exit>

### VALIDATION
- <what was tested> → <pass/fail + key output>

### BLOCKERS / DECISIONS_NEEDED
- <question for the Brain, or "none">

### NEXT
- <suggested next step, or "awaiting Brain">
```

If blocked, set `status: blocked` and ask in `BLOCKERS` rather than guessing. Paste real
output in `VALIDATION` (evidence, not reasoning). Model routing, git rules, gated actions,
and the budget rule are defined once in the sections below — not restated per prompt.

### Model routing

- **Fable 5 (default)** — build-loop units: discovery, planning-heavy implementation,
  multi-file changes.
- **Opus 4.8** — routine/mechanical edits, line-level code review, and **security-adjacent
  code**. Houdini handles Keychain credentials and OAuth tokens, so auth/credential paths
  are security-adjacent by definition (e.g. `core/**/ClaudeAuth*`, `ClaudeOAuthProvider`,
  `ClaudeCodeLogin`, `CodexAppServerClient`, anything reading the Keychain or handling cookies/tokens) → Opus.
- **Sonnet** — interactive/conversational sessions.

### Git workflow

- The **Builder owns git** — it branches, stages, and commits its own work.
- **Branch per unit** of work (`feat/…`, `fix/…`, `chore/…`, `docs/…`).
- **Conventional Commits**; **no AI-attribution trailer** (no `Co-Authored-By: Claude`,
  no "Generated with…" lines).
- 🔴 **Gated actions — explicit human sign-off required first:** `push --force`,
  `reset --hard`, notarization/signing/release steps, and **any change touching
  `install.sh` or `SHASUMS256.txt`** (see Guardrails: installer integrity).

### Evidence, not reasoning

- Reports prove results with pasted command output (diffs, test runs, grep hits) — not
  narrative confidence. If it wasn't run, it isn't verified.

### Anti-over-engineering / budget

- Smallest change that satisfies the unit. No speculative abstractions, no drive-by
  refactors. If a unit balloons past its BACKLOG scope, stop and re-plan rather than
  pushing through.

## Current priorities (app-first — see BACKLOG for detail)

The active entry in `BACKLOG.md` is authoritative. Complete the accepted subscription
scope through validation; distinguish local implementation, observed behavior, and a
published release. Preserve the paused #3/#4 WIPs and their index/worktree separation.
Historical site, API-provider, and updater entries do not expand this scope.

## Guardrails (do not violate without explicit sign-off)

- **Security & privacy first.** Persist Houdini-owned credentials only in the macOS
  Keychain; preserve the read-only existing-Claude fallback described in ADR-005/012.
  Authentication goes only to the relevant provider, with no Houdini backend. Keep
  tokens/cookies out of logs, plaintext caches, and process diagnostics. Any future
  elevated permission (e.g. the last-resort browser-scrape fallback) must be provably
  secure and least-privilege before it ships.
- **Free & open source.** No paywalls, no account required to install or use.
- **Ruthless minimalism on the site.** Target is **zero visual clutter/pollution** and
  **WCAG 2.1 AA** accessibility. Every added element must earn its place.
- **Respect existing ADRs.** e.g. the site brands neither the menu bar nor the desktop
  widget separately (ADR-010/011); the Notification Center widget is not advertised
  (ADR-002, ~15 min refresh cap). Revise an ADR openly rather than contradicting it.
- **Installer integrity is sacred.** `install.sh` must keep verifying SHA-256 against
  `SHASUMS256.txt`, install without `sudo`, avoid Gatekeeper prompts, and never force
  launch-at-login. Don't weaken these claims — the site advertises them.

## Verification expectations (per change)

- **Auth changes:** test existing Claude OAuth discovery and saved-cookie fallback,
  official-client connection/cancellation, and isolated Codex account/limits reads with
  fake clients and credentials. Confirm no secrets enter disk logs or raw process-error
  output. Record live provider login separately from synthetic tests; see the scope's
  complete acceptance criteria.
- **Any UI change (app or site):** check keyboard access, visible focus, and text
  contrast; don't regress accessibility.
- **Site changes:** re-run the live visual + accessibility audit (Claude in Chrome) and
  confirm the change moves toward zero-clutter, not away.
- **No telemetry or third-party trackers** get added to the site or app.

## Survey findings — FRAME questions resolved (2026-06-30 → 2026-07-01; historical record)

*Past tense — these record what the survey found **at the time**. Current state lives in
`BACKLOG.md` (status) and `DECISIONS.md` (decisions).*

- **Site deploy target + CI** — resolved: **Vercel**, project `houdini`
  (`site/.vercel/project.json`), deployed manually via the prebuilt CLI
  (`vercel build --prod && vercel deploy --prebuilt --prod` from `site/` — see `RELEASE.md`).
  At survey time no site CI existed and `release.yml` had never published a release (fixed
  2026-07-03 — v1 audit A3: `release.yml` is now the sole publisher). `ROADMAP.md` Phase 7's
  "Cloudflare Pages" was stale and was corrected 2026-07-01.
- **Non-CLI login root cause** — confirmed at the code level, *pre-slice (a)*: OAuth discovery
  was pinned to the single Keychain item `service="Claude Code-credentials"` — no alternate
  item names, no `~/.claude/.credentials.json` file fallback, no `refreshToken` use — so a
  user without the Claude Code CLI was forced onto the ephemeral, short-lived claude.ai
  **cookie** WebView. **P1 slice (a) then shipped** ordered Keychain discovery
  (`"Claude Code-credentials"` → `"Claude Code"`), a read-only credentials-file fallback, and
  refresh machinery (live endpoint left unwired). The 2026-09-20 ADR-012 revision permits
  launching official Claude Code login; Houdini-owned refresh, PKCE, and new cookie
  capture remain outside the accepted scope.
- **Test setup** — `core/` has real tests: `FetcherCoreTests` (swift-testing / `import Testing`)
  plus a `houdini-selftest` executable that re-runs the same assertions on CommandLineTools-only
  machines where the test runner previously no-oped. Run `swift test` and report the actual
  test count; the installed Swift 6.4 CLT runs the suites. **No test targets** in `apps/menubar` (smoke via built
  binary flags: `--selftest`/`--metrictest`/`--snapshot`/`--launchtest`), `apps/widget`, `apps/ios`,
  or `site/`.
- **`feature_list.json` / init script** — neither existed at FRAME; both were created that
  pass. `scripts/init.sh` remains; `feature_list.json` was **deleted 2026-07-03** (v1 audit
  DOC-09/ORG-05 — it had no generator and no consumer).

## Open questions / proposed doc fixes (flagged, not silently changed)

- **Claude subscription-auth posture — REVISED 2026-09-20:** ADR-012 retains read-only
  access and the recorded residual risk while permitting Houdini to initiate the official
  Claude Code browser login. Read the ADR before changing any credential ownership or
  persistence behavior.
- **ADR-006 vs reality — RESOLVED 2026-07-01:** ADR-006 was **revised in place** to record that the
  ad-hoc-signed `install.sh` / `curl|bash` path is the shipping reality (notarized DMG deferred),
  ending the drift.
- **ROADMAP.md staleness — RESOLVED 2026-07-01:** ROADMAP **refreshed** — Phase 7 corrected to
  Vercel, the ADR-010/011-forbidden "providers grid" dropped, and the stale ✅ / "← WE ARE HERE"
  markers updated now that v0.4.0 is live.
- **Google Gemini — RESOLVED 2026-07-03 (v1 audit, A0):** the claim was **dropped** from
  `README.md`/`CONTEXT.md`/`CLAUDE.md` (and the since-deleted `feature_list.json`) (DOC-04).
  Re-add only once a real `PROVIDERS.md` spec + ROADMAP phase exist.
- **Übersicht — RESOLVED 2026-07-03 (v1 audit, A0):** ADR-002/ADR-003 revised in place —
  Übersicht is recorded as historical; ADR-013 fixes the NSPanel desktop-surface decision.
