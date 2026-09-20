// Generates the real 1200×630 Open Graph card → site/public/og.png.
//
// Single reproducible command:  node scripts/og/build.mjs
//
// It inlines the brand fonts (Fraunces display + Inter body) and the dark
// product popover as data URIs into an HTML template, then renders it with
// headless Chrome at an exact 1200×630 viewport (device-scale-factor 1, so the
// PNG is pixel-exact). Chrome path is auto-detected; override with CHROME_BIN.

import { readFileSync, writeFileSync, mkdtempSync, existsSync } from "node:fs";
import { execFileSync } from "node:child_process";
import { tmpdir } from "node:os";
import { join, dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const siteRoot = resolve(here, "..", "..");

const WIDTH = 1200;
const HEIGHT = 630;

// ── Inlined assets ─────────────────────────────────────────────────────────
const interPath = join(
  siteRoot,
  "node_modules/@fontsource-variable/inter/files/inter-latin-wght-normal.woff2",
);
const frauncesPath = join(
  siteRoot,
  "node_modules/@fontsource-variable/fraunces/files/fraunces-latin-wght-normal.woff2",
);
const popoverPath = join(siteRoot, "src/assets/popover-dark.png");

const interB64 = readFileSync(interPath).toString("base64");
const frauncesB64 = readFileSync(frauncesPath).toString("base64");
const popoverB64 = readFileSync(popoverPath).toString("base64");

// The top-hat mark, lifted from src/components/Logo.astro.
const mark = `
<svg width="50" height="50" viewBox="0 0 32 32" fill="none" aria-hidden="true">
  <defs>
    <linearGradient id="lb" x1="16" y1="2" x2="16" y2="30" gradientUnits="userSpaceOnUse">
      <stop offset="0" stop-color="#1E1A2B"/><stop offset="1" stop-color="#0B0A10"/>
    </linearGradient>
    <linearGradient id="la" x1="8" y1="23" x2="24" y2="8" gradientUnits="userSpaceOnUse">
      <stop offset="0" stop-color="#7C3AED"/><stop offset="1" stop-color="#C026D3"/>
    </linearGradient>
  </defs>
  <rect x="1" y="1" width="30" height="30" rx="7" fill="url(#lb)" stroke="#3A3357"/>
  <rect x="5" y="20.4" width="22" height="3.4" rx="1.7" fill="url(#la)"/>
  <path d="M11 23 V11.5 a2 2 0 0 1 2 -2 H19 a2 2 0 0 1 2 2 V23 Z" fill="url(#la)"/>
  <rect x="11" y="17.4" width="10" height="2.2" fill="#F5C451"/>
  <path d="M25 8.4 C 25.5 9.9, 26.1 10.5, 27.6 11 C 26.1 11.5, 25.5 12.1, 25 13.6 C 24.5 12.1, 23.9 11.5, 22.4 11 C 23.9 10.5, 24.5 9.9, 25 8.4 Z" fill="#F5C451"/>
</svg>`;

const html = `<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<style>
  @font-face {
    font-family: "Inter"; font-weight: 100 900; font-display: block;
    src: url(data:font/woff2;base64,${interB64}) format("woff2");
  }
  @font-face {
    font-family: "Fraunces"; font-weight: 100 900; font-display: block;
    src: url(data:font/woff2;base64,${frauncesB64}) format("woff2");
  }
  * { margin: 0; padding: 0; box-sizing: border-box; }
  html, body {
    width: ${WIDTH}px; height: ${HEIGHT}px; overflow: hidden;
    background: #0b0a10; color: #eceaf2;
    font-family: "Inter", -apple-system, BlinkMacSystemFont, sans-serif;
    -webkit-font-smoothing: antialiased; text-rendering: geometricPrecision;
  }
  /* The stage spotlight, behind the headline. */
  .glow {
    position: absolute; inset: 0; pointer-events: none;
    background:
      radial-gradient(640px 480px at 16% 24%,
        color-mix(in oklab, #8b5cf6 32%, transparent), transparent 70%),
      radial-gradient(560px 440px at 40% 2%,
        color-mix(in oklab, #c026d3 22%, transparent), transparent 72%);
  }
  .grid {
    position: absolute; inset: 0; pointer-events: none; opacity: .5;
    background-image:
      linear-gradient(#ffffff09 1px, transparent 1px),
      linear-gradient(90deg, #ffffff09 1px, transparent 1px);
    background-size: 46px 46px;
    -webkit-mask-image: radial-gradient(900px 560px at 30% 40%, #000 30%, transparent 80%);
            mask-image: radial-gradient(900px 560px at 30% 40%, #000 30%, transparent 80%);
  }
  .wrap { position: relative; height: 100%; display: flex; align-items: stretch; }
  .left {
    position: relative; z-index: 2; width: 668px; padding: 70px 0 70px 76px;
    display: flex; flex-direction: column; justify-content: space-between;
  }
  .brand { display: flex; align-items: center; gap: 15px; }
  .brand .name { font-family: "Fraunces", serif; font-size: 31px; font-weight: 600; letter-spacing: -0.01em; color: #fff; }
  .brand .tag {
    margin-left: 6px; font-size: 13px; font-weight: 500; letter-spacing: .05em;
    text-transform: uppercase; color: #9a93b0;
    padding: 6px 11px; border: 1px solid #2a2540; border-radius: 999px; background: #161320;
  }
  h1 {
    font-family: "Fraunces", serif;
    font-size: 64px; line-height: 1.03; font-weight: 600; letter-spacing: -0.015em;
    color: #fff; max-width: 580px;
  }
  h1 .accent {
    background: linear-gradient(100deg, #a855f7, #c026d3);
    -webkit-background-clip: text; background-clip: text; color: transparent;
  }
  .sub {
    margin-top: 22px; font-size: 21px; line-height: 1.5; color: #9a93b0;
    max-width: 540px; font-weight: 400;
  }
  .foot { display: flex; align-items: center; gap: 14px; }
  .chip {
    display: inline-flex; align-items: center; gap: 10px;
    padding: 10px 16px; border: 1px solid #2a2540; border-radius: 12px;
    background: #161320; font-size: 19px; color: #eceaf2;
    font-family: ui-monospace, "SF Mono", Menlo, monospace; letter-spacing: -0.01em;
  }
  .dot { width: 9px; height: 9px; border-radius: 999px; background: #34d399; box-shadow: 0 0 10px #34d399; }
  .right { position: relative; z-index: 1; flex: 1; }
  .card {
    position: absolute; top: 50%; right: -56px; transform: translateY(-50%) rotate(-1deg);
    width: 470px; border-radius: 22px; padding: 0; overflow: hidden;
    background:
      linear-gradient(#161320, #161320) padding-box,
      linear-gradient(135deg,
        color-mix(in oklab, #8b5cf6 75%, transparent),
        color-mix(in oklab, #c026d3 62%, transparent)) border-box;
    border: 1.5px solid transparent;
    box-shadow: 0 40px 90px -20px #000c, 0 0 90px -28px #8b5cf6aa;
  }
  .card img { display: block; width: 100%; height: auto; }
</style></head>
<body>
  <div class="glow"></div>
  <div class="grid"></div>
  <div class="wrap">
    <div class="left">
      <div class="brand">
        ${mark}
        <span class="name">Houdini</span>
        <span class="tag">macOS</span>
      </div>
      <div>
        <h1>See your AI usage and spend, <span class="accent">revealed</span>.</h1>
        <p class="sub">Claude and Codex usage, limits, and reset timers — in your menu bar and on your desktop. Connect through the official clients. No Houdini account or server.</p>
      </div>
      <div class="foot">
        <span class="chip"><span class="dot"></span>houdini.salomao.org</span>
      </div>
    </div>
    <div class="right">
      <div class="card">
        <img src="data:image/png;base64,${popoverB64}" alt="">
      </div>
    </div>
  </div>
</body></html>`;

// ── Render with headless Chrome ─────────────────────────────────────────────
const tmp = mkdtempSync(join(tmpdir(), "houdini-og-"));
const htmlFile = join(tmp, "og.html");
writeFileSync(htmlFile, html);

const out = join(siteRoot, "public", "og.png");

const candidates = [
  process.env.CHROME_BIN,
  "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
  "/Applications/Chromium.app/Contents/MacOS/Chromium",
  "/Applications/Google Chrome Canary.app/Contents/MacOS/Google Chrome Canary",
].filter(Boolean);
const chrome = candidates.find((p) => existsSync(p));
if (!chrome) {
  console.error("No Chrome/Chromium found. Set CHROME_BIN=/path/to/chrome.");
  process.exit(1);
}

execFileSync(
  chrome,
  [
    "--headless=new",
    "--disable-gpu",
    "--hide-scrollbars",
    "--force-device-scale-factor=1",
    `--window-size=${WIDTH},${HEIGHT}`,
    "--virtual-time-budget=2000",
    `--screenshot=${out}`,
    `file://${htmlFile}`,
  ],
  { stdio: "inherit" },
);

console.log(`Wrote ${out} (${WIDTH}×${HEIGHT}) using ${chrome}`);
