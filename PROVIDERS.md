# Provider adapters

Every data source implements one protocol. The UI never special-cases a provider; it reads capability flags and renders whatever metrics come back.

## Contract

```swift
protocol UsageProvider {
    var id: String { get }                       // "claude", "claude-cookie", "anthropic-console", "openai-platform", "chatgpt-plus"
    var displayName: String { get }
    var authMethod: AuthMethod { get }           // .keychainOAuth | .sessionCookie | .adminApiKey
    var capabilities: Capabilities { get }        // what this provider can actually supply
    var refreshInterval: TimeInterval { get }     // 30–120s typical

    func fetch() async throws -> [UsageMetric]
}

struct Capabilities: OptionSet {
    static let usagePct      = Capabilities(rawValue: 1 << 0)
    static let resetTimer    = Capabilities(rawValue: 1 << 1)
    static let dollarBalance = Capabilities(rawValue: 1 << 2)
}

struct UsageMetric {
    let label: String        // "5-hour", "Weekly", "Opus weekly", "API cost (today)"
    var pct: Double?         // 0–100
    var used: Double?
    var limit: Double?
    var resetAt: Date?
    var dollars: Double?
    let providerId: String
}

enum AuthMethod { case keychainOAuth, sessionCookie, adminApiKey }
```

Cross-cutting services in `FetcherCore`: `CredentialStore` (Keychain read/write), `ClaudeOAuthCredentialSource` (ordered credential discovery + in-memory refresh), `ClaudeUsageParser` (one parser for both Claude endpoint dialects), `CredentialRedirectGuard` (strips credential headers on cross-host redirects). There is **no `Scheduler` or `Cache` in core**: polling and last-good caching live in the menu bar app's `UsageModel` (user-chosen 30/60/120 s interval; failed polls back off multiplicatively), and the `houdini` CLI does a single uncached fetch.

---

## claude (Pro/Max) — FLAGSHIP, build first
- **Capabilities:** `usagePct`, `resetTimer` (+ `dollarBalance` if "Claude Extra" overage).
- **Primary auth:** `.keychainOAuth` — reuse the **Claude Code OAuth token**. Discovery order (`ClaudeOAuthCredentialSource`): Keychain item `Claude Code-credentials` (primary), then the classic `Claude Code` item, then the `~/.claude/.credentials.json` file. The user already runs Claude Code, so this needs zero new login.
- **Primary endpoint:** `GET https://api.anthropic.com/api/oauth/usage`
  - Headers: `Authorization: Bearer <token>` **and** `User-Agent: claude-code/<version>` (always send it — a missing UA **may cause throttling under sustained use**; the code keeps it for safety).
  - Returns 5-hour / 7-day / Opus-7-day utilization.
- **Fallback auth:** `.sessionCookie` — realized in code as a **sibling provider `claude-cookie`** (`ClaudeCookieProvider`), chosen at runtime by `ClaudeAuthResolver` when no usable OAuth credential resolves (or when the user prefers cookie auth). The `sessionKey` cookie (`sk-ant-sid01-…`) comes from an embedded WebView login and is stored in Houdini's own Keychain item (`Houdini-claude-session`). Then:
  - `GET https://claude.ai/api/organizations` → read `org_id`.
  - `GET https://claude.ai/api/organizations/{org_id}/usage` → fields: `five_hour.utilization_pct`, `five_hour.reset_at`, `seven_day.utilization_pct`, `seven_day_opus.utilization_pct`, `extra_usage.current_spending`, `extra_usage.budget_limit`.
- **Fragility:** medium (undocumented). **Risk:** low (own account), though the volume is not a trickle: steady polling at the default 60 s is ~1,440 requests/day, and the cookie path issues two requests per poll (org lookup + usage).
- **ToS / stance (ADR-012):** subscription OAuth token / claude.ai cookie use in a third-party app is **restricted by Anthropic's Consumer Terms**; Houdini's stance is **read-only + frozen** — it reads the user's existing on-device credential and adds no refresh / PKCE / cookie-hardening.
- **Reference:** `github.com/ttar-p/claude-usage-widget`, `github.com/hamed-elfayome/Claude-Usage-Tracker`.

## anthropic-console (API usage/cost) — secondary
- **Capabilities:** `dollarBalance` (cost), usage tokens. NOT remaining prepaid balance via API.
- **Auth:** `.adminApiKey` — `sk-ant-admin…` (org accounts only; unavailable for individual accounts).
- **Endpoints:** `GET https://api.anthropic.com/v1/organizations/usage_report/messages`, `…/cost_report`. Headers `x-api-key`, `anthropic-version: 2023-06-01`.

## openai-platform (API usage/cost) — secondary
- **Capabilities:** `dollarBalance` (cost), usage. NOT remaining credit balance (legacy `credit_grants` returns 401/403 in 2025–2026).
- **Auth:** `.adminApiKey` — `sk-admin-…` (Bearer).
- **Endpoints:** `GET https://api.openai.com/v1/organization/usage/*`, `GET https://api.openai.com/v1/organization/costs`.

## chatgpt-plus (consumer quota) — EXPERIMENTAL, label clearly
- **Capabilities:** at best `resetTimer` when throttled. No reliable continuous %.
- **Auth:** `.sessionCookie` (dashboard).
- **Reality:** OpenAI exposes no clean per-user "remaining messages" counter; only implicit "limit reached / resets at X". Implement as best-effort; show "limited / OK" state, not a fake gauge.

---

## Build order
1. `claude` via `.keychainOAuth` (validate the number against the real account using `houdini`).
2. `claude` `.sessionCookie` fallback (covers users without Claude Code).
3. `openai-platform` + `anthropic-console` admin-API adapters.
4. `chatgpt-plus` experimental.

---

## Provider switcher (app Settings) — design, not yet built

The user picks and configures providers **inside the native app's Settings** — never
on the website (ADR-011). The site presents capability as one honest line and ships
no per-provider key UI.

```
Settings ▸ Providers
  ● Claude            Connected · Claude Code token (Keychain)        [Reconnect]
  ○ OpenAI Platform   Not connected                                  [Connect ▸]
  ○ Anthropic Console Not connected                                  [Connect ▸]
```

- **Registry-driven.** The list is rendered from `ProviderRegistry`; adding a provider
  in `FetcherCore` makes a row appear with no UI rewrite (capability flags drive what
  each row can show — ADR-007).
- **Connect flow per `authMethod`:**
  - `.keychainOAuth` (Claude) — auto-detect the Claude Code token; one tap to reuse it.
  - `.sessionCookie` (Claude fallback / ChatGPT Plus) — native `WKWebView` login; capture
    cookie → Keychain.
  - `.adminApiKey` (OpenAI Platform, Anthropic Console) — a single secure field in
    Settings. The key is written **straight to the macOS Keychain** and read only by
    native code at fetch time.
- **Active provider** drives the menu-bar headline + popover ordering; multiple connected
  providers stack in the popover.

### OpenAI Platform = the planned 2nd provider
- **Connect:** paste an **organization admin key** (`sk-admin-…`) in Settings.
- **Stored:** macOS Keychain only (service-scoped, e.g. `Houdini-openai-admin`).
- **Read:** native `URLSession` → `GET /v1/organization/usage/*`, `…/costs` (Bearer).
- **Shows:** `$` spent this period + token counts (no clean per-user % — ADR-004).

### Hard rule — keys never touch the frontend, site, or repo (ADR-011)
A provider **API/admin key is a secret**. It is entered **only** in the native app's
Settings and stored **only** in the macOS Keychain. It must **never** appear in:
the website or any frontend/JS bundle, browser-shipped env vars, `site/src/config.ts`,
or anywhere in the repo / git history. There is no Houdini server to receive it. The
website therefore shows **no** OpenAI (or other) key field and **no** visible OpenAI
placeholder — only the honest capability line. Code review and release (`RELEASE.md`)
must reject any change that puts a provider secret in web/repo code.
