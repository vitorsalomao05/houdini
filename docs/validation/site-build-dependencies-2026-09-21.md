# Site build dependency validation — 2026-09-21

## Scope

Base: `d845e3bbb9f1b5fad9214dc24343350db02aea64` (`origin/master` after fetch).
Implementation uses branch `codex/maintain-site-build-dependencies` in a new worktree.
The original `feat/release-contract-3` index, working tree and untracked files were
fingerprinted before work. The previous production-audit worktree is unchanged.
Native release v1.1.0, its source/assets, installer and site version pins are preserved.

The [research record](site-build-dependencies-research-2026-09-21.md) contains the
primary sources, correction floors and migration analysis. No forced audit fix or
transitive override was used. Astro's supported dependency range supplies Sharp.
`compressHTML: true` preserves the earlier inline whitespace rules. Tailwind stays
at 4.3.1; site components, content, images and styles are unchanged.

## Resolved dependencies

| Package | Baseline | Updated lockfile |
| --- | --- | --- |
| Astro | 5.18.2 | 7.3.3 |
| Sharp | 0.34.5 | 0.35.4 |
| devalue | 5.8.1 | 5.9.4 |
| esbuild (Astro) | 0.27.7 | 0.28.2 |
| js-yaml | 4.2.0 | 4.3.2 |
| nanoid | 3.3.12 | 3.3.19 |
| postcss | 8.5.15 | 8.5.28 |
| smol-toml | 1.6.1 | 1.8.0 |
| svgo | 4.0.1 | 4.1.0 |
| @astrojs/sitemap | 3.7.3 | 3.7.4 |

Astro's Vite 6 dependency is replaced by the already-present Vite 8.0.16 line.
Node >=22.12 is declared in `site/package.json`; CI now builds on Node 22 and 24
and fails on any reported npm vulnerability (`npm audit --audit-level=low`).

## Executed local checks

Official macOS arm64 Node archives were downloaded to temporary directories and
verified against their SHA-256 manifests. No globally installed runtime changed.

```text
Baseline npm audit --package-lock-only:
9 affected packages: 1 critical, 6 high, 1 moderate, 1 low

Updated npm audit --package-lock-only:
0 vulnerabilities (321 dependencies including optional platform packages)

Node 22.23.2: npm ci --no-audit --no-fund && npm run build
8 pages built; all 8 responsive WebP images generated without the old cache
python3 -m unittest discover -s tests -p test_verify_site.py
Ran 3 tests ... OK

Node 24.21.0: npm ci --no-audit --no-fund && npm run build
8 pages built; all 8 responsive WebP images generated without the old cache
python3 -m unittest discover -s tests -p test_verify_site.py
Ran 3 tests ... OK

Sharp runtime: sharp 0.35.4 / libvips 8.18.6 / libheif 1.23.2
8 WebP files decoded successfully

git diff --check: clean
bash -n scripts/init.sh: passed
```

The popover variants decode at 320×305, 360×343, 380×362 and 640×610;
widget variants at 400×153, 700×268, 1000×383 and 1296×496. The popover source
is 640×610; the image service caps the larger requested width at source resolution.
Aspect ratios and desktop/mobile rendering were checked.

The raw `astro preview` HTTP run reports **75/76**, solely because `/404` is served
as HTTP 200. A differential check using Astro 5.18.2 on the saved baseline build
and Astro 7.3.3 on the candidate returned the same result: `/404` is 200 with the
branded page, and an unknown path is 404 with that page. This is preview-server
behavior; the production gate is unchanged and must pass 76/76 on Vercel.
The three integration tests verify the generated build with the hosting 404 rules
and reject an empty deployment or the homepage substituted for `/install`.

## Browser verification

Compared production Astro 5.18.2 with local Astro 7.3.3 at 1440×1000 and 390×844:
all seven routes retain identical normalized visible main text, one H1 per page
and no horizontal overflow. Desktop homepage, mobile installer and desktop-widget
screenshots were inspected; the layout, typography and product images are preserved.

- Home → guided install through ClientRouter retains `html.js` and visible controls.
- Four install steps, Next/Back limits, both subscription choices and restored Codex
  choice passed. Copy reads back the exact `v1.1.0/install.sh` command.
- Enter activates Back; arrow/Home/End keys operate tabs; focus outlines are 2 px.
- Guide progresses through all nine cards and decodes its product image.
- FAQ Enter opens the chosen question and closes the previous one.
- Browser Back from the guide restores `/install#widget`, step 3 and `html.js`
  after the route swap completes. Sampling just after URL changes can precede the
  asynchronous DOM swap; the final rendered state was checked separately.
- With JavaScript disabled, all four installer cards and all nine guide cards
  remain visible, the enhanced Next controls are hidden, and version pins remain.
- axe-core 4.13.0 reported zero WCAG 2/2.1 A/AA violations on the seven initial
  pages at both widths. Its color-contrast result includes incomplete checks on
  gradients; screenshots and visible focus were also inspected. This is scoped
  automated and manual verification, not a claim of complete WCAG certification.

## Delivery

Independent review, hosted CI and production publication are pending at this
record's initial commit. Production must be checked after the final Git-triggered
deployment, including any later documentation commit.
