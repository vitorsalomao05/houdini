# Security Policy

Houdini is a **local-first macOS app**: there is no Houdini server. Authentication
goes directly to the provider. Houdini discovers existing Claude credentials
locally; the official Codex client owns a separate Houdini session stored in
Keychain. New sign-ins run through the official clients, with no embedded Google
login or new Claude cookie capture. Tokens are not logged. See the [privacy posture](README.md#privacy-posture)
in the README and [ARCHITECTURE.md](ARCHITECTURE.md) for the full trust model.

## Supported versions

Houdini advertises a **single production version** at a time (ADR-010): the latest
release is the only supported one. Superseded releases are kept and downloadable
for rollback, but are clearly retitled "superseded — do not install" and receive
no security fixes. Update to the latest before reporting.

| Version | Supported |
|---|---|
| Latest release (currently `v1.1.0`) | ✅ |
| Older / superseded releases | ❌ |

## Reporting a vulnerability

**Please report security issues privately — do not open a public issue.**

Use GitHub **Private Vulnerability Reporting**:

1. Go to the repository's **Security** tab → **Report a vulnerability**
   (or open <https://github.com/vitorsalomao05/houdini/security/advisories/new>).
2. Describe the issue, the affected version (`houdini --version`), and clear steps
   to reproduce.

You'll get an acknowledgement, and — once a fix ships in a new release — public
credit in the advisory unless you'd rather stay anonymous. Because Houdini keeps
no server and no telemetry, private reports are the primary way issues reach us.

## Scope

In scope: credential handling (Keychain read paths, official-client process and
browser boundaries, Codex session isolation, existing Claude OAuth/cookie reads), the
network layer (the pinned request session, redirect handling), installer integrity
(`install.sh` SHA-256 verification), and `houdini update`. Out of scope: issues in
a provider's own service (report those to the provider) and physical/social-
engineering access to your local machine.
