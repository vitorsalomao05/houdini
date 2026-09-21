# Site build dependency research — 2026-09-21

Research for the maintenance item in [BACKLOG.md](../../BACKLOG.md), using source
`d845e3bbb9f1b5fad9214dc24343350db02aea64` as the baseline. This records upstream
requirements and migration risks; build, browser, CI and production results must
be recorded separately after execution. The native release remains v1.1.0.

## Recommended dependency line

Use stable **Astro 7.3.3**, with its **Sharp 0.35.4** dependency, and update the
official sitemap integration to **3.7.4**. The npm registry reported these as
the latest stable releases on the research date. Astro 7.3.3 declares
`sharp: ^0.35.4` as an optional dependency and `vite: ^8.0.13`; no Sharp override
is needed to obtain the corrected version. Sources: published manifests for
[Astro](https://registry.npmjs.org/astro/7.3.3),
[Sharp](https://registry.npmjs.org/sharp/0.35.4), and
[sitemap](https://registry.npmjs.org/@astrojs%2fsitemap/3.7.4).

The critical Astro advisory marks versions before 7.2.8 as affected and identifies
7.2.8, requiring Sharp 0.35.4, as the fix. Retaining Astro 5 would therefore leave
the framework inside the published affected range.
[Astro advisory](https://github.com/withastro/astro/security/advisories/GHSA-26w7-cxv4-gfx2).

Sharp's prebuilt 0.35.4 binaries include libheif 1.23.2. The advisory concerns
untrusted image decoding, including possible code execution under certain Linux
conditions. The repository's trusted PNG inputs and static deployment constrain
the current exposure, as documented in the [production review](production-2026-09-21.md),
but do not replace dependency remediation.
[Sharp advisory](https://github.com/lovell/sharp/security/advisories/GHSA-rgj7-g3m4-5g8c).

## Transitive correction floors

The supplied baseline audit identifies nine affected package names. The following
floors cover the reported advisories on the dependency lines used by this build;
they are not a claim that arbitrary future releases are free of vulnerabilities.
Refresh compatible transitive versions and inspect the resolved lockfile in
addition to rerunning the audit.

| Package | Corrected version to resolve | Primary evidence |
| --- | --- | --- |
| Astro | 7.2.8 minimum; select 7.3.3 | [Astro image advisory](https://github.com/withastro/astro/security/advisories/GHSA-26w7-cxv4-gfx2) |
| Sharp | 0.35.4 | [Sharp libheif advisory](https://github.com/lovell/sharp/security/advisories/GHSA-rgj7-g3m4-5g8c) |
| devalue | 5.9.2 | [Maintainer advisory](https://github.com/sveltejs/devalue/security/advisories/GHSA-9rgm-9g3h-6x36) |
| esbuild | 0.28.1 on Astro 7's 0.28 line | [Maintainer advisory](https://github.com/evanw/esbuild/security/advisories/GHSA-g7r4-m6w7-qqqr) |
| js-yaml | 4.3.2 on the 4.x line | [Maintainer advisory](https://github.com/nodeca/js-yaml/security/advisories/GHSA-2883-xcg3-v3hh) |
| nanoid | 3.3.18 on the 3.x line | [Maintainer release](https://github.com/ai/nanoid/releases/tag/3.3.18), [published advisory ranges](https://api.github.com/advisories/GHSA-2v37-7h3g-55p8) |
| postcss | 8.5.23 | [Maintainer advisory](https://github.com/postcss/postcss/security/advisories/GHSA-fxqj-rqcc-2cmp) |
| smol-toml | 1.7.1 | [Maintainer advisory](https://github.com/squirrelchat/smol-toml/security/advisories/GHSA-7w5x-hrqm-74c2) |
| svgo | 4.1.0 on the 4.x line | [Executable-link advisory](https://github.com/svg/svgo/security/advisories/GHSA-w27v-7q3p-w38r), [foreignObject advisory](https://github.com/svg/svgo/security/advisories/GHSA-4vpr-x523-8j87) |

There is an upstream inconsistency for devalue: the affected-range field says
`<5.9.1`, while the same maintainer advisory's patched-version field and description
identify **5.9.2**. Require at least 5.9.2 for this maintenance rather than relying
only on a zero-warning audit of 5.9.1.
[devalue advisory](https://github.com/sveltejs/devalue/security/advisories/GHSA-9rgm-9g3h-6x36).

Astro 7.3.3's published ranges permit the corrective transitive versions above,
but some lower bounds remain older, including `devalue: ^5.8.1`,
`esbuild: ^0.28.0`, `js-yaml: ^4.3.0`, `smol-toml: ^1.6.0`, and `svgo: ^4.0.2`.
Updating the framework alone is not proof that an existing lockfile moved every
affected transitive. [Astro manifest](https://registry.npmjs.org/astro/7.3.3).

## Runtime and integration compatibility

Astro 7.3.3 requires **Node >=22.12.0** and npm >=9.6.5. Sharp 0.35.4 requires
Node >=20.9.0. Both **Node 22 at or above 22.12** and **Node 24** therefore satisfy
the published engine constraints; actual builds on both runtimes remain required.
[Astro manifest](https://registry.npmjs.org/astro/7.3.3),
[Sharp manifest](https://registry.npmjs.org/sharp/0.35.4).

Retain the existing **Tailwind 4.3.1** packages to avoid unrelated stylesheet
changes. The published `@tailwindcss/vite@4.3.1` peer range explicitly includes
Vite 8, and its documented Astro setup is the existing
`vite.plugins: [tailwindcss()]` configuration. No migration to the retired
Tailwind Astro integration is indicated.
[Tailwind plugin manifest](https://registry.npmjs.org/@tailwindcss%2fvite/4.3.1),
[official Astro setup](https://tailwindcss.com/docs/installation/framework-guides/astro).

The sitemap integration's documented contract remains `site` plus
`integrations: [sitemap()]`, matching this static site's configuration. Validate
the emitted sitemap index and route URLs after the integration patch.
[Sitemap documentation](https://docs.astro.build/en/guides/integrations-guide/sitemap/).

Sharp selects platform binaries through optional dependencies. Keep those enabled
and verify clean installation on both the developer Mac and Linux CI; its install
documentation calls out cross-platform npm lockfile pitfalls. A successful Mac
build alone does not validate Linux's image processor.
[Sharp installation](https://sharp.pixelplumbing.com/install/).

## Migration risks mapped to Houdini

The direct 5-to-7 update must account for both major migration guides.

- **Images:** Astro 6 stops upscaling and changes default cropping. In this
  repository, all three `Image` usages import two local PNGs and supply responsive
  widths without an explicit width/height crop. `popover-dark.png` is 640×610;
  the homepage requests widths `[320, 380, 760]`, so the 760 px variant needs
  particular inspection. `desktop-widget.png` is 1296×496 with widths
  `[400, 700, 1000]`. These dimensions were read directly from the PNG headers.
  Preserve aspect ratio and verify the generated `srcset` against actual files.
  [Astro 6 image changes](https://docs.astro.build/en/guides/upgrade-to/v6/#changed-never-upscale-images-in-default-image-service).
- **Client routing:** Houdini already imports `ClientRouter`, supplies no
  `handleForms` prop, and uses literal lifecycle event names. It does not use the
  removed `ViewTransitions` alias or transition helper constants. The current
  implementation therefore matches the retained API, but navigation must still
  exercise `astro:page-load`, stepper cleanup, copy buttons and browser history.
  [Astro 6 removals](https://docs.astro.build/en/guides/upgrade-to/v6/#removed-viewtransitions--component),
  [Astro 7 removals](https://docs.astro.build/en/guides/upgrade-to/v7/#removed-exposed-astrotransitions-internals).
- **Text and templates:** Astro 7 uses the Rust compiler, which rejects unclosed
  tags and stops repairing invalid HTML nesting. Its default `compressHTML: 'jsx'`
  can remove spaces between inline elements. `compressHTML: true` is the documented
  compatibility option for preserving prior whitespace handling. Compare rendered
  text and desktop/mobile layout with the baseline.
  [Astro 7 migration guide](https://docs.astro.build/en/guides/upgrade-to/v7/).
- **Bundling:** Astro 7 moves to Vite 8. The only configured Vite plugin here is
  the compatible Tailwind plugin; there are no custom Rollup output overrides.
  Compile and exercise client scripts because bundler compatibility metadata alone
  is not runtime evidence.
  [Astro 7 dependency changes](https://docs.astro.build/en/guides/upgrade-to/v7/#dependency-upgrades),
  [Vite 8 migration guide](https://vite.dev/guide/migration).

The source inventory contains no Markdown/MDX pages, content collections, custom
adapter, `src/fetch.ts`, database integration or experimental flags. The related
Astro 6/7 migrations therefore have no direct application to the inspected site.
This is a repository-specific inference from `site/src`, `package.json`, and
`astro.config.mjs`, not an upstream guarantee.

## Validation to perform

1. Run clean installs and production builds on Node 22 and 24; inspect the resolved
   versions above, Sharp's actual bundled library versions, and the complete audit.
2. Run the repository's existing HTTP-verifier regression suite against the built
   site. Check responsive image dimensions, route identity, branded 404s, installer
   v1.1.0 links, CSS/JS, robots and sitemap output.
3. Exercise internal navigation, guide/install steppers, provider selection, copy
   buttons, history, keyboard focus and mobile overflow in the browser. Compare
   visible text and image rendering with the baseline.
4. Confirm CI on the reviewed commit, publish via the established Vercel project,
   and run `scripts/verify_site.py` against the production domain after the **last**
   deployment. The earlier incident proves that a later Git-triggered deployment
   can replace a previously verified one; see the
   [production repair evidence](production-2026-09-21.md).
