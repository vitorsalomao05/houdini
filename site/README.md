# Houdini — landing site

Static site for Houdini. **Astro + Tailwind CSS v4**, dark "stage" identity (velvet
surfaces, violet→magenta spotlight, a gold reveal spark). Builds to `dist/`, deployed
to **Vercel** at **[houdini.salomao.org](https://houdini.salomao.org)**.

Houdini is the only brand on the site. "Menu bar" and "Desktop widget" are co-equal
**features** of the one app — never separate products, sections, or logos.

## Develop

Use Node **22.12+** (Node **24** recommended, matching Vercel). CI builds and
checks the locked dependencies on both Node 22 and 24.

```sh
cd site
npm ci
npm run dev      # local dev server (http://localhost:4321)
npm run build    # static build → dist/
npm run preview  # serve the built dist/ locally
```

## Structure

- `src/pages/index.astro` — the home page (composed from section components).
- `src/pages/install.astro` — the dedicated three-step install flow.
- `src/pages/guide.astro` — the didactic walkthrough.
- `src/components/*.astro` — one component per home section (Hero, Reveals, Surfaces, …).
- `src/styles/global.css` — design tokens (`@theme`) + base + motion utilities.
- `src/config.ts` — **all external URLs, the version pin, and the page content model in
  one place.** A release bump or copy tweak is a one-file edit.
- `src/assets/` — real product screenshots (optimized to webp at build).

## Notes

- Accessible by design: WCAG AA contrast, visible keyboard focus, `prefers-reduced-motion`
  respected, on-scroll reveals gated behind `html.js` so the page is fully visible without JS.
- Honest copy: no fabricated social proof, and **no "coming soon" placeholders** — a surface
  is real and shown, or absent (ADR-010). Capability is one honest line: Claude and
  Codex subscription usage, limits, and resets. Codex is not a universal ChatGPT quota.
- No provider API/admin key ever lives in this site or the repo — keys belong only in the
  app's macOS Keychain (ADR-011).
- Deploy: **Vercel**, project `houdini` — project Root Directory **`site`**,
  framework **Astro**, install **`npm ci`**, build **`npm run build`**, output **`dist`**.
  The build settings are also pinned in `site/vercel.json`; Root Directory must be
  configured on the Vercel project. Git pushes to `master` publish production.
  Run CLI deployments from the **repository root**, because Vercel applies the
  configured `site` directory: `vercel pull --yes --environment=production`,
  `vercel build --prod`, then `vercel deploy --prebuilt --prod`.
  Verify with `python3 scripts/verify_site.py` from the repository root; a Ready
  deployment alone does not prove that public routes work.
- OG card: `node scripts/og/build.mjs` regenerates `public/og.png` (1200×630, rendered
  with headless Chrome from an inlined HTML template).
