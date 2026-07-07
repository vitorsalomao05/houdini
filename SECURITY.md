# Security Policy

Houdini is a **local-first macOS app**: there is no Houdini server, and your
provider credentials (the Claude Code OAuth token or a claude.ai session cookie)
never leave your Mac — they stay in the macOS Keychain and are read on-device to
call each provider's own endpoint. See the [privacy posture](README.md#privacy-posture)
in the README and [ARCHITECTURE.md](ARCHITECTURE.md) for the full trust model.

## Supported versions

Houdini advertises a **single production version** at a time (ADR-010): the latest
release is the only supported one. Superseded releases are kept and downloadable
for rollback, but are clearly retitled "superseded — do not install" and receive
no security fixes. Update to the latest before reporting.

| Version | Supported |
|---|---|
| Latest release (currently `v0.4.0`) | ✅ |
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

In scope: credential handling (Keychain read paths, OAuth/cookie flows), the
network layer (the pinned request session, redirect handling), installer integrity
(`install.sh` SHA-256 verification), and `houdini update`. Out of scope: issues in
a provider's own service (report those to the provider) and physical/social-
engineering access to your local machine.
