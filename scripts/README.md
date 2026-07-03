# scripts/

Developer bootstrap only:

- **`init.sh`** — verifies the toolchain (Swift for `core/` + `apps/menubar`, Node/npm for
  `site/`), prints the repo map, the real per-area build/test/run commands, and the current
  top `BACKLOG.md` item. Safe to re-run; never reads, prints, or caches any credential.

Nothing release-related lives here:

- **Publishing** is `.github/workflows/release.yml` — the sole publisher, triggered by a
  `vX.Y.Z` tag push and driven by the checklist in [`../RELEASE.md`](../RELEASE.md).
- **The installer** is the repo-root [`../install.sh`](../install.sh) (SHA-256-verified,
  no `sudo` — changes to it are gated).
- **Signing** is ad-hoc at build time (`apps/menubar/build.sh`); notarization is a deferred
  future option (ADR-006, revised — see `../DECISIONS.md`).
