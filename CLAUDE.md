# CLAUDE.md — Houdini (operating guide for Claude Code)

> This is the **Build Conductor** operating layer for the Houdini monorepo. It tells
> Claude Code *how to work here*. For the *product & why*, see [`CONTEXT.md`](CONTEXT.md).
> For *what to build next*, see [`BACKLOG.md`](BACKLOG.md).

## What Houdini is (one line)

A local-first **macOS app** that reveals your AI usage and spend — in the menu bar and
on the desktop. **Claude (Pro/Max) is live today**; OpenAI and the Anthropic
Console are on the roadmap. No account, no server — credentials stay in the Keychain.

Pitch we lead with on the site: *"See your Claude spend at a glance, right from your
Mac's menu bar."*

## This is a monorepo

```
core/            FetcherCore Swift package (shared data layer) + `houdini` / `houdini-selftest` CLI
apps/menubar/    SwiftUI menu bar app + native desktop widget (flagship) — SPM exe wrapped by build.sh
apps/widget/     WidgetKit Notification Center widget — README-only placeholder today (unadvertised, ADR-002)
apps/ios/        Native iOS app + widget scaffold (cookie auth, XcodeGen; not yet built — ADR-008)
site/            Astro + Tailwind landing page (houdini.salomao.org; deploys via Vercel)
install.sh       one-liner installer (SHA-256-verified download from a pinned Release)
scripts/         release/init helpers — `init.sh` bootstrap; release CI is .github/workflows/release.yml
```

**Environment:** macOS 14+ / Apple Silicon. App = Swift / SwiftUI (menu bar + desktop
widget ship as one SwiftPM executable; no `.xcodeproj`, no full Xcode required — build via
`apps/menubar/build.sh`). Site = Astro 5 + Tailwind 4. Installer is pinned to a release tag
(currently `v0.4.0`). New here? Run `scripts/init.sh` to verify your toolchain and print the
repo map + real commands + the top BACKLOG item.

## Source-of-truth docs (read before changing related areas)

- `README.md` — install, core idea, providers table, repo layout, privacy posture.
- `ARCHITECTURE.md` — system design + diagram.
- `DECISIONS.md` — ADRs. **Respect these unless we explicitly revise one.**
- `PROVIDERS.md` — provider-adapter contract + per-provider specs.
- `ROADMAP.md` — phased plan.
- `CONTEXT.md` / `BACKLOG.md` — the Build Conductor product context and work queue.

## How we work (Build Conductor)

1. **FRAME** (now): interview → these three docs → repo survey → baseline commit.
2. **Build loop**: pull the top `BACKLOG.md` item → discovery-first (map current state,
   confirm assumptions) → implement in a small, reviewable change → verify → update
   `BACKLOG.md` → commit.
3. Keep `BACKLOG.md` and `CONTEXT.md` current as reality changes. Prefer proposing and
   discussing before any large rebuild — everything is open to change, but not silently.

### Model routing

- **Fable 5 (default)** — build-loop units: discovery, planning-heavy implementation,
  multi-file changes.
- **Opus 4.8** — routine/mechanical edits, line-level code review, and **security-adjacent
  code**. Houdini handles Keychain credentials and OAuth tokens, so auth/credential paths
  are security-adjacent by definition (e.g. `core/**/ClaudeAuth*`, `ClaudeOAuthProvider`,
  `ClaudeLoginWindow`, anything reading the Keychain or handling cookies/tokens) → Opus.
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

1. **P1 · Login/credential refactor** — simpler, works for *any* Claude Code user, not
   just those with the CLI OAuth token in Keychain. *(Capped at slice (a) — broadened
   discovery of an existing credential — per ADR-012; further subscription-auth expansion is
   frozen, and a user with no Claude Code credential anywhere is out of scope by decision.)*
2. **P2 · Widget accessibility + visual polish** — menu bar + desktop widget, end to end.
3. **P3 · Site polish + ongoing features** — get the site to *zero visual clutter*, then
   keep shipping features/ideas as requested. The site is an evolving surface, not a
   one-time deliverable.

## Guardrails (do not violate without explicit sign-off)

- **Security & privacy first.** Credentials live only in the macOS Keychain. There is no
  Houdini server and must not be one; requests go straight from the user's Mac to each
  provider's own endpoint. Never log, transmit, cache to disk, or otherwise leak tokens
  or cookies. Any *future* elevated permission (e.g. the last-resort browser-scrape
  fallback) must be provably secure and least-privilege before it ships.
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

- **Auth changes:** test *both* the CLI-token path and the non-CLI path; confirm no
  credential ever leaves the device or hits disk/logs.
- **Any UI change (app or site):** check keyboard access, visible focus, and text
  contrast; don't regress accessibility.
- **Site changes:** re-run the live visual + accessibility audit (Claude in Chrome) and
  confirm the change moves toward zero-clutter, not away.
- **No telemetry or third-party trackers** get added to the site or app.

## Survey findings — FRAME questions resolved (2026-06-30 → 2026-07-01)

- **Site deploy target + CI** — **Vercel**, project `houdini` (`site/.vercel/project.json`),
  deployed **manually via the prebuilt CLI** (`vercel --prod` from `site/`; prebuilt output in
  `site/.vercel/output/`). **No site CI** in `.github/workflows/` — the only workflow there
  (`release.yml`) builds + publishes the macOS **app** on `v*.*.*` tags. A Vercel Git
  integration *may* also exist dashboard-side but is not provable from the repo.
  (Note: `ROADMAP.md` Phase 7 still says "Cloudflare Pages" — **stale, should be corrected**.)
- **Non-CLI login root cause** — confirmed at the code level. OAuth discovery is pinned to the
  single Keychain item `service="Claude Code-credentials"` (`core/.../ClaudeOAuthProvider.swift:45`,
  read at `ClaudeAuth.swift:37`): no alternate item names, no `~/.claude/.credentials.json` file
  fallback, no `refreshToken` use. A user without the Claude Code CLI lacks that exact item, so the
  OAuth path is impossible for them and they're forced onto the claude.ai **cookie** WebView, which
  uses an *ephemeral* store (`ClaudeLoginWindow.swift:40`) and a short-lived, non-refreshable
  cookie. Full trace + 3 candidate fixes live in `BACKLOG.md` (P1). Recommended: broaden OAuth/token
  discovery now (no ADR change), pursue a first-run OAuth PKCE flow as the durable answer.
- **Test setup** — `core/` has real tests: `FetcherCoreTests` (swift-testing / `import Testing`)
  plus a `houdini-selftest` executable that re-runs the same assertions on CommandLineTools-only
  machines (`swift test` no-ops there). **No test targets** in `apps/menubar` (smoke via built
  binary flags: `--selftest`/`--metrictest`/`--snapshot`/`--launchtest`), `apps/widget`, `apps/ios`,
  or `site/`.
- **`feature_list.json` / init script** — neither existed at FRAME; both were created that
  pass. `scripts/init.sh` remains; `feature_list.json` was **deleted 2026-07-03** (v1 audit
  DOC-09/ORG-05 — it had no generator and no consumer).

## Open questions / proposed doc fixes (flagged, not silently changed)

- **Claude subscription-auth posture — DECIDED 2026-07-01 (ADR-012):** keep the Claude integration
  **read-only** on the user's existing credential and **freeze** expansion (no refresh / PKCE /
  cookie-hardening); a user with no Claude Code credential anywhere is out of scope by decision.
  P1 is capped at slice (a). See ADR-012.
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
