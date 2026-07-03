# 06 — macOS Widget: UI/UX + Architecture Spec (REVISED BY AUDIT 2026-07-03)

> **Status: AUDIT-REVISED.** The 2026-07-03 impartial audit verified this spec against the
> repo (21 grounding-claim clusters re-derived; 17 hold, 4 wrong) and against primary Apple
> sources + same-category precedent. **The §3 recommendation is overturned: ratify the
> spec's own fallback — "Option A hardened" (the NSPanel is the desktop surface for v1;
> WidgetKit is deferred), recorded as ADR-013.** Read the "AUDIT REVISION" section below
> before the original body; where the body conflicts with it, the revision wins.

---

## AUDIT REVISION (2026-07-03) — corrections, decision, and answered questions

### R1. The §3 premise is factually wrong — and the decision gets *easier*, not harder

The spec's stated reason to revisit ("macOS Tahoe 26 makes WidgetKit widgets first-class
desktop citizens … that capability did not exist when ADR-002 and the NSPanel were written")
is **false**: drag-to-desktop WidgetKit placement and App-Intent interactivity shipped in
**macOS 14 Sonoma (September 2023)** — Houdini's own platform floor, ~3 years before ADR-002
(git: 2026-06-16). Tahoe's real deltas are Liquid Glass rendering, the Light/Dark/Tinted/Clear
widget styles (accented rendering), ControlWidget in Control Center/menu bar, and iPhone Live
Activities on the Mac. (Sources: Apple Newsroom Sonoma 2023; WWDC25 session 278; HIG Widgets,
updated 2025-12-16. The error likely came from §14's low-authority blog sources — replace
`macos-tahoe.com` et al. with the primary sources listed in R6.)

### R2. The distribution gate is a CONFIRMED HARD BLOCKER, not a cost (this decides §3)

Three independent, evidence-backed gates stack against Options B and C under today's
ADR-006 distribution (ad-hoc-signed SPM executable via install.sh):

1. **App Groups require an Apple-issued Team ID on macOS 15+.** Apple DTS (Quinn), forums
   thread 776087, on ad-hoc signing + app-group containers: *"no, this won't work. App group
   container protection, introduced in macOS 15, is based on your Team ID."* Prompt-free
   access requires MAS/TestFlight/Team-ID-prefixed group/provisioning profile (thread 721701).
2. **A Mac widget .appex must be sandboxed to appear in the gallery** (threads 685166,
   718589) — and a sandboxed extension without an App Group cannot read the host's snapshot.
   The spec's §9 "app fetches, widget reads cache" model *structurally requires* the App
   Group, which requires the Team ID.
3. **SwiftPM cannot produce a working .appex at all** — no extension target type exists, and
   on macOS 26 a hand-wrapped SPM executable posing as an .appex exits before serving widget
   descriptors (ExtensionFoundation no longer supplies the blocking runloop). A real Xcode
   app-extension target is required, breaking the repo's no-.xcodeproj/build.sh convention.
   Same-category public precedent for all three: **CodexBar** issues #318, #533, #1095 (a
   menu-bar AI-usage app that hit exactly these walls even with Developer-ID signing but a
   non-TeamID-prefixed group).

Also: Option C's effort was underpriced ("Medium") — HoudiniUI extraction + an Xcode project
+ entitlement/signing changes to the sacred install path + likely the $99 program is **L,
High risk, sign-off-gated**.

### R3. The decision (feeds ADR-013)

**Adopt "Option A hardened" for v1** — the spec's own fallback, promoted to primary:

- The **NSPanel desktop widget is the desktop surface**, and it is a *legitimate long-term*
  pattern, not a stopgap: NSPanel/.nonactivatingPanel is current, supported AppKit API with
  an active ecosystem, and it is the only surface that can do ~60s refresh + in-process
  sign-in + free placement. Finish **P2 slice 3** (verify against real Pro/Max data) on it.
- **WidgetKit is deferred, bundled with the Developer-Program decision** (same trigger as
  iOS/notarized DMG — ADR-006's future option). When that bundle is ever taken: use an
  iOS-style `group.*` ID authorized via a macOS provisioning profile (supported since
  Feb 2025), a real Xcode extension target, and study CodexBar #318/#533/#1095 first.
- **Write ADR-013** recording: NSPanel-in-host-process is the desktop-widget architecture
  (why: 60s freshness, toolchain, signing); WidgetKit is deferred with the three gates above;
  revise **ADR-002/003 in place** (Übersicht is gone; the NC widget is *planned, not
  shipped*; the menu bar app is the sole 60s surface). Decide `apps/widget/`: **recommend
  delete** (git history + ADR-013 preserve the intent) or make its README say "no target
  exists yet".
- Independent of A/B/C, two spec items are justified NOW by repo evidence: **unify the
  threshold truth** (the site /guide teaches 75/90 vs the app's 60/85 — drift is corrective,
  not preventive) and **fix ARCHITECTURE.md's App-Group fiction** (PND-MB-02/PND-DOC-03).

### R4. Detail corrections to the body (apply when implementing)

- §3: "threshold scale defined in three places" → cutoffs exist in **two** code places
  (menubar `Thresholds`, iOS `Theme`); the site defines only the three **colors** — and the
  color *values* already diverge (system `.green/.orange/.red` vs `#34d399/#f5a623/#f2555f`).
- §5c: the popover list is **`rowMetrics`**, not `secondaryMetrics` (UsagePopover.swift:207).
- §4: `accessoryCircular` is **not** in the iOS widget's supportedFamilies
  (HoudiniWidget.swift:127-130 ships only accessoryRectangular + accessoryInline); the HIG
  lists **no accessory family for macOS** at all; `systemExtraLarge` *is* supported on the
  Mac desktop/NC (defer it on data-density grounds, not platform grounds). The §4 pt sizes
  are iOS-flavored — validate against real macOS canvases (~170/364 pt classes).
- §5 footnote: `Text(updated, style: .relative)` renders a counting interval ("15 sec"),
  never the string "just now".
- §6a/§10: **color independence is mandatory on macOS 14/15 too**, not just Tahoe accented
  mode — Sonoma-era desktop widgets desaturate to monochrome when an app window has focus,
  and the "Dim widgets" setting renders them monochrome. Arc-fill + numeral must carry
  severity with zero hue on the *minimum* OS.
- §9: the "~15 min floor" is two numbers — ~5 min hard entry spacing; 15–60 min budgeted
  steady state (40–70 reloads/day). The budget-exemption list is broader than stated
  (animations, locale, Dynamic Type/accessibility changes are also free). The §9.4
  "foreground exemption" likely does **not** help an LSUIElement menu-bar app — don't design
  the freshness story around it. WWDC25 adds push-based widget updates (WidgetPushHandler +
  APNs) — considered and rejected under the no-server guardrail.
- §9/§3: the panel cadence is a **user setting** (30/60/120s, default 60 —
  AppSettings.allowedIntervals), not a fixed 60s constant; and ADR-012 freezes *auth
  expansion*, not the poll interval.
- §10: HIG documents widget Dynamic Type for iOS/iPadOS/visionOS, **not macOS** — keep
  `scaledFont` for shared views, but verify against the Mac text-size setting, not iOS ranges.
- Post-spec event: **WWDC26 (June 2026) announced macOS 27 "Golden Gate"** with WidgetKit
  styling/App-Intents customization changes — re-verify visuals against Apple's WWDC26
  sessions before any future WidgetKit implementation.

### R5. §12 open questions — answered

| Q | Answer (evidence in 02 + R1–R4) |
|---|---|
| 12.1 Ship WidgetKit now? | **No — defer** (hard blocker, R2). Record in ADR-013. |
| 12.2 Both surfaces discoverable? | Moot until WidgetKit unfreezes. The status quo is already right: the panel is opt-in (off by default — `AppSettings.swift:93` registers no default). |
| 12.3 Refresh button on WidgetKit? | **Omit on all families**, tap-to-open only (ADR-002 honesty). |
| 12.4 De-duplicate design source of truth? | **Yes, rescoped** (R4 bullet 1): fix the live site/app contradiction now; full unification when a third consumer exists. |
| 12.5 Extract HoudiniUI? | **Only as step 1 of an actually-greenlit WidgetKit unit** — speculative now. |
| 12.6 Accented-mode fidelity? | Needs owner + real Tahoe hardware; the shipped gauge already encodes severity redundantly (arc + numeral), so the approach is consistent. |
| 12.7 Control Center + accessory families? | **Out** — and there is even less precedent than claimed (no accessoryCircular on iOS; no accessory families on macOS at all). |
| 12.8 systemExtraLarge deferred? | **Yes** — on data-density grounds (it *is* platform-supported on Mac). |
| 12.9 Gallery naming? | Reuse the iOS copy verbatim: "Claude usage" / "Your tightest Claude limit, updated a few times an hour." (HoudiniWidget.swift:125-126 — satisfies ADR-010/011 + ADR-002.) |

### R6. Sources added/replaced by the audit

Replace the §14 secondary blogs (`macos-tahoe.com`, `appleworld.today`, dev.to Liquid-Glass
piece) with: Apple Newsroom — macOS Sonoma (June 2023, desktop+interactive widgets); Apple
HIG Widgets (updated 2025-12-16); Apple Support — Add and customize widgets on Mac (Dim
widgets/monochrome); Apple DevForums **776087** (DTS: ad-hoc + App Groups verdict), **721701**
(macOS 15 container-protection rules; Feb 2025 `group.*` support), **685166**/**718589**
(sandbox requirement for Mac .appex); CodexBar issues **#318/#533/#1095**; WWDC25 session 278;
Engadget/Apple WWDC26 hub (macOS 27 "Golden Gate" — flag for re-audit).
>
> Author context: Houdini monorepo, `apps/menubar` (flagship, live v0.4.0), `apps/widget`
> (README-only WidgetKit placeholder), `apps/ios` (WidgetKit scaffold), `core/FetcherCore`
> (shared data). Research current as of **July 2026** against macOS Tahoe 26 / the Liquid
> Glass design language and the WWDC25 WidgetKit updates. See **§13 Sources**.

---

## 1. Purpose & scope

**Purpose.** Define what a *professional, Apple-native-inspired* macOS widget for Houdini
should look like and how it should be built, so the audit can pick a direction before any
implementation unit is opened. Houdini's job is to make Claude (Pro/Max) usage and spend
**glanceable** — the 5-hour window, the weekly window, model-specific weekly limits, reset
timers, and any extra-usage dollar overage — with *zero clutter* and a *calm, sophisticated*
finish that reads as a native part of macOS.

**In scope**
- The **on-desktop surface**: today's bespoke `DesktopWidgetView` in an `NSPanel`, and the
  question of whether/how it should become (or coexist with) a true WidgetKit widget now
  that macOS Tahoe 26 makes WidgetKit widgets first-class desktop citizens.
- The **WidgetKit Notification Center / desktop widget** (`apps/widget`), currently a
  README-only placeholder capped at ~15 min by ADR-002.
- Widget families/sizes, per-size information hierarchy, visual language, states,
  interactivity (App Intents), refresh strategy, accessibility, and a component-reuse map.

**Out of scope (this pass)**
- iOS widgets (`apps/ios/HoudiniWidget`) except as a **reuse precedent** — the same
  `SharedSnapshot` App-Group pattern and `Theme.color(forPct:)` thresholds apply, and the
  macOS WidgetKit widget is its twin.
- Any change to the Claude auth posture. **ADR-012 freezes** subscription-auth expansion;
  a user with no Claude Code credential is out of scope by decision. The widget only ever
  *reads* a cached snapshot the app already produced.
- Adding a second provider's UI. The switcher lives in the app's Settings (ADR-011), never
  on a widget or the site. The design must not *preclude* a future provider, but building it
  is not this unit.
- Site copy/branding. ADR-010/011 forbid separately branding the menu bar vs the desktop
  widget and forbid "coming soon" surfaces.

---

## 2. Principles

1. **Apple-native feel, not a facsimile.** Adopt the current system material (**Liquid
   Glass** on macOS 26), system typography (SF Rounded for numerals, as the app already
   uses), continuous-corner squircles, and — critically — **support the system's own
   Light / Dark / Tinted / Clear widget styles** so the widget "melts into the wallpaper"
   rather than sitting on top of it. A widget that ignores the user's chosen widget style
   looks foreign on Tahoe.
2. **Glanceable first.** The single most useful number (the *tightest* limit) must be
   legible from across the room. Progressive disclosure by size: a small widget answers
   "am I close to a limit?" in one glance; larger sizes add the *why* and the *when*.
3. **Calm & honest.** No spinners, no fake `0%`, no implied real-time. Green/amber/red are
   *functional* threshold signals, not decoration. Copy never over-promises freshness
   ("Updated 6 min ago", never "live") — this is the ADR-002 honesty contract.
4. **Sophisticated restraint.** Every element earns its place (site-grade minimalism
   applied to the widget). Prefer one hero figure + supporting context over a dense
   dashboard. Motion is subtle and always Reduce-Motion-gated.
5. **One visual language across surfaces.** The widget must read as the same product as the
   menu bar popover and the desktop panel — same thresholds, same ranking of which windows
   are "hero", same rounding family. `Theme` is the single source of truth (see §11).

---

## 3. The core decision to surface: WidgetKit widget vs the existing NSPanel — or both?

> **⚠ AUDIT CORRECTION (2026-07-03):** the premise below is **factually wrong** — desktop
> WidgetKit placement shipped in **macOS 14 Sonoma (2023)**, before this repo existed; Tahoe
> only added styling (Liquid Glass, Tinted/Clear) and Controls. And the "distribution gate"
> caveat further down is a **confirmed hard blocker** (Team-ID-based App-Group protection on
> macOS 15+; sandboxed-.appex gallery requirement; SwiftPM cannot build an .appex). The
> ratified decision is **Option A hardened** — see the AUDIT REVISION section (R1–R3).

This is the central question for the audit. Houdini today ships a **bespoke on-desktop
panel** (`DesktopWidgetView` inside a non-activating `NSPanel`, `DesktopWidgetController`),
refreshing on the app's ~60 s timer (`UsageModel.refreshInterval = 60`). Separately,
`apps/widget` is a **README-only WidgetKit placeholder** intended as a glanceable ~15-min
Notification Center surface (ADR-002). macOS Tahoe 26 changes the backdrop: **WidgetKit
widgets are now first-class desktop citizens** — users right-click the desktop → *Edit
Widgets* → drag any widget (small/medium/large) straight onto the wallpaper, rendered in
Liquid Glass with Light/Dark/Tinted/Clear styles. That capability did not exist when ADR-002
and the NSPanel were written; it is the reason to revisit. *(← wrong; see correction above)*

### The tension (unchanged fundamentals)
- **NSPanel** can refresh at **~60 s** (or faster), sits exactly where the user drags it,
  can host arbitrary SwiftUI/AppKit, and shows a live "Connect Claude" button that runs
  in-process. But it is **not** a real macOS widget: it doesn't appear in *Edit Widgets*,
  doesn't inherit the system's Tinted/Clear styling, doesn't live in Notification Center,
  and is Houdini-bespoke furniture the user must learn.
- **WidgetKit** *is* the native surface: it appears in the widget gallery, lives on the
  desktop **and** in Notification Center, inherits Liquid Glass + the user's widget style
  for free, and (Tahoe) supports App-Intent interactivity. But it is **budget-capped**:
  Apple grants a frequently-viewed widget ~**40–70 timeline reloads/day** (≈ one every
  **15–60 min**), minimum entry spacing ~5 min, and even the host app's
  `reloadAllTimelines()` is throttled/deferred. **This is a hard platform constraint, not a
  bug** (ADR-002) — a WidgetKit widget can never be the 60 s experience.

### Options

| Option | Refresh | Native placement (Edit Widgets, NC, Tinted/Clear) | In-widget interactivity | ADR-002 fit | Effort / risk |
|---|---|---|---|---|---|
| **A. NSPanel only** (today) | ✅ ~60 s | ❌ bespoke; no gallery/NC/system style | ✅ full in-process (buttons, sign-in) | n/a (not a WidgetKit widget) | Lowest — already shipped |
| **B. WidgetKit only** | ❌ ~15 min cap | ✅ fully native | ⚠️ App Intents only (no arbitrary code) | ✅ honest ~15-min | Highest — needs Apple Developer Program + Xcode target + App Group; retires a working surface |
| **C. Both, complementary** *(recommended)* | Panel ~60 s **+** WidgetKit ~15 min | ✅ (via the WidgetKit half) | ✅ panel; ⚠️ App-Intent on WidgetKit | ✅ each honest about its own cadence | Medium — build the WidgetKit widget *alongside* the panel, sharing FetcherCore + Theme + the gauge |

### Recommendation (for the audit to ratify)
**Option C — build the WidgetKit widget as the *native, glanceable* surface, keep the
NSPanel as the *live, precise* surface, and let them share everything below the view layer.**

Rationale:
- The two surfaces answer **different jobs**. The panel is for a user who wants a
  *live-ish* readout parked on their desktop and is willing to run Houdini as furniture
  (60 s, a real sign-in button). The WidgetKit widget is for the user who lives in the
  system widget gallery / Notification Center and expects Houdini to behave like every other
  Tahoe widget (Tinted/Clear styling, drag-from-gallery, glanceable). Neither fully replaces
  the other; forcing one loses real value.
- The **honesty contract is preserved per-surface**: the panel legitimately says
  "Updated just now"; the WidgetKit widget says "Updated 12 min ago" and is *marketed*
  (ADR-002) as glanceable, not live. Same data source, different truthful copy.
- Cost is contained because **the data layer and most of the view layer are already shared**
  (`FetcherCore.UsageSnapshot`, `WidgetRingGauge`, `Theme`, `Thresholds`, the ranking
  helpers). The WidgetKit widget is largely a re-host of components that already exist.

**Caveats the audit must weigh (do not let this recommendation paper over them):**
- **ADR-010 single-surface hygiene** says a feature is "either real and shown, or absent",
  and ADR-002 keeps the NC widget **unadvertised**. Shipping *two* desktop-usage surfaces
  risks looking like clutter/duplication to a new user. Mitigation: the WidgetKit widget is
  the one that shows up natively in *Edit Widgets*; the panel is opt-in via Settings (as it
  is today). But the audit should decide whether Houdini wants **both discoverable**, or the
  WidgetKit widget as the default with the panel demoted to a power-user toggle.
- **Distribution gate.** A WidgetKit extension needs an **App Group** + a real Team ID,
  which per `SharedSnapshot.swift` and `apps/ios/PLAN.md` requires enrolling in the **Apple
  Developer Program ($99/yr)** and an Xcode target — the same gate the iOS app hit. Today's
  ad-hoc-signed `install.sh` path (ADR-006) ships an SPM executable with **no** Developer
  Program. **Adding a WidgetKit extension likely forces the notarized/Developer-Program
  path** (or at least an App-Group-capable signed build). This is a real, sign-off-gated
  cost, not a detail — it may be the deciding factor, and it is an **open decision** (§12).
- If the audit judges the distribution cost too high right now, the honest fallback is
  **Option A hardened** — keep polishing the NSPanel (P2), and defer WidgetKit until the
  Developer Program is on the table anyway (e.g. when the iOS app or a notarized DMG ships).

The rest of this spec is written so it applies to **both** surfaces: the WidgetKit widget
(new) and the NSPanel (existing), which already share the gauge and tokens.

---

## 4. Target families / sizes

macOS supports these WidgetKit families; Houdini should support the subset that carries a
useful usage story:

| Family | Approx. size | Support? | Role |
|---|---|---|---|
| `systemSmall` | ~150×150 pt | **Yes** | The at-a-glance "tightest limit" ring. The default. |
| `systemMedium` | ~330×150 pt | **Yes** | Two rings (5-hour + Weekly) side by side + reset context. |
| `systemLarge` | ~330×345 pt | **Yes** | All windows (5-hour, Weekly, model-weekly) + extra-usage $ + resets. |
| `systemExtraLarge` | ~680×345 pt | **No (defer)** | iPad-oriented; overkill for this data density. Revisit only if a multi-provider board emerges. |
| `accessoryRectangular` / `accessoryInline` / `accessoryCircular` | Lock Screen / Control Center | **Optional/defer on macOS** | These are the iOS twins (already in `apps/ios`). On macOS they surface in Control Center-adjacent contexts; low priority — the desktop families carry the product. |

The **NSPanel** is not a "family" — it is freely resizable (card default **280×200**, min
**220×150**, max **480×360**, per `DesktopWidgetController`). Its two existing breakpoints
map cleanly onto the WidgetKit families:
- Panel **compact** (`<260 pt`) ≈ `systemSmall` behavior (one hero ring + spend + one-liner).
- Panel **regular** (`≥260 pt`) ≈ `systemMedium`/`systemLarge` behavior (two rings + spend).

This mapping means the WidgetKit views can be **derived from the existing panel layouts**
rather than designed from scratch.

**Control Center control (`ControlWidget`) — flagged, deferred.** Tahoe adds user-placeable
Control Center controls (macOS 26 / watchOS 26). A Houdini control could be a one-tap
"tightest limit %" chip or an "open Houdini" button. It's a *nice-to-have* native touch but
is **not** part of the core widget story; list it as a future idea (§12), not a deliverable.

---

## 5. Per-size layout wireframes (information hierarchy)

Notation: `[ ]` = a region; `◕` = ¾-ring gauge (the existing `WidgetRingGauge`, 270° sweep,
gap centered at bottom); `▁▁` = thin threshold-colored progress bar; text in quotes is
literal copy. All numerals SF Rounded, `monospacedDigit`. "Tightest" = highest-% window.

### 5a. `systemSmall` (and panel *compact*)
Answers: **"Am I close to a limit?"** One hero ring — the *tightest percentage window* —
with its reset beneath. Header is minimal (wordmark + status). If an extra-usage $ overage
exists and is the tightest signal, the hero becomes the $ figure instead.

```
┌───────────────────────────┐
│ Houdini            ●       │  ← wordmark (brand gradient) + status dot
│                            │
│           ◕                │  ← hero ¾-ring: tightest window
│         ┌────┐             │
│         │ 42%│             │  ← hero numeral (threshold color) + tiny label
│         │ 5H │             │     "5H" / "WEEKLY" / "OPUS"
│         └────┘             │
│      resets in 2h 14m      │  ← relative reset (secondary)
│                            │
│ Updated 8 min ago          │  ← honesty footer (WidgetKit) / "Updated just now" (panel)
└───────────────────────────┘
```
Hierarchy: **numeral (1) → ring color (1) → window label (2) → reset (2) → updated (3)**.
Everything but the numeral+ring is deferrable context.

### 5b. `systemMedium` (and panel *regular*, narrow)
Answers: **"How do my two main limits look, and when do they reset?"** The two ranked hero
windows — **5-hour** and **Weekly** — as side-by-side rings; extra-usage $ as a compact
block beneath if present.

```
┌─────────────────────────────────────────────┐
│ Houdini                                 ●     │
│                                               │
│        ◕                    ◕                 │  ← two ¾-rings (5-hour | Weekly)
│      ┌────┐               ┌────┐              │
│      │ 42%│               │ 8% │              │
│      │ 5H │               │WKLY│              │
│      └────┘               └────┘              │
│   resets in 2h14m       resets in 5d 3h       │
│                                               │
│  EXTRA USAGE   $12 / $100   ▁▁▁▁░░░░░░░░       │  ← spend block (only if overage exists)
│                                               │
│ Updated 8 min ago                             │
└─────────────────────────────────────────────┘
```
Hierarchy: **two ring numerals (1) → colors (1) → labels/resets (2) → spend (2, conditional)
→ updated (3)**. This is essentially today's panel `regularBody`.

### 5c. `systemLarge` (and panel *regular*, tall)
Answers: **"Show me everything without opening the app."** The two hero rings on top; the
remaining windows (model-specific weekly, e.g. Opus/Sonnet) + extra-usage $ as full metric
rows beneath — this is the popover's `secondaryMetrics` list.

```
┌─────────────────────────────────────────────┐
│ Houdini                                 ●     │
│                                               │
│        ◕                    ◕                 │  ← 5-hour | Weekly rings (hero)
│      │ 42%│               │ 8% │              │
│      │ 5H │               │WKLY│              │
│   resets in 2h14m       resets in 5d 3h       │
│ ───────────────────────────────────────────── │  ← hairline divider
│  Opus weekly        61%   ▁▁▁▁▁▁▁░░░░  5d 3h  │  ← MetricRow (reused)
│  Sonnet weekly      12%   ▁▁░░░░░░░░░░  5d 3h  │
│  Extra usage    $12 / $100  ▁▁▁░░░░░░░░        │
│                                               │
│ Updated 8 min ago                             │
└─────────────────────────────────────────────┘
```
Hierarchy: **hero rings (1) → secondary rows top-to-bottom by tightness (2) → updated (3)**.
Row order follows `rankedRingWindows` then `dollarOverage`, exactly as the popover picks.

**Which limits show at which size (summary):**

| Metric | small | medium | large | panel compact | panel regular |
|---|---|---|---|---|---|
| Tightest window (hero ring) | ✅ | ✅ (as 5-hour) | ✅ | ✅ | ✅ |
| Weekly window (2nd ring) | — | ✅ | ✅ | one-line secondary | ✅ |
| Model-weekly (Opus/Sonnet) | — | — | ✅ rows | — | popover rows |
| Extra-usage $ overage | if tightest | ✅ compact | ✅ row | ✅ | ✅ |
| Reset timers | hero only | both rings | all | hero | all |
| "Updated X ago" | ✅ | ✅ | ✅ | "just now"* | "just now"* |

\* The panel shows `Text(updated, style: .relative)` which reads "just now" at 60 s cadence.

---

## 6. Visual language

### 6a. Materials / vibrancy (map to current macOS)
- **macOS 26 (Tahoe) — Liquid Glass.** The system now renders desktop and Notification
  Center widgets on **Liquid Glass** — a translucent material that refracts the wallpaper
  and carries a subtle shimmer, with user-selectable **Light / Dark / Tinted / Clear**
  styles. The correct native behavior is to **let the system supply the background** via
  `containerBackground(_:for: .widget)` and **not** paint an opaque card that fights the
  glass. Houdini's `GlassCardBackground` already has the right instinct — it prefers
  `Color.clear.glassEffect(in:)` on `#available(macOS 26, *)` and falls back to
  `NSVisualEffectView(.hudWindow, .behindWindow)` on 14/15. For the **WidgetKit** widget,
  the analog is: use the system container background and keep Houdini's violet wash *very*
  light (or drop it in accented/clear modes — see 6b).
- **Accented / Tinted / Clear rendering (WWDC25).** When the user picks a Tinted or Clear
  widget style, the system renders the widget in **accented rendering mode**: content is
  flattened to a white/tinted mask and the background is replaced by the themed glass/tint.
  Houdini **must** read the `\.widgetRenderingMode` environment value and adapt:
  - In `.fullColor` — show the green/amber/red threshold colors as designed.
  - In `.accented` — the OS tints everything one color, so **threshold color is lost**.
    Compensate by encoding severity in a *non-color* channel: the **ring fill fraction**
    already does this (a nearly-full red ring is still a nearly-full ring when tinted), and
    the numeral ("92%") still reads. Use `widgetAccentedRenderingMode` on any glyphs so they
    render sensibly. **Do not rely on hue alone for the threshold signal** — this is both an
    accented-mode and an accessibility requirement (§10).
- **macOS 14/15 (NSPanel today).** Behind-window `NSVisualEffectView` blur + the violet
  wash + a 1px gradient border is the premium glass base and should remain the panel's look
  on pre-26 systems.

### 6b. Color + thresholds
- **Threshold scale (functional, shared):** `<60%` green, `60–85%` amber, `>85%` red —
  defined once in `Thresholds.barColor` and mirrored by `Theme.color(forPct:)` (iOS) and the
  site tokens. **Reuse verbatim.** Do not introduce a new scale.
- **Brand accent:** violet `#8B5CF6` → magenta `#D946EF` gradient, used *only* for the
  wordmark and the "Connect Claude" wand glyph — never for threshold data. Keep this
  discipline (Theme comment: brand accent is separate from functional colors).
- **Accented-mode caveat (above):** when the system tints the widget, thresholds collapse to
  one hue — rely on ring fill + numeral, not color, to carry severity.
- **Contrast:** the glass card forces `colorScheme: .dark` so light text stays AA over a
  light wallpaper; secondary text uses the AA-tuned `Theme.Colors.secondaryText` (brighter
  than system `.secondary`), lifting further under Increase Contrast. Preserve this.

### 6c. Typography
- **Numerals:** `SF Rounded`, bold, `monospacedDigit`, sized *relative to the ring diameter*
  (`diameter * 0.27`) so they never clip — with `minimumScaleFactor(0.7)` as a floor. Same
  for the $ hero.
- **Labels/resets/updated:** system font at tuned point sizes routed through `scaledFont`
  (a `@ScaledMetric` wrapper) so they **honor Dynamic Type** while resting at the designed
  size. Tiny uppercase labels use `microTracking` (0.5) letter-spacing. **Reuse `scaledFont`
  and `glassSecondaryText` verbatim** — they already solve the Dynamic-Type + AA problem for
  the panel/popover.
- **WidgetKit note:** WidgetKit strongly favors system fonts and Dynamic Type; the existing
  approach is already correct for it.

### 6d. Gauges
- **Primary gauge = the existing `WidgetRingGauge`** — a 270° ¾-ring, gap centered at the
  bottom, fill grows clockwise, track at white@8%, fill on the threshold scale, hero numeral
  + tiny window label centered, reset beneath. This is the signature Houdini glyph; **reuse
  it** in the WidgetKit widget so all surfaces read identically.
  - *WidgetKit tuning:* on `systemSmall` the ring should be the dominant element (~0.55 of
    the height); on `systemMedium` two rings share the width. The gauge already derives
    `lineWidth` and font from `diameter`, so it scales down cleanly.
- **Secondary gauge = `ProgressBar`** (thin threshold-colored capsule) for spend/budget and
  the `MetricRow` list on `systemLarge`. Reuse.
- **Data-viz for tiny surfaces (research-backed):** show **one KPI per gauge**, don't
  clutter; encode the value in **arc length** (glanceable) with color as a *secondary*
  reinforcement (never the sole channel); keep labels short; ensure the number is always
  present for VoiceOver/accented mode. The ¾-ring + centered numeral pattern is exactly the
  recommended `accessoryCircular`-style approach scaled up.

---

## 7. States

The widget must never flash empty or fake a value. Five states (the panel already
implements all of them in `DesktopWidgetView`; the WidgetKit widget must mirror them from
the cached snapshot):

| State | Trigger | Presentation |
|---|---|---|
| **Loading** | First run, no data yet | Track-only ring skeleton (`RingPairSkeleton`), calm opacity pulse (Reduce-Motion gated). **No spinner.** VoiceOver: "Loading usage". *(WidgetKit: use the `placeholder(in:)` redacted view — the OS blurs it; keep it structurally identical.)* |
| **Needs-auth** | No Claude credential (`state == .signedOut`) | `NeedsAuthView`: wand glyph + "Connect Claude" + one line. **On the panel**, a live sign-in button (in-process). **On WidgetKit**, no in-process sign-in — show "Open Houdini to sign in"; tapping the widget deep-links to the app (WidgetKit can't run the WebView login). |
| **Error** | Fetch failed but cached data exists | Keep last-good metrics visible; show the **stale chip** ("Showing last value", `arrow.triangle.2.circlepath`). Never blank the gauges. |
| **Error, no cache** | Fetch failed, nothing cached | `ErrorStateView`: "Can't read usage" + the token-safe reason (e.g. "Claude.ai session expired — sign in again"). No raw tokens ever (guaranteed by `UsageModel.message(for:)`). |
| **Empty** | Authed, fetch OK, zero metrics | "No usage metrics available." (rare; a real account has windows). |
| **Stale** (freshness, orthogonal) | Last update older than a threshold | Footer flips from "Updated 8 min ago" to the stale chip. On WidgetKit this is expected (~15 min cadence) so the threshold should be generous (e.g. only chip if > ~30–45 min or if the last fetch errored). |

**WidgetKit-specific:** the widget reads `SharedSnapshot.read()` (the App-Group-cached
`UsageSnapshot`). If the app has *never* fetched, the snapshot is `nil` → treat as
needs-auth/"open Houdini". The widget must **not** attempt a network fetch itself (no
credentials in the extension; keep the security boundary — see §9/§11).

---

## 8. Interactivity (App Intents)

WidgetKit interactivity on macOS 14+ is limited to **`Button`/`Toggle` backed by an
`AppIntent`** — the widget process can't run arbitrary closures, only fire an intent the
system executes. Tapping the widget body (no button) launches the app via
`widgetURL(_:)`/deep link.

| Interaction | Feasible on WidgetKit? | Feasible on NSPanel? | Notes |
|---|---|---|---|
| **Open the app** (tap body) | ✅ `widgetURL` / `Link` deep-link | n/a (panel *is* the app) | Default action; also the needs-auth escape hatch. |
| **Refresh now** (button) | ⚠️ *Technically* via an `AppIntent` that re-reads the cached snapshot and calls `reloadTimelines`. **But** a real network refresh needs the app; the intent can only *nudge*. And App-Intent invocations that trigger reloads still ultimately answer to the budget for *network* work. Recommend **omitting** a "Refresh" button on the small/medium widget (it implies liveness ADR-002 says we don't have); optionally offer it on `systemLarge` wired to "wake the app to fetch". | ✅ real 60 s timer + could add a manual refresh | On WidgetKit, prefer *honesty* (no misleading live-refresh button) over a button that can't truly refresh. **Open decision (§12).** |
| **Switch provider** (future) | ⚠️ Possible as a `Toggle`/config intent once a 2nd provider exists — but ADR-011 puts the switcher in **app Settings**, and a dead toggle violates ADR-010. **Defer** until a real 2nd provider ships; then reconsider a `WidgetConfigurationIntent` for per-instance provider choice. | ✅ (would read app Settings) | Not this unit. |
| **Sign in** | ❌ WidgetKit can't host the WebView/OAuth flow → deep-link to app. | ✅ in-process button (exists) | Security boundary: login stays in the app. |

**Recommendation:** ship the WidgetKit widget **read-only + tap-to-open** first. Treat any
in-widget button as an *additive*, clearly-honest affordance, decided after the audit. The
NSPanel keeps its live in-process button.

---

## 9. Refresh / timeline strategy (within Apple's budget)

**The reconciliation problem.** Three cadences are in play:
- **NSPanel:** ~**60 s** (`UsageModel` timer). Legitimate — it's the app polling in-process.
- **WidgetKit:** **~15 min effective**, hard-capped by Apple's ~40–70 reloads/day budget,
  ~5 min minimum entry spacing, and throttled `reloadTimelines()` (ADR-002).
- **Anthropic endpoints:** polled by the *app*, ~60 s (ADR-012 freezes this; no refresh
  token, read-only).

**Strategy (the "app fetches, widget reads cache" model — already scaffolded):**
1. **Only the app fetches.** The menu bar app polls Claude every 60 s (existing `UsageModel`)
   and, on each success, **writes the `UsageSnapshot` to the App Group** via
   `SharedSnapshot.write(...)`. The widget **never** holds a credential or hits the network —
   this preserves the ADR-005 security boundary *and* sidesteps the budget for network work.
2. **The WidgetKit timeline reads the cache.** `getTimeline` returns a single entry built
   from `SharedSnapshot.read()` with `policy: .after(now + ~15 min)` — exactly what the iOS
   `HoudiniProvider` already does. Apple decides the real cadence; honest "Updated X ago"
   copy (from `snapshot.capturedAt`) covers the gap.
3. **Opportunistic freshening.** When the app completes a fetch *and the value changed
   meaningfully* (e.g. a window crossed a threshold, a reset elapsed, or the tightest %
   moved by ≥ some delta), the app calls `WidgetCenter.shared.reloadTimelines(ofKind:)` to
   *nudge* the widget. This is best-effort — the OS may defer it — and must be **rate-limited**
   so we don't burn the budget on noise. Do **not** reload on every 60 s tick.
4. **Foreground exemption.** Reloads triggered while the app is foreground, during an app
   intent, or for animations **don't** count against the budget — useful for making the
   widget feel fresh right after the user interacts with the app, without spending budget.
5. **Timeline shape option:** instead of a single entry, the provider *can* emit a short
   series of **pre-computed future entries** — e.g. entries at each known **reset time** so
   the ring visibly "resets to 0%" at the boundary and the "resets in …" text stays accurate
   between budgeted reloads. This squeezes more perceived freshness out of the same budget
   and is a recommended refinement (relative-time text also updates without a reload).

**Net:** the panel stays genuinely ~60 s; the WidgetKit widget is honestly ~15 min with
smart nudges and reset-boundary entries. Both draw from the same cached `UsageSnapshot`, so
they can never disagree about *what* the numbers are — only about *how fresh* they are, and
each says so truthfully. **This fully respects ADR-002** (no attempt to make WidgetKit do
60 s; marketed as glanceable).

---

## 10. Accessibility spec

Houdini's panel/popover already set a high bar; the WidgetKit widget must match it. Targets:
**WCAG 2.1 AA** (per the project guardrails).

- **VoiceOver.** Every gauge/row is **one combined phrase**, not scattered glyphs. Reuse the
  `A11y` helpers and the gauge's `accessibilityElement(children: .ignore)` +
  `accessibilityLabel`/`accessibilityValue`:
  - Ring → *"Weekly usage, 42 percent, resets in 2h 14m."* (spells out the full window name
    even where the label abbreviates to "WKLY").
  - Spend → *"Extra usage, 12 dollars of 100 dollars."*
  - Status dot → labeled "Status", value "Up to date/Loading/Error/Signed out" (a bare
    colored dot is meaningless to VoiceOver).
  - Wordmark → `.isHeader` so it's a clear card title in the rotor.
  - Decorative glyphs (stale-refresh icon, wand, warning triangle, progress bar) →
    `accessibilityHidden(true)` since the adjacent text carries meaning.
- **Dynamic Type.** All non-numeral text routes through `scaledFont` (scales with the user's
  text size). Ring/$ hero numerals are diameter-derived by design with a `minimumScaleFactor`
  floor so they never clip. *WidgetKit reminder:* widgets should respect Dynamic Type;
  verify large-text sizes don't overflow the small family (fall back to fewer elements).
- **Contrast targets (AA).** Body/secondary text ≥ **4.5:1**; large numerals ≥ **3:1**. The
  dark-forced glass + `secondaryText` tone already clear this; the **Increase Contrast** path
  lifts both the card border and the text (not just the border). In **accented/Tinted**
  WidgetKit mode the system controls contrast, but we must still ensure the numeral + arc
  read without relying on the (now-tinted) hue.
- **Color independence.** The threshold signal must survive color-blindness *and* accented
  mode: it is carried by **arc fill length + the numeral**, with green/amber/red as
  reinforcement only. (Explicitly: never a green-vs-red dot as the *only* cue.)
- **Reduce Motion.** All animation (ring fill, `numericText` transitions, hover lift,
  skeleton pulse) is gated by `\.accessibilityReduceMotion` — value still updates, just
  without the tween. Preserve this in the WidgetKit views.
- **Reduce Transparency.** `GlassCardBackground` swaps to a **flat opaque `#15101F`** card
  (same layout, no blur/wash). For WidgetKit, the system's Reduce-Transparency handling of
  the container background largely covers this, but any Houdini-drawn wash must also drop to
  opaque under `\.accessibilityReduceTransparency`.
- **Hit targets / focus (panel).** Keep visible focus rings and ≥ adequate hit areas on the
  panel's interactive controls (the popover footer already draws a 2px focus ring).

---

## 11. Reuse map (what the widget shares)

The WidgetKit widget should be **mostly assembly**, not new invention. Shared, in
dependency order:

| Layer | Component | Path | Reuse |
|---|---|---|---|
| **Data model** | `UsageSnapshot`, `UsageMetric`, `Capabilities`, `AuthMethod` | `core/Sources/FetcherCore/Models.swift` | **Verbatim.** Codable, `Sendable`, already the shared contract. |
| **Fetch** | `UsageProvider` / `ClaudeOAuthProvider` / `ClaudeCookieProvider` | `core/Sources/FetcherCore/…` | **App-side only.** The widget must NOT call these (no credentials in the extension). |
| **Cache bridge** | `SharedSnapshot.read()/write()` (App Group `group.org.salomao.houdini`) | `apps/ios/Shared/SharedSnapshot.swift` | **Reuse the pattern**; a macOS copy (or shared file) writes on the app side, reads on the widget side. Requires the App Group entitlement on both targets. |
| **Metric ranking** | `rankedRingWindows`, `dollarOverage`, `tightest`, `primary(for:)` | `apps/menubar/…/Formatting.swift` | **Reuse** so the widget promotes the same hero rings as panel + popover. Consider hoisting these `[UsageMetric]` extensions into `FetcherCore` so all three targets (menubar, widget, ios) share one copy instead of duplicating. |
| **Thresholds** | `Thresholds.barColor/labelColor` (macOS) ≡ `Theme.color(forPct:)` (iOS) ≡ site tokens | `…/Formatting.swift`, `apps/ios/Shared/Theme.swift` | **Reuse the scale** (60/85). Ideally unify into one shared definition to prevent drift. |
| **Gauge** | `WidgetRingGauge` (¾-ring) | `apps/menubar/…/WidgetRingGauge.swift` | **Reuse** as the signature glyph. It's pure SwiftUI + `FetcherCore`; portable to a WidgetKit target. |
| **Rows / bars / states** | `MetricRow`, `ProgressBar`, `RingPairSkeleton`, `NeedsAuthView`, `ErrorStateView`, `StatusDot`, `BrandWordmark` | `apps/menubar/…/SharedUI.swift` | **Reuse** for `systemLarge` rows + all states (with the WidgetKit sign-in caveat in §7/§8). |
| **A11y phrasing** | `A11y.*` helpers | `…/Formatting.swift` | **Reuse verbatim.** |
| **Dynamic Type / secondary text** | `scaledFont`, `glassSecondaryText` | `…/SharedUI.swift` | **Reuse.** |
| **Materials** | `GlassCardBackground`, `VisualEffectBlur`, `Color(hex:)`, brand hexes | `apps/menubar/…/WidgetGlass.swift` | **Panel:** reuse. **WidgetKit:** prefer the system `containerBackground` + `widgetRenderingMode` adaptation; borrow the wash/border only lightly (see §6a). |
| **Tokens** | `Theme` (colors, spacing, radius, typography, motion) | `apps/menubar/…/Theme.swift` | **Single source of truth — reuse.** Note there are currently *two* `Theme` enums (menubar vs `apps/ios/Shared`); the macOS widget should use the menubar `Theme`. **Open item:** de-duplicate the color source across app/widget/site (§12). |

**Structural note:** most reusable views live in `apps/menubar/Sources/Houdini`, which is an
SPM executable target — a WidgetKit extension is a separate (Xcode) target and can't import
an executable. To share cleanly, the reusable SwiftUI (gauge, rows, states, tokens, ranking,
a11y) should be lifted into a **library** target (e.g. a `HoudiniUI` SPM library, or folded
into `FetcherCore`/a sibling) that *both* the app and the widget extension depend on. This
refactor is the main *engineering* cost of Option C and should be scoped explicitly.

---

## 12. Open questions / decisions for the audit

1. **Ship WidgetKit at all now, given the distribution gate?** A WidgetKit extension + App
   Group most likely forces the **Apple Developer Program ($99/yr)** + Xcode target,
   changing today's ad-hoc `install.sh` (ADR-006). **Decision needed:** is that cost worth
   the native surface now, or defer WidgetKit until the Developer Program is on the table for
   other reasons (iOS app, notarized DMG)? *(This may override the Option-C recommendation.)*
2. **Both surfaces discoverable, or WidgetKit-primary + panel demoted?** ADR-010 hygiene vs
   ADR-002 (NC widget unadvertised). If both ship, how are they positioned so a new user
   doesn't see two overlapping "desktop usage" things? Does the panel become an off-by-default
   power-user Setting?
3. **Refresh button on WidgetKit — honest or omit?** A button that can only nudge (not truly
   refresh) risks implying liveness ADR-002 says we lack. Recommend omit on small/medium;
   decide for `systemLarge`.
4. **De-duplicate the design source of truth.** There are two `Theme` enums (menubar +
   `apps/ios/Shared`) and the threshold scale is defined in three places (menubar
   `Thresholds`, iOS `Theme`, site CSS). Unify before a *third* consumer (macOS WidgetKit)
   copies it again? (Recommended: yes.)
5. **Extract a shared `HoudiniUI` library.** Required for the widget extension to reuse the
   gauge/rows/tokens (an extension can't import the app's executable target). Approve the
   refactor + its scope.
6. **Accented/Tinted-mode fidelity.** Confirm the ring-fill-carries-severity approach is
   acceptable when the OS tints the widget one color (thresholds collapse). Any brand-tint
   preference for the Tinted style?
7. **Control Center control + accessory (Lock-Screen-style) families — in or out?** Native
   Tahoe touches, but scope creep. Recommend: out of the core unit, list as future.
8. **`systemExtraLarge` — confirmed deferred?** (Recommended: yes; revisit only for a
   future multi-provider board.)
9. **Naming/branding.** ADR-010/011 forbid separately branding the menu bar vs desktop
   widget. The WidgetKit widget's gallery `configurationDisplayName`/`description` must fit
   that (e.g. "Claude usage" as the existing iOS widget uses) — confirm copy.

---

## 13. Rough phased plan (future implementation)

> Sequenced per the Build Conductor loop (discovery-first, smallest reviewable change).
> **Nothing here is authorized by this doc** — it's a sketch for the audit to shape.

1. **Research → decision (this doc + audit).** Ratify Option A/B/C, resolve the distribution
   gate (§12.1), and the two-surfaces positioning (§12.2). *Output: a decision + possibly a
   new ADR revising ADR-002's "unadvertised" stance if WidgetKit becomes a first-class
   surface.*
2. **Spec refinement.** Fold the audit's answers back in: finalize families, per-size
   hierarchy, accented-mode rules, the interactivity set.
3. **Refactor for reuse (prereq).** Extract `HoudiniUI` (gauge, rows, states, tokens,
   ranking, a11y) into a library target both app + widget can import; de-duplicate `Theme`
   and the threshold scale (§12.4/12.5). Small, mechanical, verifiable by building the
   existing app against it unchanged.
4. **Prototype (headless first).** Build the WidgetKit views against the extracted library
   using **`PreviewData`/`SharedSnapshot` fixtures** — render small/medium/large in Xcode
   Previews across Light/Dark/Tinted/Clear, Dynamic Type sizes, Reduce Transparency, and
   VoiceOver. No live data yet. (Mirrors how the panel already does `--snapshot` renders.)
5. **Wire the cache + timeline.** App writes `SharedSnapshot` on each successful fetch
   (macOS side); widget `getTimeline` reads it with `.after(~15 min)`; add the rate-limited
   `WidgetCenter.reloadTimelines` nudge + reset-boundary entries (§9). Verify the honesty
   copy and that the extension never touches the network/Keychain.
6. **Build/sign (gated).** Only if §12.1 says go: stand up the Xcode target + App Group,
   enroll in the Developer Program, wire entitlements to match the app. **This step is
   sign-off-gated** (installer/signing/notarization per CLAUDE.md guardrails).
7. **Accessibility + visual polish (P2 finish).** Live audit across the states, all sizes,
   both appearances, Tinted/Clear, and the accessibility matrix (§10). Confirm parity with
   the panel/popover; confirm zero regressions to the shipped panel.
8. **Docs + ADR hygiene.** Update `apps/widget/README.md`, ADR-002 (if revised), `CONTEXT.md`
   (widget surfaces), and `PROVIDERS.md` if any capability wording shifts. Follow ADR-010
   single-version release hygiene.

---

## 14. Sources

Apple (primary):
- Human Interface Guidelines — Widgets: https://developer.apple.com/design/human-interface-guidelines/widgets/
- Human Interface Guidelines — Materials: https://developer.apple.com/design/human-interface-guidelines/materials
- What's new — Apple Design: https://developer.apple.com/design/whats-new/
- WidgetKit — Keeping a widget up to date (refresh budget, timeline policy): https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date
- WidgetKit — Adding interactivity to widgets and Live Activities (App Intents): https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities
- WidgetKit — Optimizing your widget for accented rendering mode and Liquid Glass: https://developer.apple.com/documentation/WidgetKit/optimizing-your-widget-for-accented-rendering-mode-and-liquid-glass
- WidgetKit — `WidgetRenderingMode`: https://developer.apple.com/documentation/widgetkit/widgetrenderingmode
- WidgetKit updates (families, platforms): https://developer.apple.com/documentation/updates/widgetkit
- WWDC25 — What's new in widgets: https://developer.apple.com/videos/play/wwdc2025/278/
- WWDC25 — Build a SwiftUI app with the new design: https://developer.apple.com/videos/play/wwdc2025/323/
- WWDC21 — Principles of great widgets: https://developer.apple.com/videos/play/wwdc2021/10048/
- Apple Newsroom — new software design (Liquid Glass): https://www.apple.com/newsroom/2025/06/apple-introduces-a-delightful-and-elegant-new-software-design/
- Apple Support — Add and customize widgets on Mac: https://support.apple.com/guide/mac-help/add-and-customize-widgets-mchl52be5da5/mac

macOS Tahoe / Liquid Glass (secondary, for current behavior & desktop widget styles):
- macOS Tahoe widgets & customization (Light/Dark/Tinted/Clear, drag-to-desktop): https://macos-tahoe.com/blog/macos-tahoe-widgets-customization-complete-guide-2025/
- The Eclectic Light Company — Tahoe appearance/widget styles: https://eclecticlight.co/2025/09/15/appearance-matters-get-tahoe-looking-in-better-shape/
- How to add widgets to the desktop in macOS Tahoe: https://appleworld.today/2025/10/how-to-add-widgets-to-your-desktop-in-macos-tahoe/
- macOS Tahoe Control Center customization (controls): https://www.tomsguide.com/computing/macos/how-to-customize-the-control-center-in-macos-tahoe-26

WidgetKit refresh budget / interactivity / accessibility (secondary):
- Apple Developer Forums — do Mac widgets have timeline limits: https://developer.apple.com/forums/thread/711091
- Swift Senpai — refreshing a widget: https://swiftsenpai.com/development/refreshing-widget/
- Liquid Glass in Swift — official best practices (iOS 26 / macOS Tahoe): https://dev.to/diskcleankit/liquid-glass-in-swift-official-best-practices-for-ios-26-macos-tahoe-1coo
- SwiftUI Gauge (styles for small surfaces): https://sarunw.com/posts/swiftui-gauge/
- SwiftUI accessibility guide (2026) — VoiceOver/Dynamic Type: https://swiftcrafted.dev/article/swiftui-accessibility-complete-guide-voiceover-dynamic-type-inclusive-design
- Accessibility in iOS widgets with SwiftUI: https://medium.com/better-programming/accessibility-in-ios-14-widgets-with-swiftui-83656bdb68e2

Houdini repo (grounding):
- `DECISIONS.md` (ADR-002 budget/honesty, ADR-005 Keychain, ADR-006 distribution, ADR-010/011 hygiene/branding, ADR-012 auth freeze)
- `CONTEXT.md` (desktop widget = SwiftUI in NSPanel, ~60s; NC WidgetKit widget unadvertised)
- `apps/menubar/Sources/Houdini/`: `DesktopWidgetView.swift`, `DesktopWidgetController.swift`, `WidgetRingGauge.swift`, `SharedUI.swift`, `WidgetGlass.swift`, `Theme.swift`, `Formatting.swift`, `UsageModel.swift`, `UsagePopover.swift`
- `apps/widget/README.md` (placeholder), `apps/ios/HoudiniWidget/HoudiniWidget.swift` + `apps/ios/Shared/SharedSnapshot.swift` + `apps/ios/Shared/Theme.swift` (WidgetKit precedent)
- `core/Sources/FetcherCore/Models.swift` (`UsageSnapshot`/`UsageMetric` data contract)
