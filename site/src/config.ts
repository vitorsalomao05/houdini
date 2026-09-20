// Central configuration — every external URL, version pin, and the site's
// content model lives here, so a release bump or a copy tweak is a one-file edit.
// Components and the /install + /guide pages read from this.

// The app/release version this build prepares (shown wherever a current version is
// referenced). At go-live `installTag` is flipped to `v${version}` so the published
// one-liner points at this release — see RELEASE.md.
export const version = "1.1.0";

// The release tag the installer downloads from. In sync with `v${version}` post
// go-live; the live one-liner fetches the verified artifacts from this release.
export const installTag = "v1.1.0";

export const site = {
  name: "Houdini",
  // The reveal — the product promise, kept across the home and the OG card.
  tagline: "See your AI usage and spend, revealed.",
  description:
    "Claude and Codex usage, limits, and reset timers — in your Mac's menu bar and on your desktop. Connect through the official clients, refresh every 60 seconds by default. No Houdini account or server.",
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

// ── What Houdini reveals ──────────────────────────────────────────────────────
// The three dimensions Houdini pulls into the open — only what the app can
// honestly fill (usage %, reset timers, extra-usage dollars). Rendered as the
// tabs on /reveals; co-equal, glanceable, no status badges.
export const reveals = [
  {
    title: "Limits",
    body: "Claude and Codex quota windows, color-coded so you can see how much is left. Only the limits your provider reports appear.",
  },
  {
    title: "Sessions",
    body: "The reset time for each available window, including 5-hour and weekly limits when your provider returns them.",
  },
  {
    title: "Spend",
    body: "Claude extra-usage spend against your budget, when enabled and reported. Codex shows subscription quotas; API billing is not included.",
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
    a: "Yes. The one-liner installs Houdini — ad-hoc signed with a hardened runtime, with checksum verification and no sudo. Choose Claude or Codex in Settings and connect through the matching official client.",
  },
  {
    q: "Where do my credentials go?",
    a: "Authentication goes directly to your provider; there is no Houdini server. Houdini reads an existing Claude credential locally. The official Codex client owns its login and stores Houdini's separate session in the macOS Keychain. Houdini does not log tokens or ask you to paste them.",
  },
  {
    q: "Which AI providers does it work with?",
    a: "Claude Pro/Max and Codex. Select one subscription for the menu bar and desktop widget. Claude includes available usage windows and extra-usage spend; Codex includes the quota windows returned by its official client. Codex limits are not a universal ChatGPT allowance, and API billing is not included.",
  },
  {
    q: "How does it read my Claude usage?",
    a: "Houdini discovers your existing Claude Code credential. To connect or renew it, choose Connect Claude in Settings: Claude Code opens the browser and owns the sign-in. Previously saved Claude.ai sessions remain a fallback. Usage still comes from undocumented endpoints; Anthropic restricts third-party subscription OAuth use, so this integration carries that risk.",
  },
  {
    q: "How do I connect Codex?",
    a: "Install the official Codex CLI 0.150.x, choose Codex in Houdini Settings, and select Connect Codex. Complete sign-in in your browser. Houdini uses a separate session managed by the official client, leaving your usual Codex login and configuration unchanged. Other client versions show an explicit compatibility message.",
  },
  {
    q: "Does it really refresh every 60 seconds?",
    a: "The default is a 60-second timer for both surfaces; Settings also offers 30 or 120 seconds. Provider failures can delay updates, and Houdini shows the reading's age or an error instead of treating missing usage as zero.",
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
