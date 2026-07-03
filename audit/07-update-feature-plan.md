# 07 · Plan — Houdini self-update / clean-upgrade command (`houdini update`)  (REVISED BY AUDIT 2026-07-03)

> **Status:** AUDIT-REVISED planning — *no code in this document.* The 2026-07-03 impartial
> audit re-verified every §1 grounding claim (6 hold, **2 wrong** — see R1 below), researched
> the self-update patterns against primary sources, and **endorses option (a) with five
> mandatory hardening conditions** (R3). Read the AUDIT REVISION section first; where the
> body conflicts with it, the revision wins.
> **Author pass:** 2026-07-02. **Owner sign-off required** before implementation (this is a
> future **Fable 5 Ultracode** task, after the v1 blocker phases — see `05-v1-plan.md`).

---

## AUDIT REVISION (2026-07-03)

### R1. Grounding corrections

1. **§1.5 is false: `RELEASE.md` EXISTS** (repo root, 116 lines, tracked since 2026-06-18 —
   commits 710bef3→c80483a — containing exactly the bump/publish/prune checklist ADR-006/010
   reference). Everything downstream changes from "create RELEASE.md" to **"amend
   RELEASE.md"**: add the `apps/menubar/Info.plist` bump to §2 (its `grep "vP.Q.R"` safety
   net cannot match the un-prefixed `0.4.0`, and §4.2 makes that plist the authoritative
   installed-version marker), and add a post-release `houdini update --check` smoke test.
2. **§1.2 describes a pipeline that has never run to completion.** All 4 `release.yml` runs
   ever (v0.2.0 ×2, v0.3.0, v0.4.0) **failed** (`gh run list`: WidgetGlass.swift `glassEffect`
   needs the macOS 26 SDK; the runner pins Xcode 16); both shipped releases were **manual
   CommandLineTools builds** per RELEASE.md's own log. Consequence for §9 Phase 1 / §10 Q2:
   the version constant must be injected in the **shared build path** (build.sh / a generated
   source file) so manual and CI builds both get it — not in release.yml alone. Fixing or
   retiring release.yml is a **prerequisite decision** (see 05 · Phase A).

### R2. The single-version policy kills downgrades — fix the contradiction

Verified live: only the `v0.4.0` tag exists remotely; v0.2.0/v0.3.0 raw `install.sh` URLs
return **404**. Under ADR-010 + RELEASE.md §5, an older tag **never** exists once superseded
— so §4.1's "may be an older version (explicit downgrade)" and §10 Q9's "allow downgrade when
the tag exists" describe a **null set**, and §7's "often 404s" understates to "always".
**Resolution:** restrict `houdini update <version>` to the current latest (pin/reinstall
semantics) or drop the positional argument for v1. (Separately, the audit recommends revising
ADR-010 to *keep* superseded releases marked "superseded" + enable GitHub **Immutable
Releases** — see 04 · OPP-17; if adopted, named-version updates become meaningful again.)

### R3. Option (a) ENDORSED — with five mandatory conditions

(a) and (b) share the **identical trust root** (TLS to GitHub + same-release SHASUMS256.txt;
no independent signature exists anywhere), so (b) adds zero security while duplicating the
security-critical logic in a second language — (a) wins. Honest caveat to own in §6: with
(a), a binary auto-executes a freshly fetched script the user never reads, and the fetched
script itself is not checksum-verified (only the assets it downloads are). That makes these
conditions **non-optional**:

1. **CLI rename-aside before delegating (fixes a real crash hazard).** §3/§7's "a running
   binary can be replaced (unlink+write) — safe" is **wrong for this repo**: install.sh:107
   uses `cp -f`, which truncates and rewrites the **same inode**. Apple's "Updating Mac
   Software" doc: the kernel caches code-signature info per file and does not flush it on
   in-place modification → "Code Signature Invalid" crashes; the kernel can kill the running
   process whose backing executable was modified (Apple names `cp` as the unsafe tool and
   `ditto` as the safe one; the app path — `rm -rf` + `ditto` — is fine). Fix, CLI-side, no
   installer edit: **rename `~/.local/bin/houdini` aside** (e.g. `houdini.old`) before
   delegating — frees the path so `cp -f` creates a new inode, keeps the running updater
   alive on the old inode, and yields a free rollback copy (restore on non-zero exit, delete
   on success). This is exactly rustup's/`self-replace`'s and deno's pattern.
2. **Pre-stash `Houdini.app` — REQUIRED, not optional** (upgrades §5.4/§10 Q6): install.sh
   does `rm -rf "$APP"` before extracting, leaving a no-app window with no restore path on
   failure; a same-volume rename-aside stash closes it at near-zero cost. (If a native swap
   is ever built: `renameatx_np(RENAME_SWAP)` on APFS is the atomic two-path primitive.)
3. **TAG-match guard:** parse the fetched installer's `TAG=` line and require it to equal the
   resolved target (and/or verify post-install Info.plist == target) before printing
   "Updated" — the tag→TAG invariant is currently enforced only by a manual RELEASE.md grep;
   a release that forgets the bump would otherwise silently install the *previous* version
   while reporting success.
4. **Login-item neutrality via tty-detached spawn:** run the installer **without a
   controlling terminal and without `HOUDINI_YES`** — install.sh's `ask()` then takes the
   `{ true > /dev/tty; }` failure branch → default **No** → "skipped login item" (which does
   NOT unregister an existing one, i.e. exactly neutral). Zero installer edits; interactive
   passthrough would re-prompt on every update (noise); `HOUDINI_YES=1` would force-enable.
5. **Handle install.sh's unconditional `open "$APP"` (install.sh:116-117):** on
   update-while-running, `open` merely foregrounds the **old, still-running** instance right
   after the success message — the report must anticipate it ("Houdini is still running
   v0.4.0 — quit and relaunch to load v0.5.0"); on update-while-not-running the new version
   silently self-launches (fine, but §5.3's behavior inventory must include it).

Plus two additions from research: an **unmanaged-install guard** (uv/mise pattern — before
mutating, verify the running binary resolves to `~/.local/bin/houdini` and the app to
`~/Applications/Houdini.app`; if elsewhere, warn and refuse — strengthens §7's PATH row into
a safety gate), and **expected post-update UX**: the app is ad-hoc signed, so every update
mints a new code identity — TCC grants and Keychain ACL bindings reset and the user may be
re-prompted; document as expected, not a regression.

### R4. §10 open questions — answers

| Q | Answer |
|---|---|
| Q1 surface | CLI-first (`houdini update`); menu-bar item is a thin follow-on. |
| Q2 version source | Inject from the tag **in the shared build path** (not release.yml alone — R1.2); add the Info.plist bump to RELEASE.md §2. |
| Q3 `--check` cadence | On-demand only for v1 (no-telemetry guardrail). |
| Q4 old-version 404 UX | Yes — but "always", not "usually" (R2); say so in the error. |
| Q5 installer parameterization | Fetch-per-tag; never edit install.sh; add the TAG-match guard (R3.3). |
| Q6 rollback depth | Pre-stash/restore is **required** (R3.2), and rename-aside for the CLI (R3.1). |
| Q7 RELEASE.md | Premise false — it exists; **amend** it (R1.1). |
| Q8 auto-relaunch | Message-only for v1, accounting for the `open` side effect (R3.5). |
| Q9 downgrades | **No** — latest-only `<version>` semantics (R2); revisit only if ADR-010's prune rule is revised (OPP-17). |

### R5. Sources added by the audit

Apple — Updating Mac Software (kernel signature cache; cp-vs-ditto); Apple DevForums 130313
(Quinn: never overwrite a Mach-O in place) + 781548 (in-situ replacement breaks the bundle
seal) + 730043 (TCC vs ad-hoc identities); OpenRadar FB8914243 (arm64 stale-signature-cache);
`self-replace` crate docs; deno upgrade reference (`--dry-run`, `deno.old.exe` rename-aside);
gh manual + cli/cli#166 (no self-update **by design** — notifier only); uv/mise unmanaged-
install guards; Homebrew Acceptable Formulae (self-update must be disabled — two owners
desync); Sparkle docs (embedded EdDSA public key = old version verifies new; separate helper
processes); GitHub Immutable Releases GA (2025-10-28; compatible with pruning — tags become
unreusable, releases still deletable); GitHub artifact attestations (`gh attestation verify`);
nickovs/atomicswap (`renameatx_np` RENAME_SWAP).
>
> **Scope guardrail (CLAUDE.md):** *"Installer integrity is sacred."* Any change touching
> `install.sh` or `SHASUMS256.txt` is a **🔴 gated action** requiring explicit human
> sign-off. This plan is written so the default path can ship **without** modifying either.

---

## 0. TL;DR

- Add an `update` subcommand to the existing **`houdini` CLI**: `houdini update`
  (default = latest), `houdini update <version>` (pin), `houdini update --check` (dry-run),
  plus a `houdini --version` primitive.
- Resolve **installed vs. target** version, using **GitHub Releases as the source of truth**.
- Download + install the target through the **exact same verified path as `install.sh`**
  (pinned tag → SHA-256 vs. `SHASUMS256.txt` → no `sudo` → no Gatekeeper prompt).
- **Clean up old-version artifacts** so only the latest remains, scoped to a **precise
  owned-file manifest** (least-privilege) — never touch user data or Keychain credentials.
- Print a **clear terminal message**: `Updated Houdini v0.4.0 → v0.5.0`, `Already on the
  latest (v0.4.0)`, or a failure/rollback line that leaves the current install intact.
- **Recommended design: (a)** — `houdini update` **re-runs the already-verified
  `install.sh`** for the resolved tag, then performs an explicit owned-file cleanup pass.
  The CLI never re-implements download/verify/swap. See §6 for the trade-off vs. (b).

---

## 1. Grounding — what exists today (verified from the repo)

Read this before changing anything; the plan reuses these primitives verbatim.

### 1.1 `install.sh` (the verified install path we must not weaken)
File: `install.sh` (pinned `TAG="v0.4.0"`, `REPO="vitorsalomao05/houdini"`). Full flow:

1. **Preflight** — refuses anything but **macOS 14+ on Apple Silicon** (`arm64`); requires
   `curl shasum ditto open` (`install.sh:60-69`).
2. **Download from the pinned Release only** — `curl -fSL --proto '=https' --tlsv1.2` fetches
   `SHASUMS256.txt`, `Houdini.app.zip`, `houdini` from
   `github.com/$REPO/releases/download/$TAG` (`install.sh:71-88`).
3. **SHA-256 verify** — `shasum -a 256 -c` against the downloaded `SHASUMS256.txt`; **aborts on
   any mismatch** and refuses to install unverified bytes (`install.sh:75-92`).
4. **Install without `sudo`** — app → `~/Applications` (via `ditto -x -k`), CLI → `~/.local/bin`
   (`cp` + `chmod +x`) (`install.sh:94-113`).
5. **No Gatekeeper prompt** — `xattr -dr com.apple.quarantine "$APP"` on the ad-hoc-signed app
   (`install.sh:100-102`).
6. **Offered-not-forced login item** — `ask` reads `/dev/tty`; `HOUDINI_YES=1` = unattended;
   no terminal / no env → **default No** (`install.sh:44-58, 119-128`).
7. **Idempotent / safe to re-run** — `rm -rf "$APP"` then re-extract; overwrites the CLI in
   place; prints exact uninstall steps (`install.sh:96-142`).

**These are advertised guarantees** (README install section; CONTEXT "Distribution"; ADR-006).
The update feature must preserve **every one** of them.

### 1.2 Release pipeline (how a tag becomes assets)
File: `.github/workflows/release.yml`. Fires on **`v*.*.*` tags**. On an **arm64 `macos-14`
runner** it builds `apps/menubar/build.sh release` + `swift build -c release --product houdini`,
then stages and publishes **exactly three assets** with `gh release create`:

- `Houdini.app.zip` — menu bar app + native desktop widget (ad-hoc signed, hardened runtime),
  zipped with `ditto -c -k --keepParent` so it extracts to `Houdini.app`.
- `houdini` — the data-layer CLI (`chmod +x`).
- `SHASUMS256.txt` — **bare filenames** (`shasum -a 256 Houdini.app.zip houdini`) so
  `install.sh`'s `shasum -c` matches.

So the update feature has a stable, known contract: **for any tag, these three asset names
exist and `SHASUMS256.txt` covers the two binaries.**

### 1.3 The `houdini` CLI today (what we're extending)
File: `core/Sources/houdini/main.swift`. Today it does **one thing**: fetch a provider
snapshot and print JSON. Relevant facts for this plan:

- **No subcommands, no arg-parsing library** — it just treats the first non-`-` arg as a
  provider id and ignores unknown flags (`main.swift:21-28`). Adding `update` means introducing
  a small verb dispatch (or `swift-argument-parser`) — a real, if modest, change.
- **No version awareness** — there is **no `--version` flag and no embedded version constant**
  in the CLI. The **app** bundle carries `CFBundleShortVersionString = 0.4.0`
  (`apps/menubar/Info.plist:19-20`), but the CLI binary does not. `houdini --version` must be
  **added** (see §4.1 / §8).
- Package: `core/Package.swift` declares the `houdini` executable (macOS-only; uses
  `Foundation.Process`). The app's headless flags (`--snapshot`, `--selftest`,
  `--register-login-item`, `--unregister-login-item`) live in the **app** binary
  (`apps/menubar/Sources/Houdini/Main.swift:8-37`), *not* the CLI — worth noting because
  `houdini update` may want to call the app's `--unregister-login-item` (see §5, §7).

### 1.4 Governing decisions
- **ADR-006** — ad-hoc-signed app via `install.sh` (`curl | bash`) **is** the shipping path
  (not a stopgap). Sparkle auto-update stays a *separate future option*. The update command
  should be "a thin wrapper over the verified `install.sh` re-run" per BACKLOG P4 notes.
- **ADR-010** — **single advertised version**; every release bumps + publishes + **removes every
  obsolete GitHub release / tag / installer artifact**. Installer is always re-fetched from the
  current tag. *Implication:* older tags may **not exist** on GitHub — `houdini update
  <old-version>` can legitimately 404 (see §7). "Latest" is the normal, blessed target.
- **CLAUDE.md guardrails** — installer integrity is sacred; credentials live only in the
  Keychain; no telemetry; least-privilege for any elevated action.
- **BACKLOG P4** — states the goal, the "same verified path" requirement, the owned-file
  cleanup requirement, and the "display the new version" requirement. This plan fulfils it.

### 1.5 Doc gap noticed (flag, don't fix here)

> **⚠ AUDIT CORRECTION (2026-07-03): this section is FALSE.** `RELEASE.md` exists at the
> repo root (116 lines, tracked since 2026-06-18 — `git log -- RELEASE.md` → 710bef3,
> 53c843f, d04b11d, c80483a) and contains exactly the bump/publish/prune checklist
> ADR-006/010 reference. The correct P4 action is to **amend** it (Info.plist bump in §2;
> `houdini update --check` post-release smoke test), not create it. See AUDIT REVISION R1.

~~ADR-006 and ADR-010 both reference a **`RELEASE.md`** checklist ("The procedure is the checklist
in `RELEASE.md`"), but **no `RELEASE.md` exists in the repo** (searched; absent). Not in scope
for this feature, but the release/prune procedure this plan leans on (ADR-010) is currently
**undocumented** — worth creating during or before the P4 wave (see §9 open questions).~~

---

## 2. Goal & acceptance (restated from BACKLOG P4)

**One command upgrades an installed Houdini to the target release, removes leftover files from
any previous version, installs the new version, and reports the new version — through the same
verified, no-`sudo`, no-Gatekeeper, offered-not-forced path as `install.sh`.**

Acceptance:
- `houdini update` on an out-of-date install → verified download of latest → old artifacts
  removed → new version installed → `Updated Houdini vX → vY` printed.
- `houdini update` when already latest → **no-op**, prints `Already on the latest (vX)`.
- `houdini update <version>` → targets that exact tag (or fails cleanly if ADR-010 pruned it).
- `houdini update --check` → **dry-run**: reports installed + latest and whether an update is
  available; changes nothing on disk.
- **Every `install.sh` guarantee preserved.** No credential is read, logged, transmitted, or
  cached. Cleanup is least-privilege and never touches user data or the Keychain.
- Failure at any step (network, checksum, extraction) **aborts and leaves the current install
  working** (no half-upgrade).

---

## 3. Research — safe CLI self-update patterns (what good tools do)

Light survey of `gh`, `rustup`, and Homebrew, plus atomic-swap/verification practice. Full URLs
in **§11 Sources**.

**Atomic download → verify → swap.** The durable pattern everywhere: download to a **temp
location**, **verify** (checksum/signature) *before* touching the live install, then swap into
place with an **atomic rename** so a reader sees either the old complete file or the new one —
never a half-state. `os.rename`/`os.replace`-style atomicity holds **within one filesystem**;
cross-filesystem needs a copy-then-rename. This is exactly what `install.sh` already does with
`mktemp -d` + `trap rm -rf` + verify-before-install — Houdini is well-positioned to reuse it.

**Verify before install, refuse on mismatch.** `gh` publishes **immutable releases** and build
**provenance attestations** (Sigstore) and can self-verify a download; general Rust self-updaters
(the `self_update` crate) do **signature verification + atomic file replacement**; a tampered or
mismatched binary is **refused**. Houdini's analogue is the **SHA-256 vs. `SHASUMS256.txt`**
gate — keep it as the hard abort.

**Replacing a running binary.** `rustup self update` downloads a fresh `rustup-init` and runs it
with a hidden `--self-replace` flag to swap the in-use binary and update shims. On macOS/Unix a
**running executable can be replaced** (unlink + write new) because the open inode persists —
so a running `houdini` overwriting `~/.local/bin/houdini` is safe. **Replacing a running `.app`
that the user has open** is the real edge case (see §7).

**Transactional multi-file moves / rollback.** rustup's `MoveAll` applies a set of moves
**transactionally** — either all succeed or the first failure **rolls back** the already-applied
moves, so a failed update can't leave a half-installed tool. Houdini ships **two** artifacts
(app + CLI), so it should treat "install app + install CLI" as one unit and, on failure, restore
what it moved (see §5.4).

**Cleaning up old versions.** Homebrew **automatically uninstalls old versions on
`brew upgrade`**, and `brew cleanup` removes stale versions/downloads, keeping only the most
recent — with a **`--dry-run`** that shows what *would* be removed without removing it. Two lifts
for Houdini: (1) delete old artifacts as part of upgrade, and (2) offer a **dry-run/`--check`**
so users can preview.

**Terminal UX for update messages.** Across `az upgrade`, WP-CLI `core check-update`, and
`pamac --dry-run`: show **installed vs. latest** explicitly, print a clear **"already on the
latest"** when current, and offer a **dry-run** that prints the delta and changes nothing. Keep
messages short, name the versions, and make success/no-op/failure visually distinct.

**Takeaways applied to Houdini:**
1. Reuse the `install.sh` temp-dir + verify-before-install flow (don't invent a second one).
2. SHA-256 mismatch = **hard abort**, current install untouched.
3. Treat the two-artifact install as one transaction; roll back on partial failure.
4. Clean old versions as part of upgrade; expose a **dry-run** (`--check`).
5. Emit explicit installed→target messaging and a distinct no-op line.

---

## 4. CLI surface (the `houdini` command)

All new surface lives on the **existing `houdini` CLI** (not the app). Design a minimal verb
dispatch on top of today's arg handling (§1.3).

### 4.1 Commands

| Command | Behavior |
|---|---|
| `houdini --version` | Print the CLI's own version (e.g. `houdini 0.4.0`). **New** — no version constant exists today; add one (embedded at build time, ideally from the tag). Primitive for everything below. |
| `houdini update` | Update to **latest**. Resolve installed vs. latest; if already latest, no-op with a message; else verified download + install + cleanup + report. |
| `houdini update <version>` | Update to an **explicit tag** (e.g. `v0.5.0` / `0.5.0`). Same path, `TAG` fixed to the requested version. May be an **older** version (explicit downgrade) or a **newer** one. Fails cleanly if the tag no longer exists (ADR-010 pruning). |
| `houdini update --check` | **Dry-run.** Print installed + latest and whether an update is available. **Changes nothing.** |

Suggested extras (small, optional; decide at build time):
- `--yes` / `-y` — non-interactive (mirrors `install.sh`'s `HOUDINI_YES`), for scripts/CI.
- `--json` — machine-readable status for `--check` (consistent with the CLI's existing
  `--json` contract), e.g. `{"installed":"0.4.0","latest":"0.5.0","update_available":true}`.
- Keep the existing default (`houdini` with no verb) = fetch the `claude` snapshot, unchanged —
  **`update` is an explicit verb**, so no collision with provider ids (guard: reject/ignore a
  provider literally named `update`, or require the verb form).

### 4.2 Version resolution — GitHub Releases as source of truth
- **Installed version** — read from the **installed app bundle**
  `~/Applications/Houdini.app/Contents/Info.plist` → `CFBundleShortVersionString` (this is the
  one authoritative on-disk version marker today, `= 0.4.0`). Optionally cross-check the CLI's
  own `--version`. If the app isn't installed, treat as "not installed" (see §7).
- **Latest version** — query the **GitHub Releases API**
  (`https://api.github.com/repos/vitorsalomao05/houdini/releases/latest`) and read `tag_name`.
  Unauthenticated is fine (public repo; low rate). No token, no credential.
- **Compare** by semver (normalize `v` prefix). Equal → no-op; target > installed → upgrade;
  target < installed → explicit downgrade only when a version is named (never on bare `update`).
- **Source-of-truth note:** the *installer* pins a tag literally in `install.sh`; the *update
  command* asks GitHub what "latest" is. These agree because ADR-010 keeps exactly one live
  release and re-fetches `install.sh` from the current tag.

---

## 5. Behavior — the update run (recommended design (a))

**Design (a): `houdini update` orchestrates a re-run of the already-verified `install.sh` for
the resolved tag, then performs an explicit owned-file cleanup.** The CLI is the *conductor*;
`install.sh` remains the *only* code that downloads, verifies, and installs.

### 5.1 Resolve
1. Determine **installed** version (§4.2) and **target** (`--check`/bare = latest; else the
   named tag).
2. If **target == installed** and not a forced re-install → print `Already on the latest (vX)`
   and exit `0`. (For `--check`, print the installed/latest comparison and exit.)
3. If `--check` → print the delta (`Update available: v0.4.0 → v0.5.0` **or** `Already on the
   latest`), change nothing, exit.

### 5.2 Fetch the verified installer for the target tag
- Fetch `install.sh` **from the target tag ref**, matching the advertised trust model
  (the pinned per-tag `raw.githubusercontent.com/<repo>/<tag>/install.sh`). This is the same
  artifact the site/README advertise, tied to the release being installed.
- Run it with the target tag and unattended-but-no-login defaults:
  `HOUDINI_YES` semantics must **not** silently enable the login item — the update should be
  **login-item-neutral** (preserve the user's current choice; do not newly force-enable). If
  the installer's `HOUDINI_YES=1` would accept the login item, pass through the CLI's own
  interactivity instead, or set an explicit "don't offer login on update" path (see §8 open
  item — small installer nuance to settle **without weakening** any guarantee).
- Because `install.sh` targets a **fixed `TAG`** constant today, design (a) needs a way to point
  it at an arbitrary tag. Two non-`install.sh`-modifying options, in preference order:
  1. **Fetch `install.sh` from the target tag** — that copy already has `TAG` pinned to *its own*
     tag, so running the `v0.5.0` copy installs `v0.5.0`. **No edit to the shipping installer.**
     (Clean, and it's literally what the site advertises for that version.)
  2. If a single-parameterized installer is ever wanted, adding e.g. `TAG="${HOUDINI_TAG:-v0.4.0}"`
     is a **one-line change to `install.sh` → 🔴 gated action** (touches the installer). Prefer
     option 1 to avoid the gate; keep this only as a noted alternative.

> Net: design (a) can ship with **zero changes to `install.sh`/`SHASUMS256.txt`** by fetching the
> per-tag installer (option 1). That keeps the sacred-installer guardrail satisfied by default.

### 5.3 Install (delegated, fully verified)
The re-run performs, unchanged: preflight → download the 3 assets from the target tag →
**SHA-256 verify vs. `SHASUMS256.txt`** → install app to `~/Applications` (no `sudo`) → strip
quarantine (no Gatekeeper prompt) → install CLI to `~/.local/bin`. **Idempotent overwrite** is
already the installer's behavior, so the app and CLI are replaced in place.

### 5.4 Clean up old-version artifacts (the new step) — owned-file manifest
Cleanup runs **after** a successful install so we never delete the working copy before the new
one lands. **Least-privilege: only files Houdini itself owns.**

**Owned-file manifest (authoritative list — everything the installer creates, nothing else):**

| Path | Owner? | Update action |
|---|---|---|
| `~/Applications/Houdini.app` | **Yes** — installed by `install.sh:96-103` | Replaced in place by the re-run (`rm -rf` + re-extract). No separate cleanup needed for the *current* location. |
| `~/.local/bin/houdini` | **Yes** — installed by `install.sh:105-108` | Overwritten in place by the re-run. |
| Login item registration (LaunchServices) | **Yes** — only if the user opted in (`install.sh:120-125` → app `--register-login-item`) | **Preserve** the user's choice. On update, do not toggle. (Only on *uninstall* would we `--unregister-login-item`.) |
| Quarantine xattr on the app | Managed by installer | Handled by the re-run's `xattr -dr`. |
| **Any other path** (Keychain items `Houdini-claude-session` / `Claude Code-credentials`; `~/.claude/*`; app preferences/`UserDefaults`; caches; last-good snapshot) | **User data / not installer-owned** | **NEVER touched.** Explicitly out of manifest. |

**What "clean up old versions" actually means here.** Because both the app and CLI install to
**fixed paths** (`~/Applications/Houdini.app`, `~/.local/bin/houdini`), a normal upgrade
**overwrites in place** — there is no version-numbered directory (unlike Homebrew's Cellar) that
accumulates. So in the current layout, "leftover old-version artifacts" are essentially:
- A **stale app at a non-standard/legacy location** from an older install convention (e.g. a copy
  a user dragged to `/Applications`, or a pre-rename `Tally.app` from ADR-009). Cleanup should
  **detect and offer to remove** known legacy names/locations **only with explicit confirmation**
  (never silently reach into `/Applications`). Default: report, don't auto-delete outside
  `~/Applications`.
- **Orphaned sidecar files** a *future* version might introduce (none today). The manifest is the
  contract: when a future release adds an owned file, it gets added here, and cleanup removes the
  prior version's copy.

**Rollback / transactional safety (per §3 research):** treat "install app + install CLI" as one
unit. If the re-run fails after replacing the app but before the CLI (or vice-versa), the
installer already `die`s; the update wrapper should **detect non-zero exit and NOT run cleanup**,
leaving whatever the installer left (the installer's own `rm -rf`→re-extract means a failed
extract is caught by its `[ -d "$APP" ] || die`). For extra safety the wrapper MAY stash the
prior `Houdini.app` to a temp path before delegating and restore it if the install exits non-zero
(optional hardening; see §8).

### 5.5 Report (terminal UX)
Distinct, short messages (colorized like `install.sh`'s `ok`/`warn`/`die`):
- Success: `✓ Updated Houdini v0.4.0 → v0.5.0` + one line each for app + CLI paths + "restart
  Houdini from the menu bar to load the new version" if the app was running (§7).
- No-op: `✓ Already on the latest (v0.4.0).`
- Dry-run: `Update available: v0.4.0 → v0.5.0  (run: houdini update)` or `✓ Already on the
  latest (v0.4.0).`
- Failure: `✗ Update failed: <reason>. Your current install (v0.4.0) is unchanged.` — never a
  half-state; explicit "unchanged" reassurance.
- **Version display closes the loop** (BACKLOG P4): the CLI prints the new version, and the
  app's own "About"/version already reads `CFBundleShortVersionString` from the freshly-installed
  bundle, so relaunching shows `v0.5.0`.

---

## 6. Design options + recommendation

### Option (a) — `houdini update` shells the verified `install.sh` (recommended)
The CLI resolves versions, fetches the **per-tag `install.sh`**, delegates download/verify/install
to it, then runs the owned-file cleanup + reporting.

- **Pros:** *One* verified code path — zero duplication of the SHA-256/quarantine/no-`sudo`
  logic, so the "installer integrity is sacred" guarantee is enforced in exactly one place and
  can't drift between installer and updater. Ships with **no change to `install.sh`/
  `SHASUMS256.txt`** (fetch the per-tag installer), so it **avoids the 🔴 gated action** entirely.
  Directly matches BACKLOG P4's "thin wrapper over the verified `install.sh` re-run + explicit
  cleanup" and ADR-006/010.
- **Cons:** Requires a network fetch of `install.sh` at update time (already the trust model);
  atomicity is "install then cleanup," relying on the installer's own `die`-on-failure rather
  than a single native transaction; pointing the installer at an arbitrary tag is done by
  fetching that tag's copy (fine) rather than a parameter (a parameter would be gated).

### Option (b) — the CLI performs download + verify + swap natively (in Swift)
`houdini update` re-implements the flow: fetch the 3 assets, verify SHA-256 against
`SHASUMS256.txt`, extract the app, strip quarantine, atomically swap both artifacts, clean up.

- **Pros:** Fully self-contained (no shelling out); can implement a **true atomic/transactional
  swap with rollback** in one place; finer control over messaging and the running-app case.
- **Cons:** **Duplicates the security-critical install logic** in a second language — now the
  SHA-256 gate, the quarantine strip, the no-`sudo` placement, and the preflight all exist
  **twice** and must be kept in lockstep with `install.sh` forever. That is precisely the drift
  risk the "installer integrity is sacred" guardrail exists to prevent, and it's a larger
  security-adjacent surface to review. Also re-implements `ditto`/`xattr`/`shasum` behavior.

### Recommendation: **(a)**, with a small, well-scoped cleanup + reporting layer in the CLI.
Reuse beats re-implementation here: the verified path is the crown-jewel guarantee, and (a) keeps
it single-sourced while satisfying every P4 requirement **without** touching the sacred installer.
Adopt one hardening idea from (b) — the **optional pre-stash-and-restore of `Houdini.app`** (§5.4)
— to get rollback-grade safety without duplicating the download/verify logic. Revisit (b) only if
we later ship Sparkle or a signed/notarized DMG (ADR-006 future option), where a native updater
is the natural home.

> **Gated-action note (must be explicit in the eventual PR):** the default (a) path is designed to
> need **no** edit to `install.sh` or `SHASUMS256.txt`. If implementation ever proposes
> parameterizing the installer's `TAG` (or any installer/checksum change), that is a **🔴 gated
> action requiring human sign-off** per CLAUDE.md — stop and get approval first.

---

## 7. Edge cases

| Case | Handling |
|---|---|
| **Already latest** (bare `update`) | No-op; `✓ Already on the latest (vX).` Exit `0`. Never re-download. |
| **`--check` dry-run** | Print installed + latest + availability; change nothing; exit `0`. |
| **Explicit older version** (`houdini update 0.3.0`) | Allowed as an explicit downgrade *iff* the tag still exists. But **ADR-010 prunes old tags/releases**, so this often **404s** — fail cleanly: `✗ v0.3.0 is no longer published (Houdini keeps only the latest release). Latest is vX.` |
| **Explicit newer/nonexistent version** | If the tag doesn't exist on GitHub → clean 404 message with the current latest; no partial work. |
| **Network failure** (resolve or download) | Abort before touching the install; `✗ Update failed: could not reach GitHub. Your current install (vX) is unchanged.` The installer's `curl -fSL … || die` already aborts mid-download. |
| **Checksum mismatch** | The delegated `install.sh` `die`s on `shasum -c` failure and installs nothing; wrapper reports `✗ Update failed: checksum mismatch — refusing to install. Current install unchanged.` **Never** run cleanup after a failed install. |
| **Running app during update** | On macOS a running `.app` **can** be replaced on disk (open bundle keeps working from its inode); the **running process keeps the old version until relaunch**. So: replace files, then print `Restart Houdini (menu bar ▸ Quit, then relaunch) to load vY.` Optionally offer to quit+relaunch via the app (out of scope for v1; a plain message is enough). The **CLI overwriting itself** while running is safe (unlink+write). |
| **PATH issues** | If `~/.local/bin` isn't on `PATH`, the *user* may be running a `houdini` from elsewhere. On `update`, detect the running binary's own path vs. `~/.local/bin/houdini`; if they differ, warn (`! Updated ~/.local/bin/houdini, but 'houdini' on your PATH resolves to <other>; add ~/.local/bin to PATH`) — same guidance `install.sh:110-113` already prints. |
| **App not installed at all** | `houdini update` from a stray CLI with no `~/Applications/Houdini.app` → treat as **install**, not update: run the installer for latest and report `Installed Houdini vX`. |
| **Interrupted mid-run (Ctrl-C / crash)** | Installer uses `mktemp -d` + `trap rm -rf … EXIT`, so temp files are cleaned; a partial extract is caught by `[ -d "$APP" ] || die`. Wrapper's rule: **no cleanup unless install exited 0.** Optional pre-stash/restore (§5.4) covers the "app half-replaced" window. |
| **Non-arm64 / old macOS** | Installer preflight already refuses; the wrapper surfaces that message rather than proceeding. |
| **Two installs / non-standard app location** | Cleanup only auto-removes within `~/Applications`; a legacy/`/Applications` copy is **reported for manual removal**, never silently deleted (least-privilege). |

---

## 8. Security & safety requirements (non-negotiable)

- **Preserve every `install.sh` guarantee** — SHA-256 verify vs. `SHASUMS256.txt`, no `sudo`,
  no Gatekeeper prompt, offered-not-forced login item. Design (a) inherits these by delegation;
  **do not** re-implement or weaken them.
- **HTTPS + pinned tag only** — resolve latest via the GitHub API over HTTPS; download only the
  three assets from the pinned target tag's Release (as the installer already enforces with
  `--proto '=https' --tlsv1.2`).
- **No credential access, ever** — the update path **must not** read, log, transmit, or cache
  the Keychain items (`Houdini-claude-session`, `Claude Code-credentials`), `~/.claude/*`, cookies,
  or tokens. It has no reason to touch auth at all. (Auth-adjacent → Opus review per CLAUDE.md if
  the implementation ever comes near the Keychain; it should not.)
- **Cleanup stays safe (least-privilege)** — act **only** on the owned-file manifest (§5.4).
  Never `rm` outside `~/Applications/Houdini.app` and `~/.local/bin/houdini` without explicit
  user confirmation; **never** touch user data, preferences, caches, or the Keychain. Prefer
  "report and let the user remove" for anything outside the two owned paths.
- **No telemetry** — the version check is a plain unauthenticated GitHub API call; add no
  analytics, no phone-home, no trackers (CLAUDE.md).
- **Version pinning vs. latest** — bare `update` = latest (the ADR-010 blessed target);
  `update <version>` lets a user pin, but honesty about pruning (old tags may be gone) is part of
  the UX. `--check` never mutates.
- **Login-item neutrality on update (small nuance to settle):** ensure the delegated installer,
  when run unattended for an update, does **not** newly force-enable launch-at-login. Options:
  drive the installer interactively from the CLI, or gate the login prompt out on the update path.
  This must be solved **without weakening** the installer's offered-not-forced guarantee (and any
  edit to `install.sh` to support it would be a 🔴 gated action — prefer a CLI-side solution).

---

## 9. Phased implementation outline (for the future Fable 5 Ultracode task)

> Discovery-first, smallest reviewable slices. **Not** to be built until P1–P3 are clear and the
> owner signs off. No installer/checksum edits without the gate.

- **Phase 0 · Discovery + decisions (no code).** Confirm this plan's assumptions against
  current HEAD (asset names, install paths, ADR-010 pruning still in force). Lock the open
  questions in §10. Decide whether to introduce `swift-argument-parser` or a hand-rolled verb
  switch for the CLI. Draft/locate `RELEASE.md` (the ADR-referenced but missing checklist) since
  the update UX depends on the release/prune contract.
- **Phase 1 · Version primitives.** Add an **embedded version constant** to the `houdini` CLI
  (ideally injected from the git tag at build time in `release.yml`) and a `houdini --version`
  flag. Add installed-version read from `~/Applications/Houdini.app/.../Info.plist`. Add the
  GitHub "latest" resolver. **Extend `houdini-selftest`/`FetcherCoreTests`** for the compare
  logic (mock the GitHub response and the Info.plist read) — no live network in tests.
- **Phase 2 · `houdini update --check` (read-only).** Wire resolve + compare + the dry-run
  messages and `--json` output. Zero on-disk mutation — safe to ship and dogfood first.
- **Phase 3 · `houdini update` (the mutation).** Implement design (a): fetch the per-tag
  `install.sh`, delegate the verified install, capture exit status, print success/failure. Solve
  login-item neutrality CLI-side (§8). Handle the running-app + PATH messages (§7).
- **Phase 4 · Owned-file cleanup.** Implement the manifest-scoped cleanup (§5.4): overwrite-in-
  place is the norm; add detection+confirmation for legacy/non-standard copies; add the optional
  pre-stash/restore rollback hardening. Guard: cleanup only after a `0` install exit.
- **Phase 5 · Verify + docs.** Manual end-to-end on a real machine across the §7 matrix
  (evidence = pasted terminal output per CLAUDE.md). Update `README.md` (mention `houdini update`),
  `BACKLOG.md` P4 → done, and add/patch `RELEASE.md`. Re-confirm no credential is touched and no
  installer guarantee regressed. Consider whether the menu-bar "Check for updates" surface
  (BACKLOG P4 "decide the surface") is a follow-on slice or out of scope for v1 (recommend: CLI
  first, menu-bar item later).

---

## 10. Open questions / decisions for the audit

1. **CLI vs. menu-bar surface (P4 asks).** Ship **CLI `houdini update` first**; add a menu-bar
   "Check for updates…" later? (Recommendation: **yes, CLI-first**; menu-bar is a thin follow-on
   that can call the same code or shell the CLI.) — *decide.*
2. **Version source injection.** Should the CLI's version be **injected from the git tag** during
   `release.yml` (single source of truth, matches the app bundle), or hard-coded and bumped like
   `Info.plist`? (Recommendation: **inject from the tag**.) — *decide.*
3. **`--check` default cadence.** Purely on-demand (only when the user runs it), or a **passive
   "update available" nudge** on normal `houdini`/app runs? (Note: any passive check is a periodic
   network call — keep it opt-in and telemetry-free; recommendation: **on-demand only for v1**.) —
   *decide.*
4. **Explicit-version policy under ADR-010.** Confirm we're fine that `houdini update <old>`
   usually 404s because old tags are pruned, and that the clean error message is the intended UX.
   (Recommendation: **yes** — pruning is the blessed model; document it in the error.) — *confirm.*
5. **Installer parameterization.** Keep design (a)'s **fetch-per-tag installer** approach (no
   installer edit, no gate), or eventually add `HOUDINI_TAG` to `install.sh` (a 🔴 gated
   one-liner)? (Recommendation: **fetch-per-tag; do not edit the installer**.) — *confirm.*
6. **Rollback depth for v1.** Is the installer's own `die`-on-failure enough, or do we add the
   optional **pre-stash/restore of `Houdini.app`** in v1? (Recommendation: **add the pre-stash**
   — cheap, gives rollback-grade safety without duplicating verify logic.) — *decide.*
7. **`RELEASE.md` gap.** ADR-006/010 reference a `RELEASE.md` that **doesn't exist**. Create it as
   part of P4 (the update UX leans on the release/prune procedure), or track separately? —
   *decide.*
8. **Running-app auto-relaunch.** v1 prints "restart Houdini"; do we later offer to **quit +
   relaunch** the app automatically? (Recommendation: **message-only for v1**.) — *decide.*
9. **Downgrade allowance.** Permit explicit downgrades at all, or restrict `update` to
   forward-only + "reinstall latest"? (Recommendation: **allow explicit `<version>` including
   downgrade when the tag exists**, since it's opt-in and honest.) — *decide.*

---

## 11. Sources

Repo (verified this pass):
- `install.sh` (pinned tag, download, SHA-256 verify, no-`sudo` install, quarantine strip,
  offered login item, idempotence).
- `.github/workflows/release.yml` (tag → build → 3 assets + `SHASUMS256.txt`).
- `core/Sources/houdini/main.swift` (current CLI: no subcommands, no `--version`).
- `apps/menubar/Info.plist` (`CFBundleShortVersionString = 0.4.0`).
- `apps/menubar/Sources/Houdini/Main.swift` (app-side `--register/--unregister-login-item`).
- `README.md`, `CONTEXT.md`, `BACKLOG.md` (P4), `DECISIONS.md` (ADR-006, ADR-010), `CLAUDE.md`
  ("installer integrity is sacred"; gated actions; model routing).

Web (safe CLI self-update patterns — light survey, July 2026):
- GitHub CLI — immutable releases + build provenance / self-verify:
  https://github.com/cli/cli · https://cli.github.com/manual/gh_release
- rustup self-update system (`--self-replace`, transactional `MoveAll`, running-binary swap):
  https://deepwiki.com/rust-lang/rustup/4-self-update-system ·
  https://github.com/rust-lang/rustup/blob/main/src/cli/self_update.rs
- `self_update` crate (signature verification + atomic replacement for Rust binaries):
  https://github.com/jaemk/self_update
- Atomic swap / verify-before-install (minisign verify + atomic swap example; Sparkle safe-swap):
  https://github.com/santhsecurity/keyhog ·
  https://github.com/sparkle-project/Sparkle/pull/2593
- Atomic rename / `os.replace` temp-file-then-rename semantics:
  https://alexwlchan.net/2019/atomic-cross-filesystem-moves-in-python/ ·
  https://zetcode.com/python/os-replace/
- Homebrew cleanup of old versions on upgrade + `--dry-run`:
  https://docs.brew.sh/Manpage · https://docs.brew.sh/FAQ
- Update-command UX (installed vs. latest, "already up to date", dry-run):
  https://learn.microsoft.com/en-us/cli/azure/update-azure-cli ·
  https://developer.wordpress.org/cli/commands/core/check-update/
