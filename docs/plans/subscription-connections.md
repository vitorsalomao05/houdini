# Subscription connections — 2026-09-20

## Accepted scope

The owner selected subscription consumption, limits, and quota reset times for Claude and Codex. Connections start from Houdini and may use the provider's official client. Billing, invoices, API spending, and the paused Installation Lifecycle/Release Contract WIPs are outside this change.

The reported Claude sign-in failure occurs inside Houdini's embedded Google sign-in. The owner's screenshot shows “Something went wrong” and a Bluetooth/device-proximity instruction. It proves a failure in the cross-device authentication step, not a `disallowed_useragent` error or a specific root cause. Some attempts reportedly establish a Claude session despite the error. Automated observation timed out at that step; the original Google failure is not yet reproducibly diagnosed.

## Delivery criteria

- A user can choose Claude or Codex (the visible provider names) for the menu bar, popover, and desktop widget. The active subscription is named, and switching never shows the other subscription's cached values.
- Existing Claude OAuth discovery and saved-session fallback remain readable. New connections launch the official Claude Code browser login, without embedding Google's sign-in or capturing new cookies. Houdini does not refresh or log out the user's Claude Code credential.
- A successful login-process exit is followed by credential discovery and a usage fetch; process completion alone is not presented as proof of usage access.
- Codex connections and quota reads use the documented Codex App Server protocol and a Houdini-owned authentication scope. Existing Codex configuration and credentials remain untouched. Persistence uses the system credential store, without fallback to plaintext auth files.
- Only actual quota windows are displayed. Missing percentages/resets remain unavailable, and labels identify Codex limits rather than promising a universal ChatGPT quota.
- Missing official clients have a clear installation link; Houdini does not silently install software. Login can be cancelled and times out safely. Process errors and output never expose credentials, account identifiers, or authentication URLs.
- Tests exercise fake clients and fake credentials, including cancellation, protocol failures, missing quota fields, and switching during a fetch. No test requires real provider authentication.
- Relevant core tests, app build and smoke checks run with observed results; interface checks cover keyboard access, focus, contrast and both providers. Live Google login remains separately identified if external interaction cannot be verified.

## Sources and existing decisions

Official sources: [Codex App Server](https://learn.chatgpt.com/docs/app-server), [Codex authentication](https://learn.chatgpt.com/docs/auth), [versioned Codex credential storage](https://github.com/openai/codex/blob/rust-v0.150.1/codex-rs/login/src/auth/storage.rs), [Claude CLI reference](https://code.claude.com/docs/en/cli-reference), and [Google passkeys](https://support.google.com/accounts/answer/13548313). ADR-004/011/012 must record the accepted subscription priority and the bounded official-client connection flow; this does not authorize direct OAuth refresh, new cookie capture, API billing features, or a Houdini backend.

The old issue #5 is still a proposal awaiting retriage. Its full authenticated-use gate is not implicitly adopted by this scope. This document records the owner's current answers and the local implementation boundary; no issue or release has been published.
