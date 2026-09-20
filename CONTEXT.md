# CONTEXT.md — Houdini (product & current state)

> The *why* and *what* behind Houdini. Pairs with [`CLAUDE.md`](CLAUDE.md) (how we work)
> and [`BACKLOG.md`](BACKLOG.md) (what's next). Framed 2026-07-01 · direction revised 2026-09-20.

## Product overview

Houdini is a **local-first macOS app** (macOS 14+, Apple Silicon) that reveals a user's
**subscription consumption, quota limits, and reset times**. It surfaces the same data two co-equal ways:

- **Menu bar** — your tightest limit, always visible; popover with full detail. ~60s refresh.
- **Desktop widget** — the same gauges on the wallpaper as a draggable, resizable glass
  panel (SwiftUI in an `NSPanel`), native to the app. ~60s refresh.

The **v1.1.0** release supports **Claude** and **Codex** consumption and reset times,
with connections initiated from Houdini through their official clients. Claude
retains its 5-hour, weekly and extra-usage readings; Codex shows its returned quota
windows. Release verification and acceptance are recorded in `RELEASE.md` and `BACKLOG.md`.

Claude retains its existing usage source and saved-session fallback. Codex data describes
the quota groups reported by its official client, not a universal quota for every
ChatGPT feature. API spending, subscription billing, invoices, and
renewal dates are outside this work (ADR-004/011/012).

### Subscription vocabulary

- **Subscription:** the selected Claude or Codex subscription whose supported consumption
  Houdini displays; a provider API account is a separate product.
- **Codex:** the app's name for quota usage and resets reported by the official Codex client.
  These limits cover the returned Codex groups.
- **Quota window:** a provider-reported allowance over a period, with a reported percentage
  and optional reset time. An unavailable value is unknown, never zero by inference.
- **Reset:** when a quota window renews; it is not the subscription's billing renewal.
- **Connection:** the account can be used to read its supported usage. Completing browser
  sign-in alone does not establish that usage data is available.

## Positioning

- **Site pitch:** subscription consumption and reset times for Claude and Codex.
- **Product direction:** reveal subscription consumption and resets across supported providers.
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
- Current release target: **v1.1.0**; publication evidence lives in `RELEASE.md`.

## Trust & security posture (a first-class selling point)

- Houdini persists credentials in the macOS **Keychain**; authentication is sent only to
  the relevant provider, never to a Houdini server or logs. Existing Claude credential
  discovery and delegated Codex storage are bounded by ADR-005/012.
- **There is no Houdini server.** Requests go straight from the user's Mac to each
  provider's own endpoint.
- Because the app touches logins, the site carries a **dedicated trust/privacy section**.
- Messaging leads with: **safe by design, robust local data handling, no compromise.**
- Principle for the future: any elevated permission (e.g. the browser-scrape fallback)
  must be provably secure and least-privilege before it ships.

## Current state (2026-09-20)

**App**
- Claude retains its established usage provider. It reads the **Claude Code OAuth token in
  Keychain** *or* a **claude.ai session cookie**.
- The connection action launches the official Claude Code browser flow and
  then reuses the established credential. Existing OAuth discovery and previously saved
  cookies remain readable. Claude usage access remains a private integration with the
  residual risk recorded in **ADR-012**; launching an official client does not remove it.
- Codex connections and quota reads use the official Codex App Server with a separate
  Houdini authentication scope. Both new connection flows require their official client;
  missing clients lead to installation guidance. See `PROVIDERS.md` for the contract and
  [`subscription scope`](docs/plans/subscription-connections.md) for acceptance criteria.
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
  **mandatory** (ADR-012 §6, revised 2026-07-03) and present in app Settings and
  the site's privacy page.

## Design direction

Minimalist and calm: generous whitespace, one clear install CTA, legible typography, a
real product screenshot/demo, and a distinct trust/privacy section. Accessible by default
(WCAG 2.1 AA). Respect the no-separate-branding decision for menu bar vs desktop widget.

## Priorities (app-first) & why

Current work and validation status live in `BACKLOG.md`. The accepted priority is
subscription consumption and reliable connection initiation for Claude and Codex,
using the menu bar, popover, and desktop widget. The paused Release Contract (#3) and
Installation Lifecycle (#4) WIPs remain separate; this scope does not resume them.

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
  live endpoint left unwired). That round froze expansion; the bounded official-client
  connection revision is recorded in ADR-012 (2026-09-20).
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
