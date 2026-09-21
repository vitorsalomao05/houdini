# scripts/

Developer and deployment verification tools:

- **`init.sh`** — verifies the toolchain (Swift for `core/` + `apps/menubar`, Node/npm for
  `site/`), prints the repo map, the real per-area build/test/run commands, and the current
  top `BACKLOG.md` item. Safe to re-run; never reads, prints, or caches any credential.

- **`verify_site.py`** — checks the public site over HTTP: routes, branded 404s,
  current version and install pointers, product images, CSS/JavaScript, robots and
  sitemaps. Run `python3 scripts/verify_site.py` after production deployment, or
  pass `--origin https://example.com` for an accessible candidate. It exits nonzero
  on any mismatch and makes no authenticated or provider requests. After building
  the site, run its HTTP regression suite with
  `python3 -m unittest discover -s tests -p test_verify_site.py`; CI runs the same
  suite against the generated pages.

Release responsibilities:

- **Publishing** is `.github/workflows/release.yml` — the sole publisher, triggered by a
  `vX.Y.Z` tag push and driven by the checklist in [`../RELEASE.md`](../RELEASE.md).
- **The installer** is the repo-root [`../install.sh`](../install.sh) (SHA-256-verified,
  no `sudo` — changes to it are gated).
- **Signing** is ad-hoc at build time (`apps/menubar/build.sh`); notarization is a deferred
  future option (ADR-006, revised — see `../DECISIONS.md`).
