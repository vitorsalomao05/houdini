# Release checklist

The rule (ADR-010, revised 2026-07-03): **production advertises exactly one
version.** Every production release bumps, publishes the new one via CI, and
**prunes the *pointers*** (site, `README`, one-liner) so they reference only the
current version. Superseded releases and their tags are **kept** — retitled
"superseded — do not install" — so rollback and `houdini update` stay possible.
No "coming soon" placeholders ship to production — a surface is real and shown,
or absent.

**Publishing is CI's job.** `.github/workflows/release.yml` is the sole
publisher: it builds, verifies (core `swift test`, `houdini-selftest`,
built-binary `--metrictest`/`--widgettest`), checksums, and publishes on a
`vX.Y.Z` tag push. The manual role is to bump, tag, watch, and verify.

Replace `X.Y.Z` with the new version (and `P.Q.R` with the previous one).

---

## ▶ v0.4.0 — SHIPPED 2026-06-19 (popover redesign)

The menu-bar **popover was redesigned** onto the desktop widget's visual system
(consistent gauges, typography, and reset/overage readouts across both surfaces).
A **UI-only release** — no data-layer change: same providers, same Keychain-only
credential flow, same true 60-second refresh; the `houdini` CLI is byte-for-byte
identical to v0.3.0. App bumped to **0.4.0** (`apps/menubar/Info.plist` →
`CFBundleShortVersionString 0.4.0`, build `5`).

Go-live executed in order:

1. [x] `site/src/config.ts` → `version = "0.4.0"`, `installTag = "v0.4.0"`;
       `install.sh` → `TAG="v0.4.0"`; `README.md` one-liner + release link → `v0.4.0`;
       `site/package.json` → `0.4.0`.
2. [x] Commit: `chore(release): point install to v0.4.0` (`3ba16e1`).
3. [x] Built artifacts (CommandLineTools), tagged `v0.4.0` on `3ba16e1`, published
       `gh release create v0.4.0` with `Houdini.app.zip`, `houdini`, `SHASUMS256.txt`.
4. [x] Deleted the old release + tag: `gh release delete v0.3.0 --yes --cleanup-tag`
       (`gh release list` → only `v0.4.0`).
5. [x] `cd site && vercel build --prod && vercel deploy --prebuilt --prod`. Production
       `houdini.salomao.org` serves the new site; the 7 routes all 200; `tally → houdini`
       redirect (308) OK.

Install validated against the published `v0.4.0` tag in an isolated `HOME`: download
from the new release, SHA-256 match, idempotent re-run. Checksums (SHA-256):
`Houdini.app.zip` `0235f256552c8652633f5c6ec75b932898d54777f6e753e74331c3cd9eec2304`,
`houdini` `1d17035e281aa30dc68cbb45a298ba3c89f2d6cdffe0d53be71ee09a0c29270f`.

---

## ▶ v0.3.0 — SHIPPED 2026-06-18 (Round B)

Round B is **live**: the **native desktop widget** (replaced Übersicht), the
**redesigned logo** (free web mark + new `.icns`), honest **providers copy**, the
interactive **/install wizard** and **/guide** card tour, and the app at **0.3.0**
(`apps/menubar/Info.plist` → `CFBundleShortVersionString 0.3.0`, build `4`).

Go-live executed in order:

1. [x] `site/src/config.ts` → `installTag = "v0.3.0"`.
2. [x] `install.sh` → `TAG="v0.3.0"`.
3. [x] `README.md` → install one-liner + release link → `v0.3.0`.
4. [x] Commit: `chore(release): point install to v0.3.0` (`7d5b796`).
5. [x] Built artifacts (CommandLineTools), tagged `v0.3.0`, published
       `gh release create v0.3.0` with `Houdini.app.zip`, `houdini`, `SHASUMS256.txt`.
6. [x] Deleted the old release + tag: `gh release delete v0.2.0 --yes --cleanup-tag`
       (`gh release list` → only `v0.3.0`).
7. [x] `cd site && vercel --prod`. Production `houdini.salomao.org` serves the new
       site; home, `/install`, `/guide`, `og.png` all 200; `tally → houdini` redirect OK.

Install validated against the published `v0.3.0` tag in an isolated `HOME`: download
from the new release, SHA-256 match, idempotent re-run.

---

## 1 · Pre-flight
- [ ] `master` is clean (`git status` empty) and the local checks pass:
      `cd core && swift run houdini-selftest` and `cd site && npm run build`.
      (The release workflow itself is the release gate — it runs the full
      verification on the tag before anything publishes.)
- [ ] Optional but recommended: dry-run the release pipeline from the branch —
      `gh workflow run "Release Houdini" --ref <branch>` — and confirm the run
      is green and ends in a **draft** release; delete the draft afterwards.
- [ ] Decide the bump (semver): patch / minor / major. Note it in the release notes.
- [ ] No "coming soon" / "Soon" / "next milestone" copy anywhere user-facing
      (`grep -rIni 'coming soon\|>soon<\|next milestone' site/src README.md`).

## 2 · Bump the version (every place it lives)
- [ ] `site/src/config.ts` → `export const version = "X.Y.Z"` (drives the install
      one-liner and every release link automatically).
- [ ] `apps/menubar/Info.plist` → `CFBundleShortVersionString` = `X.Y.Z` and
      increment `CFBundleVersion`.
- [ ] `README.md` install one-liner + release link → `vX.Y.Z`.
- [ ] Any other pinned reference to the old version, with and without the `v`
      prefix (`grep -rIn "vP\.Q\.R\|P\.Q\.R" . | grep -v node_modules`).
- [ ] Commit: `chore(release): bump to vX.Y.Z`.

## 3 · Tag — CI builds, verifies, and publishes
- [ ] Tag and push: `git tag vX.Y.Z && git push origin vX.Y.Z`.
- [ ] Watch the run: `gh run watch` (workflow "Release Houdini"). It must pass
      all verification steps — core `swift test` (asserted to actually execute
      tests), `houdini-selftest`, built-binary `--metrictest` + `--widgettest` —
      before it stages, checksums, and publishes. **Do not** create the release
      by hand; if the run fails, nothing shipped — fix and re-tag.

## 4 · Verify what CI published
- [ ] `gh release view vX.Y.Z` → three assets: `Houdini.app.zip`, `houdini`,
      `SHASUMS256.txt`.
- [ ] Download `SHASUMS256.txt`, record the checksums in this file's shipped log.
- [ ] Confirm `install.sh` on the new tag fetches the new artifacts and checksums
      match (sanity-run the one-liner against the **new** tag on a clean path).

## 5 · Retitle superseded releases + prune pointers (ADR-010, revised)
- [ ] List what exists: `gh release list` and `git tag -l`.
- [ ] For every superseded version `P.Q.R`: **keep** the release and tag; retitle it
      `gh release edit vP.Q.R --title "Houdini vP.Q.R (superseded — do not install)"`.
- [ ] Prune the *pointers*: site, `README`, and the one-liner reference only `vX.Y.Z`
      (covered by §2 — re-check here).
- [ ] Re-check: `gh release list` shows `vX.Y.Z` as **Latest** and every older
      release retitled "superseded".

## 6 · Ship the site (production)
- [ ] Confirm the site references only `vX.Y.Z` (no old links, no "coming soon").
- [ ] If a feature shipped, the relevant section is **adapted** (re-framed), not a
      loose new block bolted on (ADR-010).
- [ ] Deploy production from `site/`: `vercel build --prod && vercel deploy
      --prebuilt --prod` (the practiced prebuilt two-step). Preview deploys —
      `vercel deploy` with no `--prod` — are safe for review and do **not**
      touch production.
- [ ] Smoke-test production: home, `/install`, `/guide` all 200; one-liner copies the
      `vX.Y.Z` command.

## 7 · Post-release
- [ ] Update `ROADMAP.md` / `DECISIONS.md` if the release changed direction.
- [ ] Announce only after production is verified.

---

**Never:** leave two *advertised* versions live · point the site at a dead tag ·
publish a "Soon" placeholder · `gh release create` by hand (CI is the sole
publisher) · `vercel --prod` from an unreviewed build · put any provider
API/admin key in the site, frontend, env bundle, or repo (ADR-011 — keys live
only in the user's Keychain).
