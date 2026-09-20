# Provider adapters

Every usage source implements one protocol. Usage rendering reads capability flags and
the metrics returned; connection flows follow the provider's ownership model.
The accepted subscription changes below are in validation, not a published release.
See [scope and acceptance criteria](docs/plans/subscription-connections.md).

## Contract

```swift
protocol UsageProvider {
    var id: String { get }                       // "claude", "claude-cookie", "chatgpt-codex"
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
    var windowDurationMinutes: Int?
    let providerId: String
}

enum AuthMethod { case keychainOAuth, sessionCookie, adminApiKey }
```

Cross-cutting services in `FetcherCore`: `CredentialStore` (Keychain read/write), `ClaudeOAuthCredentialSource` (ordered discovery; the live refresher remains unwired), `ClaudeUsageParser` (both Claude endpoint dialects), `CredentialRedirectGuard` (strips credential headers on cross-host redirects), and `CodexAppServerClient` (managed account/login/limits protocol). Polling and last-good caching live in the app's `UsageModel`; the `houdini` CLI retains its existing Claude path. The app's subscription selection does not imply a new CLI feature.

Optional percentages, durations, and resets stay optional. A reset timestamp alone does
not establish a five-hour or weekly window. Empty results mean unavailable usage, not
zero consumption. Metrics and in-flight results belong to the selected subscription.

---

## claude (Pro/Max) — existing usage source; official-client connection
- **Capabilities:** `usagePct`, `resetTimer` (+ `dollarBalance` if "Claude Extra" overage).
- **Primary auth:** `.keychainOAuth` — reuse the **Claude Code OAuth token**. Discovery order (`ClaudeOAuthCredentialSource`): Keychain item `Claude Code-credentials` (primary), then the classic `Claude Code` item, then the `~/.claude/.credentials.json` file. Existing sessions need no new login; Houdini does not modify or refresh that credential.
- **New connection:** launch the installed official client's [`claude auth login`](https://code.claude.com/docs/en/cli-reference), using its browser flow. Missing Claude Code produces installation guidance. The action is cancellable and bounded by a timeout. Exit zero triggers credential rediscovery and a usage fetch; a successful process alone does not establish usable quota access. Houdini does not log out Claude Code.
- **Primary endpoint:** `GET https://api.anthropic.com/api/oauth/usage`
  - Headers: `Authorization: Bearer <token>` **and** `User-Agent: claude-code/<version>` (always send it — a missing UA **may cause throttling under sustained use**; the code keeps it for safety).
  - Returns 5-hour / 7-day / Opus-7-day utilization.
- **Saved-session fallback:** `.sessionCookie` — sibling provider `claude-cookie` (`ClaudeCookieProvider`), selected by `ClaudeAuthResolver` when no usable OAuth credential resolves. Previously saved cookies remain readable from `Houdini-claude-session`; new connections no longer capture cookies or embed Google sign-in. The legacy item uses `kSecAttrAccessibleAfterFirstUnlock` (audit SEC-09), readable after the first unlock even while subsequently locked. Existing saved-session preferences remain compatibility state, not a new connection flow. The provider calls:
  - `GET https://claude.ai/api/organizations` → read `org_id`.
  - `GET https://claude.ai/api/organizations/{org_id}/usage` → fields: `five_hour.utilization_pct`, `five_hour.reset_at`, `seven_day.utilization_pct`, `seven_day_opus.utilization_pct`, `extra_usage.current_spending`, `extra_usage.budget_limit`.
- **Fragility / risk:** usage endpoints remain undocumented, and the residual third-party subscription-auth risk accepted in ADR-012 remains. At 60-second polling the OAuth path makes about 1,440 requests/day; the cookie path adds an organization lookup per poll. Launching the official client does not authorize or stabilize these private usage endpoints.
- **Boundary (ADR-012, revised 2026-09-20):** read-only OAuth discovery and saved-cookie access, with official-client connection initiation. No Houdini OAuth refresh, PKCE, new cookie capture, or inference. The documented Claude Code statusline is a separate session-dependent data source, not the source implemented by this slice.
- **Reference:** `github.com/ttar-p/claude-usage-widget`, `github.com/hamed-elfayome/Claude-Usage-Tracker`.

## chatgpt-codex — Codex subscription limits
- **Display name:** `Codex`. The stable provider ID remains `chatgpt-codex`; the official protocol account type remains `chatgpt`.
- **Capabilities:** `usagePct`, `resetTimer`; only the windows actually returned. No billing, invoices, API costs, message-count estimates, or universal ChatGPT quota.
- **Auth ownership:** `CodexUsageProvider` uses `.keychainOAuth` in the current contract, but the official Codex client owns tokens, persistence, and refresh. Houdini uses account methods; it does not read `auth.json` or token contents.
- **Protocol:** [Codex App Server](https://learn.chatgpt.com/docs/app-server) JSON-RPC over stdio, with `initialize` / `initialized`, browser `account/login/start`, login-completion notification, `account/read`, and `account/rateLimits/read`. Missing/unsupported clients and process/protocol failures become safe, actionable errors. Browser login is explicit and cancellable; raw output and authentication URLs do not enter diagnostics.
- **Quota mapping:** prefer `rateLimitsByLimitId` when populated, otherwise `rateLimits`. Preserve bucket names/IDs and primary/secondary windows without duplicating the fallback. `usedPercent` is required for each returned window; `windowDurationMins` and Unix-seconds `resetsAt` may be absent. Missing duration is not assumed to be five hours or a week.
- **Local scope:** use `~/Library/Application Support/Houdini/Codex` (0700) as the canonical `CODEX_HOME` and child working directory. Use an environment allowlist rather than inheriting the developer's Codex/OpenAI variables. Check the home returned by `initialize`. Leave the normal `~/.codex` configuration and login untouched.
- **Persistence:** require `cli_auth_credentials_store="keyring"`; never `auto` or file fallback. In official [`rust-v0.150.1` storage code](https://github.com/openai/codex/blob/rust-v0.150.1/codex-rs/login/src/auth/storage.rs), the service is `Codex Auth` and the account is `cli|` plus the first 16 hexadecimal characters of SHA-256 of canonical `CODEX_HOME`; load/save/delete share that namespace. This establishes the source-level separation, not an observed login/logout or real Keychain round trip.
- **Compatibility evidence:** schema and storage inspected at `codex-cli 0.150.1`; the local implementation accepts `0.150.x`. Revalidate protocol and storage before widening that range. The isolated unauthenticated spike and fake-client tests do not establish live account quotas or persistence behavior; validation results belong in the delivery record.

## anthropic-console (API usage/cost) — deferred, outside current priority
- **Capabilities:** `dollarBalance` (cost), usage tokens. NOT remaining prepaid balance via API.
- **Auth:** `.adminApiKey` — `sk-ant-admin…` (org accounts only; unavailable for individual accounts).
- **Endpoints:** `GET https://api.anthropic.com/v1/organizations/usage_report/messages`, `…/cost_report`. Headers `x-api-key`, `anthropic-version: 2023-06-01`.

## openai-platform (API usage/cost) — deferred, outside current priority
- **Capabilities:** `dollarBalance` (cost), usage. NOT remaining credit balance (legacy `credit_grants` returns 401/403 in 2025–2026).
- **Auth:** `.adminApiKey` — `sk-admin-…` (Bearer).
- **Endpoints:** `GET https://api.openai.com/v1/organization/usage/*`, `GET https://api.openai.com/v1/organization/costs`.

---

## Accepted implementation order
1. Preserve Claude usage reads and replace new embedded sign-in with official Claude Code login.
2. Add Codex account connection and supported quota windows.
3. Select one subscription across the app's surfaces and validate switching and connection failures.

API adapters and the former experimental ChatGPT cookie approach are outside this scope
(ADR-004/011). Work status lives in `BACKLOG.md`.

---

## Subscription selection (app Settings) — current slice, in validation

The user picks and configures providers **inside the native app's Settings** — never
on the website (ADR-011). The site presents capability as one honest line and ships
no per-provider key UI.

```
Settings ▸ Subscription
  Claude | Codex
```

- **Connect:** Claude launches its official client's browser login; Codex
  uses its isolated App Server login. Already-saved Claude cookies remain a fallback.
- **One active subscription** drives the menu-bar headline, popover, and desktop widget.
  Switching clears displayed metrics and rejects stale results from the previous
  selection. Simultaneous provider stacking and the old speculative registry UI are
  outside this slice.
- **Missing client:** show the official installation link. Never install silently or
  substitute API-key billing for subscription quotas.

### Hard rule — keys never touch the frontend, site, or repo (ADR-011)
A provider **API/admin key is a secret**. It is entered **only** in the native app's
Settings and stored **only** in the macOS Keychain. It must **never** appear in:
the website or any frontend/JS bundle, browser-shipped env vars, `site/src/config.ts`,
or anywhere in the repo / git history. There is no Houdini server to receive it. The
website therefore shows **no** OpenAI (or other) key field and **no** visible OpenAI
placeholder — only the honest capability line. Code review and release (`RELEASE.md`)
must reject any change that puts a provider secret in web/repo code.
