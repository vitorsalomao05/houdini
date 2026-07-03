# Architecture

## Principle: de-risk the data layer first

The riskiest part of this product is **"can we reliably read the number the user sees?"** — not the UI. So we build and validate the data layer (FetcherCore + Claude provider) before any pixels. All three frontends are thin consumers of one shared core.

## High-level diagram

```
                  ┌─────────────────────────────────────────────┐
                  │              FetcherCore (Swift)            │
                  │                                             │
                  │  CredentialStore (Keychain read/write)      │
                  │  ClaudeOAuthCredentialSource (discovery)    │
                  │  ProviderRegistry → [UsageProvider]         │
                  │   ├─ ClaudeOAuthProvider  ("claude")        │
                  │   └─ ClaudeCookieProvider ("claude-cookie") │
                  │  ClaudeUsageParser (one parser, 2 dialects) │
                  │                                             │
                  │  fetch() → [UsageMetric]                    │
                  │   {label, pct?, used?, limit?, resetAt?,    │
                  │    dollars?, providerId}                    │
                  └───────┬───────────────┬─────────────────────┘
            links direct  │               │ CLI (JSON)
                          ▼               ▼
              ┌──────────────────────┐  ┌──────────┐
              │  MENU BAR APP        │  │  houdini │
              │  + DESKTOP WIDGET    │  │  CLI     │
              │  one process, one    │  │  --json  │
              │  UsageModel poller   │  │  stdout  │
              │  MenuBarExtra popover│  │  no cache│
              │  + NSPanel glass card│  │          │
              │  TRUE 60s ✅         │  │          │
              └──────────────────────┘  └──────────┘
```

*Planned, not built:* a WidgetKit Notification Center widget fed by an App Group
cache + `WidgetCenter.reloadTimelines()` (ADR-002). No App-Group write and no
`WidgetCenter` call exist in the app today; the design is recorded below.

## Components

### FetcherCore (Swift Package)
The single source of truth for data. No UI. Exposes:
- `UsageProvider` protocol (see `PROVIDERS.md`) and `ProviderRegistry`, holding the two shipped
  adapters: `ClaudeOAuthProvider` (`"claude"`) and `ClaudeCookieProvider` (`"claude-cookie"`).
  `ClaudeAuthResolver` picks between them at runtime based on which credential is present.
- `CredentialStore` — reads/writes secrets in the macOS Keychain (native `SecItem` calls, plus a
  `/usr/bin/security` CLI path for items whose ACL would otherwise require a prompt). Items Houdini
  itself writes (e.g. the `Houdini-claude-session` cookie) use `kSecAttrAccessibleAfterFirstUnlock`
  — deliberate, so the launch-at-login agent can read them without a prompt, accepting that the
  item is decryptable while the Mac is locked once unlocked after boot (audit SEC-09).
- `ClaudeOAuthCredentialSource` — OAuth credential discovery, tried in order: Keychain item
  `"Claude Code-credentials"` (primary), then the classic `"Claude Code"` item, then the
  `~/.claude/.credentials.json` file. Refreshes a stale token **in memory only**.
- `UsageSnapshot` — normalized result `[UsageMetric]` consumed by every frontend.
- A thin **`houdini`** executable target that prints the current snapshot as JSON to stdout — a stable contract for scripting and what we use to validate against a real account before building UI.

There is **no `Scheduler` or `Cache` component in core**. Polling and last-good caching live in
the menu bar app's `UsageModel`: a repeating timer at the user-chosen interval (30/60/120 s,
default 60 s) whose failed polls back off multiplicatively until the next success, keeping the
last good metrics in memory so the UI never flashes empty. The CLI does one fetch, no cache.

### Menu bar app (flagship) — `apps/menubar`
- SwiftUI `MenuBarExtra` (macOS 13+), `.menuBarExtraStyle(.window)` popover.
- Timer lives in an `ObservableObject` owned at scene level (NOT inside the menu view — known macOS bug where menu-hosted timers stall).
- `SMAppService.mainApp.register()` for launch-at-login, gated behind a user toggle.
- *Planned, not built:* writing the latest value into an **App Group** container and calling
  `WidgetCenter.shared.reloadAllTimelines()` for the future WidgetKit widget. No App-Group write
  or `WidgetCenter` call exists in the app today.
- True 60s refresh — the surface that fully meets the original requirement.
- Also **hosts the desktop widget** (below) in the same process, so both share one `UsageModel`/timer.

### Desktop widget (native) — part of `apps/menubar`
- A SwiftUI card hosted in a desktop-level **`NSPanel`** (`.nonactivatingPanel`): draggable by its
  background, resizable within limits (card 280×200 default; 220×150–480×360), behind app windows,
  never steals focus. Two responsive breakpoints (compact `<260pt` / regular `≥260pt`).
- **Shares the menu bar app's `UsageModel`** — same source, same true 60s refresh; no second poller.
- Glass: `NSVisualEffectView(.hudWindow, .behindWindow)` + a violet wash + a 1px gradient border +
  tight shadows; adopts the system `.glassEffect()` on macOS 26 (`#available`). ¾-ring gauges for the
  percent windows, the spend `$` as a hero number. Reduce Transparency → a solid `#15101F` card.
- Persists its frame + `displayID` to `UserDefaults`; restores across relaunch/reboot and clamps back
  onto a visible screen if a monitor is unplugged. (Replaces the former Übersicht `.jsx` widget.)

### WidgetKit Notification Center widget — DESIGNED, NOT BUILT
> **Status: designed, not built (ADR-002).** No WidgetKit target, App-Group write, or
> `WidgetCenter` call exists in the repo. This section records the design for a possible
> post-v1 glanceable surface — it describes no shipping code.
- `TimelineProvider` would read only the **cached** value from the App Group (cheap reloads).
- Steady-state `.after(~15min)` policy; host app pushes `reloadTimelines` on meaningful change.
- Honest UX copy ("updated a few minutes ago"). Cannot do 60s — Apple budget ~40–70 reloads/day. See `DECISIONS.md` ADR-002.

### Provider switcher & key handling — app Settings (design; see ADR-011, `PROVIDERS.md`)
The user picks/configures providers **inside the native app's Settings**, never on the
website. The Settings list is rendered from `ProviderRegistry`, so adding a provider in
`FetcherCore` surfaces a row with no UI rewrite (capability flags drive each row — ADR-007).
`.adminApiKey` providers (OpenAI Platform, Anthropic Console) take a key in a single secure
Settings field that is written **straight to the macOS Keychain** and read only by native
code at fetch time. **Hard rule:** a provider API/admin key is **never** placed in the
website, any frontend/JS bundle, browser env vars, `config.ts`, or the repo/git history —
Keychain only, no server (ADR-005, ADR-011). The site shows no key UI and no visible
OpenAI placeholder — just one honest capability line. *(Switcher + OpenAI adapter are not
built yet; this fixes the direction and the key-safety rule.)*

### Landing site — `site`
- Astro + Tailwind v4, dark "stage" identity. Static build → `dist/`, deployed on **Vercel**
  at `houdini.salomao.org`. App + CLI artifacts hosted on GitHub Releases.
- Information architecture (Houdini is the only brand; "Menu bar" and "Desktop widget" are
  co-equal **features**, never separate products/logos):
  - **Home** (`index.astro`) — hero (Install / How-it-works CTAs), trust strip, how-it-works,
    a compact "what it reveals" strip, "where it shows up" (menu bar + desktop, co-equal),
    one honest provider line, **privacy/trust**, FAQ, footer CTA. Detailed install lives off
    the home.
  - **`/install`** — three-step guided flow (run the one-liner → connect Claude → done),
    "what's included" (one app, two surfaces), build-from-source behind a "For developers"
    disclosure.
  - **`/guide`** — didactic walkthrough of what Houdini tracks and how to read the gauges.
- No "coming soon" placeholders in production (ADR-010). Copy-to-clipboard install block.

## Fetch mechanism priority (per provider)
1. **JSON endpoint + Keychain token/cookie** (BEST — native `URLSession`, no browser).
2. **WKWebView with injected cookies** (native fallback if JS render needed).
3. **Bundled headless Chromium / background Chrome reload** (LAST RESORT — heavy, signing pain, brittle DOM).

## Network surface — complete endpoint inventory

Houdini has no server; every request goes straight from the user's Mac to the provider.
These are **all** the endpoints reachable from the shipped macOS code:

| # | Endpoint | Auth sent | Caller |
|---|----------|-----------|--------|
| 1 | `GET https://api.anthropic.com/api/oauth/usage` | `Authorization: Bearer <OAuth token>` + `User-Agent: claude-code/<version>` | `ClaudeOAuthProvider` |
| 2 | `GET https://claude.ai/api/organizations` | `sessionKey` cookie | `ClaudeCookieProvider` |
| 3 | `GET https://claude.ai/api/organizations/{org_id}/usage` | `sessionKey` cookie | `ClaudeCookieProvider` |
| 4 | `https://claude.ai/login` (WKWebView page load) | interactive sign-in | `ClaudeLoginWindow` — browser semantics: the page may pull claude.ai subresources / SSO redirects |

No telemetry, no update check, no Houdini-owned host, no plain `http://` anywhere. Both API
paths share an ephemeral `URLSession` (no persistent cookie/cache store) and a redirect guard
(`CredentialRedirectGuard`) that strips credential headers on cross-host redirects.

## Key constraints to honor
- Always send the `User-Agent` header on the Anthropic OAuth usage endpoint (`claude-code/<version>`). Omitting it **may cause throttling under sustained use**; keep it for safety. (Phase 1 note: a single call without the UA still returned 200, so the "persistent 429" behavior is load-dependent, not absolute.)
- Poll politely (30–120s), cache, fail gracefully on auth expiry, re-prompt before cookies die (~24h warning for session cookies).
- Never log tokens. Keychain only.
