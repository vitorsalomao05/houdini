# CONTEXT.md — Houdini (product & current state)

> The *why* and *what* behind Houdini. Pairs with [`CLAUDE.md`](CLAUDE.md) (how we work)
> and [`BACKLOG.md`](BACKLOG.md) (what's next). Framed 2026-07-01 · trued 2026-07-03 (v1 audit).

## Product overview

Houdini is a **local-first macOS app** (macOS 14+, Apple Silicon) that reveals a user's
**AI usage and spend**. It surfaces the same data two co-equal ways:

- **Menu bar** — your tightest limit, always visible; popover with full detail. ~60s refresh.
- **Desktop widget** — the same gauges on the wallpaper as a draggable, resizable glass
  panel (SwiftUI in an `NSPanel`), native to the app. ~60s refresh.

**Claude (Pro/Max) is live today**: 5-hour and weekly limits, reset timers, and any
extra-usage spend, refreshed about every 60 seconds. **OpenAI and the Anthropic
Console are on the roadmap** (see `PROVIDERS.md` / `ROADMAP.md`).

The core mechanism: Houdini reads the user's *existing* credential (Keychain OAuth token
or session cookie) and calls each provider's **JSON usage endpoint directly** — no bundled
browser, no scraping (a browser-scrape adapter survives only as a last-resort fallback).

## Positioning

- **Lead pitch:** *"See your Claude spend at a glance, right from your Mac's menu bar."*
- **Broader promise:** reveal your AI usage and spend, local-first, across providers.
- **Audience:** Mac developers and AI power users — especially Claude Pro/Max and Claude
  Code users — who want a fast, practical, always-visible read on consumption.
- **Name:** "Houdini" = the number *revealed*, not hidden.

## Distribution & pricing

- **100% free and open source.** No account, no payment, no server.
- **Primary conversion action = install.** Users land on **houdini.salomao.org** and run
  the one-liner, which downloads the ad-hoc-signed `Houdini.app` + `houdini` CLI from a
  **pinned Release**, **verifies SHA-256**, and installs **without `sudo`** and **without
  a Gatekeeper prompt** (app → `~/Applications`, CLI → `~/.local/bin`). Safe to re-run;
  offers but never forces launch-at-login.
- Current release: **v0.4.0**.

## Trust & security posture (a first-class selling point)

- Credentials **never leave the device** — tokens/cookies stay in the macOS **Keychain**.
- **There is no Houdini server.** Requests go straight from the user's Mac to each
  provider's own endpoint.
- Because the app touches logins, the site carries a **dedicated trust/privacy section**.
- Messaging leads with: **safe by design, robust local data handling, no compromise.**
- Principle for the future: any elevated permission (e.g. the browser-scrape fallback)
  must be provably secure and least-privilege before it ships.

## Current state (2026-07-03)

**App**
- Claude provider is **live** (v0.4.0). It reads the **Claude Code OAuth token in
  Keychain** *or* a **claude.ai session cookie**.
- **Claude auth is deliberately KEPT READ-ONLY and its subscription-auth expansion is FROZEN**
  (see **ADR-012**, decided 2026-07-01). Both paths use the user's *existing* on-device
  credential; Anthropic's Consumer Terms restrict third-party use of subscription OAuth/cookies,
  so Houdini stays read-only and adds **no** refresh, first-run PKCE, or cookie-hardening. P1
  shipped only slice (a) (broadened discovery of an existing credential); a user with **no**
  Claude Code credential anywhere is **out of scope by decision**.
- Menu bar + native desktop widget ship inside one app. A Notification Center WidgetKit
  widget was never built and is **deferred** (hard-blocked under the current
  distribution — ADR-013); it was intentionally never advertised (ADR-002).

**Site** (`site/`, Astro + Tailwind, live at houdini.salomao.org)
- Live but **not fully polished**. Target is a **100% clean site with zero visual
  clutter/pollution** and strong accessibility.
- **Live visual + accessibility audit DONE 2026-07-01** (Claude in Chrome; full report at
  `conductor/audits/2026-07-01-site-audit.md`). It found the site already calm/low-clutter and
  mostly WCAG-AA clean. The four ToS-independent quick-wins have **shipped** (commit `78e2bf3`):
  the product screenshot now shows on mobile, the curl one-liner is fully readable, footer +
  terminal-label contrast pass AA, and decorative SVGs are confirmed `aria-hidden` — so the site
  now passes AA on the audited items and shows the product shot on mobile. The hero H1 is
  kept generic (ToS-gated, see **ADR-012**); the short user-facing transparency line is now
  **mandatory for v1** (ADR-012 §6, revised 2026-07-03) and queued for implementation
  (app Settings + site privacy page).

## Design direction

Minimalist and calm: generous whitespace, one clear install CTA, legible typography, a
real product screenshot/demo, and a distinct trust/privacy section. Accessible by default
(WCAG 2.1 AA). Respect the no-separate-branding decision for menu bar vs desktop widget.

## Priorities (app-first) & why

1. **Login refactor — DECIDED / CAPPED (ADR-012).** The Claude integration stays **read-only**
   on the user's existing credential and its subscription-auth expansion is **frozen**; slice (a)
   (broadened discovery) shipped, and a user with no Claude Code credential anywhere is out of
   scope by decision. Active focus has moved to #2.
2. **Widget accessibility + polish** — make the core surfaces (menu bar + desktop widget)
   genuinely polished and accessible end to end.
3. **Site polish + ongoing features** — with the app solid, drive the site to zero clutter
   and keep it evolving with new features and ideas.

## Survey findings (FRAME, resolved 2026-07-01 — historical record)

*Past tense — what the survey found at the time; current status lives in `BACKLOG.md`.*

- **Unified login — hypothesis CONFIRMED at the code level (pre-slice (a)).** At survey time
  the app read exactly two credential sources: (1) the Claude Code CLI's OAuth token, from the
  single Keychain item `service="Claude Code-credentials"` (via the `security` CLI); and (2) a
  claude.ai `sessionKey` cookie in Houdini's own Keychain item `Houdini-claude-session`, captured
  by a WebView login. The OAuth lookup was hardcoded to that one item name — no alternates, no
  `~/.claude/.credentials.json` file fallback, no refresh-token use — so a non-CLI user had no
  OAuth item and was forced onto the ephemeral, short-lived cookie WebView. **P1 slice (a) then
  shipped** broadened discovery (ordered Keychain items + file fallback + refresh machinery,
  live endpoint left unwired); everything further is **frozen by ADR-012** (see `BACKLOG.md` P1).
- **Site deploy target + CI — resolved: Vercel.** Project `houdini`, deployed manually via the
  prebuilt CLI (`vercel build --prod && vercel deploy --prebuilt --prod` from `site/` — see
  `RELEASE.md`). At survey time no site CI existed in `.github/workflows/` (only the app release
  workflow). `ROADMAP.md` Phase 7's "Cloudflare Pages" was stale; corrected 2026-07-01.
- **Test coverage — resolved.** `core/` has swift-testing suites (`FetcherCoreTests`) plus a
  `houdini-selftest` runnable mirror; no automated tests in `apps/*` or `site/`.
- **Constraints:** none are hard. Everything (stack, brand, existing implementation) is
  open to change — but changes to documented decisions should update the relevant ADR
  (see the ADR-006-vs-reality flag in `CLAUDE.md`).

## Not-yet-surfaced in this doc set

- `apps/ios/` — a native iPhone app + WidgetKit scaffold (cookie auth, reuses `FetcherCore`;
  XcodeGen, not yet buildable here) exists per ADR-008 / ROADMAP Phase 9. It is a real, coherent
  scaffold, not junk — just absent from the top-of-repo layout maps until now.
