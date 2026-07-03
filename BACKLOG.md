# BACKLOG.md — Houdini

> Prioritized work for the Houdini monorepo. Pairs with [`CONTEXT.md`](CONTEXT.md) (why)
> and [`CLAUDE.md`](CLAUDE.md) (how we work). Framed 2026-06-30.
>
> **Legend:** `P1` now · `P2` next · `P3` later/ongoing · `[ ]` open · `[~]` in progress
> · `[x]` done. Priorities are **app-first**: login → polish → site + ongoing.

---

## P1 · App — Login / credential refactor  `[~]`

> **⚠ ToS note — decided 2026-07-01 (see ADR-012).** Houdini's Claude auth (Claude Code OAuth token + claude.ai cookie) is prohibited third-party use under Anthropic's Consumer Terms; enforcement is active (account bans land on the *user's* own account). **Decision:** keep it **read-only** using the user's existing credential; **freeze** expansion (no refresh / PKCE / cookie-hardening); do not seek permission; do not pivot now (options i/iv are the future fallback). This **caps P1 at slice (a)** — a user with no Claude Code credential at all is out of scope by decision. A short user-facing transparency line is recommended but optional (deferred).

**Problem.** The Claude provider connects cleanly for **Claude Code CLI users** (OAuth
token in Keychain) but is **buggy/unclean for non-CLI users**, who have no smooth way to
connect their account.

**Goal.** A simple, reliable, secure login that works for **any** Claude Code user,
regardless of how they authenticate — without weakening the Keychain-only, no-server
security posture.

**Acceptance.**
- A non-CLI Claude user can connect in an obvious, documented way and see live data.
- Existing CLI-token users are unaffected (no regression).
- No credential ever leaves the device, hits disk, or lands in logs.
- The flow is least-privilege and passes a security review.

**Discovery-first sub-tasks.**
- [x] Map every credential source the app reads today — **done (FRAME survey).** Two sources:
      (1) OAuth token from Keychain `service="Claude Code-credentials"` (read via the `security`
      CLI in `CredentialStore.cliReadGenericPassword`) → `api.anthropic.com/api/oauth/usage`;
      (2) claude.ai `sessionKey` cookie in Houdini's own Keychain item `Houdini-claude-session`,
      captured by the WebView login → `claude.ai/api/organizations/{org}/usage`. Resolver picks
      OAuth → cookie → none (`ClaudeAuth.swift:63-79`). The CLI (`houdini`) uses OAuth only, no
      cookie fallback.
- [x] Reproduce and pinpoint the **exact** non-CLI failure — **done (FRAME survey).**
      - **Root cause A (dominant):** OAuth discovery is hardcoded to the single Keychain item
        `"Claude Code-credentials"` (`ClaudeOAuthProvider.swift:45`, consumed at `ClaudeAuth.swift:37`
        & `ClaudeOAuthProvider.swift:105`) — no alternate item names (the code even *notes* a classic
        `"Claude Code"` item but never queries it), no `~/.claude/.credentials.json` file fallback,
        no `refreshToken` use. Non-CLI users lack that exact item ⇒ OAuth is impossible by
        construction ⇒ they're forced onto the cookie path.
      - **Root cause B:** the cookie WebView uses an **ephemeral** store
        (`ClaudeLoginWindow.swift:40`) so it can't reuse the user's existing claude.ai browser
        session; the captured cookie is short-lived and **non-refreshable** → re-login loop on expiry.
      - **Root cause C:** even real CLI users silently lose OAuth when the access token expires
        (`expiresAt` past → unusable; `refreshToken` never used).
- [~] Design the unified login — **(a) IMPLEMENTED this pass; (c) remains the durable follow-on:**
      - **(a) Broaden OAuth/token discovery** — ordered item list (`"Claude Code-credentials"` +
        `"Claude Code"`), `~/.claude/.credentials.json` read fallback, use `refreshToken` to refresh
        a stale access token. *No ADR change; low risk; fixes A+C but not true non-CLI users.*
        **✅ IMPLEMENTED (P1 slice a)** behind one shared `ClaudeOAuthCredentialSource` seam
        (ordered Keychain discovery + read-only file fallback + in-memory `refreshToken` refresh).
        The refresh mechanism is built + tested via an injected refresher; the live refresh
        **endpoint stays unwired — FROZEN by ADR-012** (the `refresher` stays `nil`), so an
        expired token degrades exactly as today **by decision**, not merely pending sign-off.
      - **(b) Harden the claude.ai cookie flow** — persistent/shared WebView store or paste-session,
        proactive expiry re-auth. *Weaker (needs ADR-005 revision); interim bridge only.*
        **FROZEN (ADR-012) — not pursued.**
      - **(c) First-run OAuth PKCE "Connect"** — Houdini gets its own refreshable, revocable,
        Keychain-only Anthropic token, independent of the CLI. *Durable; higher effort; depends on a
        usable public OAuth client.* **FROZEN (ADR-012) — not pursued.**
      - **Decision (ADR-012, 2026-07-01):** slice **(a)** shipped is the **cap** for P1 — keep the
        Claude integration read-only on the user's existing credential and **freeze** expansion.
        **(b)** cookie-hardening and **(c)** OAuth PKCE are **not pursued** (they'd escalate the
        signal that Houdini's traffic mimics the Claude Code client), and token refresh stays off.
        A true non-CLI user with **no** Claude Code credential anywhere is **out of scope by
        decision**. Options (i)/(iv) (Anthropic Admin Usage & Cost API / lead with API-key
        providers) are retained as the future fallback if enforcement tightens.
- [~] Implement behind a clean, testable seam in `core/` (the `CredentialStore` /
      `ClaudeAuthResolver` boundary already isolates this well). **slice (a): ordered Keychain
      discovery + `~/.claude/.credentials.json` fallback + in-memory `refreshToken` refresh**,
      all in one `ClaudeOAuthCredentialSource` unit (collapsed the two old private blob structs
      + two read call-sites). Live refresh endpoint **frozen (ADR-012)**; cookie hardening (b)
      and OAuth PKCE (c) are frozen too — **P1 is capped at slice (a).**
- [~] Test both user types end to end; add regression tests (extend `FetcherCoreTests`).
      **slice (a): added `ClaudeAuthResolverTests` (ordered discovery, first-item-wins, file
      fallback, refresh, absent) + a `houdini-selftest` mirror (29 checks PASS here).** Still
      open: end-to-end coverage for the non-CLI **cookie** user (part of (b)/(c)).
- [~] Update `PROVIDERS.md` / relevant ADR — **ADR-012 decided** (read-only + frozen); `PROVIDERS.md`
      gets a one-line ToS-stance note this pass. A full security review is only needed if refresh /
      PKCE is ever unfrozen — **out of scope now by decision.**

## P2 · App — Widget accessibility + visual polish  `[~]`

**Goal.** The menu bar and desktop widget are accessible and visually polished end to end.

**Acceptance.**
- Keyboard + VoiceOver usable; clear, legible gauges and reset timers.
- Consistent visual language across menu bar popover and desktop panel.
- No rough edges (alignment, spacing, states, empty/error/loading).

**Sub-tasks.**
- [x] Accessibility pass (labels, focus, Dynamic Type, contrast, reduced-motion). *(P2 slice 1 — **DONE, commit `19d3ed0`:** VoiceOver labels/values on gauges·rows·spend·status·footer, keyboard focus ring on footer buttons, `@ScaledMetric` Dynamic Type, AA contrast lift + Increase-Contrast now raises text; reduced-motion already gated.)*
- [x] Visual polish pass on both surfaces; define shared visual tokens. *(P2 slice 2 — **DONE:** one shared `Theme` token layer — colors · spacing · radii · type · motion — consumed by both the popover and desktop widget; deduped the `#8B5CF6` brand hex, pulled the glass wash/border/ink hexes into one place, unified the popover card radius into the widget's rounded-card family (14→20), unified the gauge/progress tracks + the two state-view rhythms + micro-label tracking + hover/value motion. Slice-1 a11y values (Dynamic Type, AA secondary tone, Increase-Contrast lifts, focus ring) folded into tokens intact; verified via adversarial review.)*
- [ ] Verify against real Claude Pro/Max data (limits, timers, overage). *(Slice 3 — remains.)*

## P3 · Site — Polish to zero-clutter + ongoing features  `[~]`

**Goal.** A 100% clean site (zero visual clutter/pollution), strongly accessible, with one
clear install CTA — then a continuous stream of features and ideas.

**Audit:** DONE 2026-07-01 (live Claude-in-Chrome visual + a11y pass; full report at
`conductor/audits/2026-07-01-site-audit.md`). The site was already calm/low-clutter and mostly
WCAG-AA clean; concrete gaps captured below.

**Sub-tasks.**
- [x] Run the Claude-in-Chrome visual + a11y audit; fold findings in. **Done** — report in
      `conductor/audits/`.
- [x] Ship the four ToS-independent quick-wins **(commit `78e2bf3`):** product screenshot now
      shows on mobile; curl one-liner made fully readable; footer + terminal-label contrast lifted
      to **AA**; decorative hat SVGs confirmed `aria-hidden`.
- [x] Hero H1 — **decided: KEEP GENERIC** ("AI usage", per ADR-012's low-profile posture); the
      audit's "sharpen toward Claude/menu-bar" is ToS-gated and intentionally **not** actioned
      (no change for now).
- [x] Explicit "Mac → Anthropic, no Houdini server" trust line — **decided: DEFERRED** (optional
      per ADR-012; owner may adopt anytime). No change for now.
- [ ] Ongoing site polish + feature/idea stream (tracked in the Parking lot below).

## P4 · App — Self-update / clean-upgrade command (`houdini update`)  `[ ]`

*Captured 2026-07-01 — future wave, not scheduled yet (comes after P1–P3).*

**Goal.** One command (`houdini update`) that upgrades an installed Houdini to the latest
release, removes leftover files from any previous version in production, installs the new
version, and reports the new version to the user.

**Requirements.**
- Update to the **latest** release via the same pinned-tag, **SHA-256-verified** path as
  `install.sh` — don't weaken installer integrity (no `sudo`, no Gatekeeper prompt, no forced
  launch-at-login).
- **Clean up old-version artifacts** in production before/after install: stale `Houdini.app`
  (`~/Applications`), old `houdini` CLI (`~/.local/bin`), and anything else a prior version
  left behind — scoped to a defined owned-file manifest; never touch user data or Keychain
  credentials.
- Install the new version, then **display it** on completion (CLI output + the app/menu-bar
  "About"/version — a clear "you're now on vX.Y.Z").

**Notes / open questions.**
- Respect **ADR-010** (single advertised version; installer re-fetched from the current tag)
  and **ADR-006** (ad-hoc via `install.sh` is the shipping path) — likely a thin wrapper over
  the verified `install.sh` re-run plus an explicit old-version cleanup step. Sparkle stays a
  separate future option.
- Decide the surface: CLI subcommand vs. menu-bar "Check for updates" vs. both.
- Needs a definitive **owned-file manifest** so cleanup is exhaustive but safe (least-privilege).

---

## Cross-cutting

- [ ] **Security & trust:** keep the trust/privacy messaging accurate; review any future
      elevated permission (e.g. browser-scrape fallback) before it ships.
- [ ] **Accessibility baseline:** WCAG 2.1 AA across site and app UI; no regressions.
- [ ] **Installer integrity:** preserve SHA-256 verification, no-`sudo`, no-Gatekeeper,
      no forced launch-at-login as `install.sh` evolves.

## Discovery / open questions — resolved by the FRAME survey (2026-07-01)

- [x] Cleanest unified-login design — **DECIDED in ADR-012** (2026-07-01): keep Claude read-only
      on the user's existing credential and freeze expansion; **P1 capped at slice (a)**, already
      shipped. (The "user with no Claude Code credential at all" case is out of scope by decision.)
- [x] Site deploy target + CI — **Vercel**, project `houdini`, manual prebuilt CLI (`vercel --prod`
      from `site/`); **no site CI** in `.github/workflows/`. `ROADMAP.md` Phase 7 ("Cloudflare Pages")
      is stale and should be corrected.
- [x] Test coverage/setup — `core/` has swift-testing (`FetcherCoreTests`) + a `houdini-selftest`
      runnable mirror; **no tests** in `apps/*` or `site/`.
- [x] Init script / `feature_list.json` — neither existed; both created 2026-07-01.
      `scripts/init.sh` remains; `feature_list.json` was **deleted 2026-07-03** (v1 audit
      DOC-09/ORG-05 — no generator, no consumer).

### Newly surfaced (flag for the user)

- [x] **ADR-006 vs reality — RESOLVED 2026-07-01:** ADR-006 revised in place to record that the
      ad-hoc-signed `install.sh`/`curl|bash` path is the shipping reality (notarized DMG deferred).
- [x] **ROADMAP.md refresh — RESOLVED 2026-07-01:** Phase 7 corrected to Vercel, the
      ADR-010/011-forbidden "providers grid" dropped, and stale ✅ / "← WE ARE HERE" markers
      updated now that v0.4.0 is live.
- [ ] **Gemini gap (still open):** advertised in `README.md`/`CONTEXT.md` but absent from
      `PROVIDERS.md`/`ROADMAP.md` — spec it or drop the claim.
- [x] **README/CLAUDE repo-layout — done:** `apps/ios/` added to the layout maps (`CLAUDE.md` +
      README); `apps/widget/` documented as a README-only placeholder, not a built target.

## Immediate next steps

*Framing + scope sign-off are long done. The login decision (**ADR-012**), the site audit +
its ToS-independent quick-wins (commit `78e2bf3`), and the P2 accessibility slice (commit
`19d3ed0`) have all shipped. Current focus:*

1. [~] **P2 slice 2** — visual polish + shared visual tokens across the menu bar and desktop widget.
2. [ ] **P2 slice 3** — verify gauges / reset timers / overage against real Claude Pro/Max data.
3. [ ] **P3 ongoing** — continue site polish + the feature/idea stream (Parking lot); the Gemini
       provider claim still needs to be specced or dropped (see flags above).

## Parking lot / ideas (ongoing)

- _(Add feature ideas here as they come up — the site is an evolving surface.)_
