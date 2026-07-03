// Central configuration — every external URL, version pin, and the site's
// content model lives here, so a release bump or a copy tweak is a one-file edit.
// Components and the /install + /guide pages read from this.

// The app/release version this build prepares (shown wherever a current version is
// referenced). At go-live `installTag` is flipped to `v${version}` so the published
// one-liner points at this release — see RELEASE.md.
export const version = "0.4.0";

// The release tag the installer downloads from. In sync with `v${version}` post
// go-live; the live one-liner fetches the verified artifacts from this release.
export const installTag = "v0.4.0";

export const site = {
  name: "Houdini",
  // The reveal — the product promise, kept across the home and the OG card.
  tagline: "See your AI usage and spend, revealed.",
  description:
    "Houdini is a local-first macOS app that reveals your AI usage and spend — in your menu bar and on your desktop. Your Claude limits, reset timers, and extra-usage dollars, refreshed every 60 seconds. No account, no server; credentials stay in your Keychain.",
  // Canonical origin (canonical + Open Graph): the Houdini subdomain on Vercel.
  domain: "https://houdini.salomao.org",
  // Real 1200×630 social card in public/og.png (regenerate: node scripts/og/build.mjs).
  ogImage: "og.png",
};

export const links = {
  github: "https://github.com/vitorsalomao05/houdini",
  // Releases / changelog page.
  changelog: "https://github.com/vitorsalomao05/houdini/releases",
  guide: "/guide",
  install: "/install",
};

// The verified path that works today: a one-liner that downloads the
// ad-hoc-signed Houdini.app + the `houdini` CLI from the pinned release,
// verifies their SHA-256 against SHASUMS256.txt, then installs them (no sudo,
// no Gatekeeper prompt). Pinned to the tag, so the bytes you run are the bytes
// we shipped.
export const installOneLiner = `curl -fsSL https://raw.githubusercontent.com/vitorsalomao05/houdini/${installTag}/install.sh | bash`;

// Build-from-source path — kept behind a discreet "For developers" disclosure
// on /install. Works today once cloned.
export const installFromSource = [
  "git clone https://github.com/vitorsalomao05/houdini",
  "cd houdini/apps/menubar",
  "./build.sh",
].join("\n");

// One route per screen. Install is the primary CTA (rendered as a button), and
// Home is the logo — so neither appears as a text link here.
export const nav = [
  { label: "Reveals", href: "/reveals" },
  { label: "Surfaces", href: "/surfaces" },
  { label: "Privacy", href: "/privacy" },
  { label: "FAQ", href: "/faq" },
  { label: "Guide", href: "/guide" },
];

// ── What Houdini reveals (compact icon strip) ────────────────────────────────
// The three dimensions Houdini pulls into the open — only what the app can
// honestly fill (usage %, reset timers, extra-usage dollars). No status badges
// — co-equal, glanceable.
export const reveals = [
  {
    title: "Limits",
    body: "Every cap — session and weekly — color-coded before you hit the wall.",
    icon: "gauge",
  },
  {
    title: "Sessions",
    body: "Your rolling 5-hour window, and exactly when it rolls back to zero.",
    icon: "clock",
  },
  {
    title: "Spend",
    body: "Dollars spent past your plan, in real time — never a surprise bill.",
    icon: "dollar",
  },
];

// ── Where Houdini shows up (two co-equal native features) ─────────────────────
// Both are the same Houdini, native to the app — no separate brand or logo. The
// menu bar renders live gauges; the desktop widget uses a real screenshot.
export const surfaces = [
  {
    title: "Menu bar",
    body: "Your tightest limit sits in the menu bar. Click for a popover with every window, its reset timer, and any overage — refreshed every 60 seconds.",
  },
  {
    title: "Desktop widget",
    body: "Prefer it on the desktop? The same gauges, pinned to your wallpaper — part of the app, not a separate install. The same true 60-second refresh.",
  },
];

// ── FAQ ──────────────────────────────────────────────────────────────────────
export const faqs = [
  {
    q: "Is Houdini really installable today?",
    a: "Yes. The one-liner installs Houdini right now — ad-hoc signed with a hardened runtime, so it opens with no Gatekeeper prompt. You're not waiting for anything to start tracking Claude.",
  },
  {
    q: "Do my credentials ever leave my Mac?",
    a: "No. There is no Houdini account and no Houdini server. Houdini reads the credential already on your machine — your Claude Code OAuth token, or a claude.ai session you sign in to in a native window — and calls the provider directly from your Mac. Tokens stay in your Keychain.",
  },
  {
    q: "Which AI providers does it work with?",
    a: "Claude Pro and Max work today — your limits, reset timers, and extra-usage spend. Houdini is Claude-first; more providers can come as they open up, and it never shows a gauge it can't honestly fill.",
  },
  {
    q: "How does it read my Claude usage?",
    a: "If you use Claude Code, Houdini reuses its OAuth token from the Keychain — zero new logins. Otherwise you sign in to claude.ai in a native window; the session is kept in your Keychain and reused until it expires — you'll sign in again when it does. It then calls the same usage endpoint the official tools do.",
  },
  {
    q: "Does it really refresh every 60 seconds?",
    a: "Yes — a true 60-second timer, in the menu bar and the desktop widget alike, so the headline number is always current.",
  },
  {
    q: "What does it cost?",
    a: "Nothing. Houdini is free and open-source. Read every line before you run it — the installer is pinned to a release tag and verifies checksums before touching your disk.",
  },
  {
    q: "macOS requirements?",
    a: "macOS 14 (Sonoma) or newer on Apple Silicon. No Intel build is shipped.",
  },
];
