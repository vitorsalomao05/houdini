# Houdini — see your AI usage and spend, revealed

> A local-first **macOS app** that reveals your AI usage and spend — in your menu bar and on your desktop.
> Repo: [`vitorsalomao05/houdini`](https://github.com/vitorsalomao05/houdini) ·
> Site: **[houdini.salomao.org](https://houdini.salomao.org)** ·
> Target: **macOS 14+ / Apple Silicon**.

Houdini tracks **Claude (Pro/Max) and Codex** subscription consumption, limits,
and quota resets on macOS. Choose one subscription for the menu bar, popover,
and desktop widget, refreshed **every 60 seconds by default**. Claude also
shows extra-usage spend when reported. Start connection in Houdini; the official
Claude Code or Codex client handles browser sign-in. No Houdini account or server.

<p align="center">
  <img src="docs/popover.png" width="440"
    alt="The Houdini menu-bar popover: a 5-hour session window at 32% and the weekly limit at 95%, each a color-coded ring gauge with its reset timer; a Sonnet weekly bar at 61%; and extra-usage spend at $93.00 of $100.00. Sample data." />
</p>

## Install (macOS 14+, Apple Silicon)

```sh
curl -fsSL https://raw.githubusercontent.com/vitorsalomao05/houdini/v1.1.0/install.sh | bash
```

Downloads the ad-hoc-signed `Houdini.app` + the `houdini` CLI from the pinned
[`v1.1.0` release](https://github.com/vitorsalomao05/houdini/releases/tag/v1.1.0),
**verifies their SHA-256** against `SHASUMS256.txt`, then installs without `sudo`
(app → `~/Applications`, CLI → `~/.local/bin`) — with no Gatekeeper prompt. It
offers (never forces) launch at login, and is safe to re-run. The desktop widget
ships inside the app (toggle it in Settings) — no separate install. Read it
first — it's at [`install.sh`](install.sh).

In Settings, choose **Claude** or **Codex** and connect. Claude uses an existing
Claude Code credential or starts `claude auth login --claudeai`; that sign-in
updates your Claude Code session. Codex requires the official **Codex CLI
0.150.x** and uses a separate Houdini session managed by that client in Keychain,
leaving your normal Codex login and configuration unchanged. Missing clients
and unsupported versions have setup guidance in the app. The shipped `houdini`
CLI continues to expose its existing providers; Codex selection is in the macOS app.

Houdini is **one app** with two co-equal, user-facing features (the website brands
neither separately — see ADR-010/011):

1. **Menu bar** — your tightest limit, always visible; popover with every window. True 60s refresh.
2. **Desktop widget** — the same gauges on your wallpaper, as a draggable, resizable glass panel.
   **Native to the app** (SwiftUI in an `NSPanel`) — toggle it in Settings, no separate install. True 60s refresh.

A glanceable **Notification Center widget** (WidgetKit) is a *deferred* future surface — never
built, and hard-blocked under the current distribution (ADR-013); Apple would cap its refresh
at ~15 min anyway (ADR-002), so it is not advertised on the site.

## Update

Keep Houdini current with the built-in updater. `houdini update` re-runs the same
verified, SHA-256-checked `install.sh` path (no `sudo`, no Gatekeeper prompt,
launch-at-login left exactly as you set it), then reports the new version:

```sh
houdini update            # update to the latest release
houdini update --check    # dry-run: show installed vs. latest, change nothing
houdini update 1.1.0      # install a specific release (incl. rollback to an older one)
```

It updates only what it installed — `~/Applications/Houdini.app` and
`~/.local/bin/houdini` — reads no credential, and rolls back to your current version if
anything fails. If Houdini is running, quit and relaunch it (menu bar ▸ Quit) to load the
new version.

## The core idea (read this first)

Houdini reads structured usage data rather than scraping a browser. Claude uses
an existing local credential with the private usage endpoints; previously saved
Claude.ai cookies remain a fallback. New Claude connections go through Claude
Code's browser login, with no embedded Google sign-in or new cookie capture.
The endpoints remain undocumented, and Anthropic's restrictions on third-party
subscription OAuth remain a risk (ADR-012).

Codex exposes account and quota methods through its official App Server. The
official client owns tokens, persistence, and refresh; Houdini reads the returned
quota windows. It does not infer missing windows, token counts, API costs, or a
universal ChatGPT allowance.

## Providers

| Provider | Source | Method | Status |
|---|---|---|---|
| **Claude (Pro/Max)** | `api.anthropic.com/api/oauth/usage` (Claude Code OAuth token in Keychain) **or** `claude.ai/api/organizations/{org}/usage` (session cookie) | JSON | **Live** |
| **Codex** | Official Codex App Server account and rate-limit methods | JSON-RPC over local stdio | **Live in macOS app** |
| **OpenAI Platform** (API usage/cost) | `/v1/organization/usage/*`, `/v1/organization/costs` | JSON (admin key) | Planned |
| **Anthropic Console** (API usage/cost) | Admin API `usage_report` / `cost_report` | JSON (admin key) | Planned |

See [`PROVIDERS.md`](PROVIDERS.md) for the adapter contract and per-provider specs, [`ARCHITECTURE.md`](ARCHITECTURE.md) for the system design, [`DECISIONS.md`](DECISIONS.md) for the ADRs, and [`ROADMAP.md`](ROADMAP.md) for the phased plan.

## Repo layout

```
houdini/
├── README.md            ← this file
├── ARCHITECTURE.md      ← system design + diagram
├── DECISIONS.md         ← ADRs (why menu bar, why no 60s widget, the rebrand…)
├── PROVIDERS.md         ← provider-adapter contract + per-provider specs
├── ROADMAP.md           ← phased plan
├── RELEASE.md           ← release checklist + per-release go-live records
├── CLAUDE.md            ← operating guide for Claude Code (how we work here)
├── CONTEXT.md           ← product context (why) — pairs with BACKLOG.md (what's next)
├── BACKLOG.md           ← prioritized work queue
├── core/                ← FetcherCore Swift package (shared data layer) + `houdini` CLI
├── apps/
│   ├── menubar/         ← SwiftUI menu bar app + native desktop widget (flagship)
│   └── ios/             ← native iOS app + widget scaffold (cookie auth; not yet built — ADR-008)
├── site/                ← Astro + Tailwind landing page (deploys via Vercel)
├── install.sh           ← one-liner installer (verified download from Releases)
├── scripts/             ← developer bootstrap (`init.sh`) — release CI lives in .github/workflows/
├── conductor/           ← Build Conductor artifacts (tracked audits; local-only prompts)
└── audit/               ← v1 audit corpus (charter, diagnosis, plan)
```

New here? Run [`scripts/init.sh`](scripts/init.sh) to verify your toolchain and print the
repo map, the real build/test/run commands, and the current top backlog item.

## Privacy posture

Authentication goes directly to each provider; there is no Houdini server.
Houdini reads an existing Claude credential locally without refreshing or rewriting
it. The official Codex client stores Houdini's separate session in Keychain;
Houdini never reads Codex token contents. Tokens and authentication URLs are not
logged. See [`PROVIDERS.md`](PROVIDERS.md) for storage boundaries and the site's
[privacy page](https://houdini.salomao.org/privacy) for the Claude integration's
remaining restrictions.

## Uninstall

Quit Houdini (menu bar ▸ Quit). If you connected Codex, first ask its official
client to remove only Houdini's separate session; skip this command otherwise:

```sh
CODEX_HOME="$HOME/Library/Application Support/Houdini/Codex" codex logout -c 'cli_auth_credentials_store="keyring"'
```

Then remove the installed files and local preferences:

```sh
# If you enabled launch-at-login, unregister it first:
"$HOME/Applications/Houdini.app/Contents/MacOS/Houdini" --unregister-login-item

# Remove the app and the CLI:
rm -rf "$HOME/Applications/Houdini.app"
rm -f  "$HOME/.local/bin/houdini"

# Remove Houdini's saved preferences:
defaults delete org.salomao.houdini 2>/dev/null || true

# Remove the claude.ai session Houdini stored (only exists if you used the
# cookie sign-in). The Claude Code OAuth token is Claude Code's own — left alone:
security delete-generic-password -s Houdini-claude-session 2>/dev/null || true

# After Codex logout, remove Houdini's isolated client state:
rm -rf "$HOME/Library/Application Support/Houdini/Codex"
```

These removal steps preserve your Claude Code credential
(`Claude Code-credentials`), `~/.claude/`, and your usual `~/.codex` login and
configuration. Initiating a Claude connection earlier may have updated the
Claude Code session through that official client.

## License

Free and open source under the [MIT License](LICENSE).
