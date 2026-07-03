# Roadmap (phased delegation plan)

Each phase = one or more prompts handed to Claude Code. We build the data layer before any UI, then frontends, then distribution and site. Order is chosen to de-risk early.

**Markers:** ✅ shipped · `[~]` partially shipped · **deferred** noted inline · unmarked = not started.

## Phase 0 — Repo foundation ✅ (done by the Brain)
Docs (README, ARCHITECTURE, DECISIONS, PROVIDERS, WORKFLOW — the last since merged into CLAUDE.md), directory skeleton, ADRs. Git init + first commit handled in Phase 1 prompt.

## Phase 1 — FetcherCore + Claude adapter (data layer) ✅ (shipped in v0.4.0 — Claude live)
- SwiftPM workspace: `FetcherCore` library + `houdini` executable.
- `UsageProvider` protocol, `CredentialStore` (Keychain), models.
- **Claude `.keychainOAuth` adapter**: read Claude Code OAuth token, call `api.anthropic.com/api/oauth/usage` with mandatory `claude-code/<ver>` UA, parse 5h/weekly/Opus.
- `houdini` prints the live snapshot as JSON.
- **Validation gate:** run `houdini` against the real account; confirm numbers match `claude.ai/settings/usage`.

## Phase 2 — Menu bar app (flagship) ✅ (shipped in v0.4.0)
- SwiftUI `MenuBarExtra` + popover; timer in scene-level `ObservableObject` (60s).
- Settings: choose provider, launch-at-login (`SMAppService`), thresholds/colors.

## Phase 3 — Desktop widget ✅ (native; superseded the Übersicht `.jsx`)
- Shipped as a SwiftUI card in a desktop-level `NSPanel`, **inside the menu bar app** — draggable,
  resizable, persistent (frame + displayID), glass with a Reduce-Transparency solid fallback.
- Shares the app's `UsageModel`, so it tracks the same true 60s refresh. The earlier Übersicht
  `.jsx` prototype (`apps/ubersicht`) is removed.

## Phase 4 — WidgetKit widget (glanceable) — **deferred** (hard-blocked under ad-hoc distribution; ADR-013)
- Widget extension + App Group shared container; `.after(~15min)`; honest "updated X min ago" copy.
- Menu bar app writes to App Group + `reloadTimelines()` *(moved here from Phase 2 — this
  bridge only exists to feed a WidgetKit surface, so it lands with this phase, not before)*.

## Phase 5 — More providers `[~]`
- ✅ Claude `.sessionCookie` fallback (embedded WebView login) — shipped (in v0.4.0).
- OpenAI Platform + Anthropic Console admin-API adapters.
- ChatGPT Plus experimental.

## Phase 6 — Distribution ✅ (decided + shipped)
- Decision finalized per ADR-006 (revised): the ad-hoc-signed `install.sh` / curl|bash path
  is the shipping reality; notarized DMG / Homebrew stay documented future options.
- `install.sh` (SHA-256-verified, no sudo) + release automation
  (`.github/workflows/release.yml`, the sole publisher) shipped.

## Phase 7 — Landing site ✅ (live at houdini.salomao.org)
- Astro + Tailwind, dark Linear-style, deployed on **Vercel** (project `houdini`; manual prebuilt `vercel --prod` from `site/`, no site CI — the only workflow, `.github/workflows/release.yml`, publishes the macOS app on `v*.*.*` tags). Install artifact distributed via `install.sh` from the pinned GitHub Release.
- Hero + demo, install CTA, how-it-works, one honest capability line (no provider grid — ADR-010/011), privacy/trust, FAQ.

## Phase 8 — Polish & launch `[~]` (in progress — BACKLOG P2/P3)
- Icon/branding, accessibility pass, auto-update (Sparkle) for mature release, README badges, screenshots/video.

## Phase 9 — Mobile: Houdini for iPhone (iOS)  — NEW DIRECTION
See `apps/ios/PLAN.md` and `DECISIONS.md` ADR-008. Native iOS app (no PWA — CORS + httpOnly cookie + the "no server sees your creds" promise rule it out).
- **FetcherCore iOS-ready** `[~]` (by construction — guards verified by inspection, macOS build unchanged; the iOS compile itself is *unverified*, no iOS SDK here — see `apps/ios/PLAN.md` §5) — only macOS-only dep was `Foundation.Process`; guarded behind `#if os(macOS)`. Cookie path (`ClaudeCookieProvider` + `ClaudeUsageParser`) reused verbatim.
- **App scaffold** ✅ (source only — *not* compiled; needs Xcode) — SwiftUI app + `UsageViewModel`, in-app `WKWebView` claude.ai login → capture `sessionKey` → iOS Keychain → native `URLSession` fetch.
- **WidgetKit** — Home Screen + Lock Screen widgets reading the App Group cached snapshot; honest ~15–30 min refresh ("updated X min ago"), **not** 60s (same Apple budget as Phase 4 / ADR-002).
- **Distribution** — needs **Apple Developer Program ($99/yr) + Xcode**; TestFlight (beta) → App Store. No free install-by-link on iOS (unlike the Mac app).
- **Blocked on:** Xcode + the $99 program + a confirmed Team ID / bundle-ID prefix. None producible on this CommandLineTools-only machine.

## Phase 10 — Android (future, not scheduled)
- Separate Kotlin/Compose app, same cookie approach (`WebView` login → `CookieManager` reads httpOnly → Keystore → `OkHttp`, no CORS), Glance home-screen widget. Waits until the iOS app proves the mobile thesis.
