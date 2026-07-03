#!/usr/bin/env bash
#
# init.sh — Houdini developer bootstrap / orientation.
#
# Safe to re-run. Does NOT touch the network beyond `--version` probes and does
# NOT read, print, or cache any credential. It:
#   1. Verifies the toolchain (Swift for core + apps, Node/npm for the site).
#   2. Prints the repo map and the REAL build / test / run commands per area.
#   3. Prints the current top BACKLOG item so you know what's next.
#
# Exits non-zero with a helpful message if a required tool is missing.
#
#   Usage:  scripts/init.sh
#
set -euo pipefail

# Resolve repo root from this script's location (works from anywhere).
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# ── Output helpers ───────────────────────────────────────────────────────────
if [ -t 1 ]; then
  BOLD=$'\033[1m'; BLUE=$'\033[1;34m'; GREEN=$'\033[1;32m'; YELLOW=$'\033[1;33m'; RED=$'\033[1;31m'; DIM=$'\033[2m'; RST=$'\033[0m'
else
  BOLD=''; BLUE=''; GREEN=''; YELLOW=''; RED=''; DIM=''; RST=''
fi
h()    { printf '\n%s== %s ==%s\n' "$BOLD" "$1" "$RST"; }
ok()   { printf '%s  ✓%s %s\n' "$GREEN"  "$RST" "$1"; }
warn() { printf '%s  !%s %s\n' "$YELLOW" "$RST" "$1"; }
info() { printf '    %s\n' "$1"; }
cmd()  { printf '    %s$%s %s\n' "$DIM" "$RST" "$1"; }

MISSING=0
need() { # need <bin> <why>
  if command -v "$1" >/dev/null 2>&1; then
    ok "$1 — $($1 --version 2>&1 | head -1)"
  else
    printf '%s  ✗%s %s not found — %s\n' "$RED" "$RST" "$1" "$2"
    MISSING=1
  fi
}
have() { command -v "$1" >/dev/null 2>&1; }

printf '%sHoudini — developer bootstrap%s  %s(%s)%s\n' "$BOLD" "$RST" "$DIM" "$ROOT" "$RST"

# ── 1. Toolchain ─────────────────────────────────────────────────────────────
h "Toolchain"
need swift "required to build core/ + apps/menubar (Swift 6 / CommandLineTools or Xcode 16+)"
need node  "required to build the site/ (Astro). Install Node 20+ (repo/Vercel use 24.x)"
need npm   "required to install + build the site/"
# Optional / nice-to-have.
if have git;      then ok "git — $(git --version)"; else warn "git not found (needed to release/commit)"; fi
if have xcodegen; then ok "xcodegen — present (needed only to generate apps/ios project)"; else info "xcodegen: absent (only needed for apps/ios — brew install xcodegen)"; fi
# `command -v xcodebuild` is true even on CommandLineTools-only machines (a shim that
# errors when run), so detect full Xcode via the active developer directory instead.
if xcode-select -p 2>/dev/null | grep -q "Xcode.app"; then info "Xcode: full install ($(xcode-select -p)). Not required — apps build via SwiftPM."; else info "Xcode: CommandLineTools only — fine; apps build via SwiftPM + build.sh (only apps/ios needs full Xcode)."; fi

# ── 2. Repo map ──────────────────────────────────────────────────────────────
h "Repo map"
cat <<'MAP'
    core/            FetcherCore Swift package (shared data layer) + `houdini` CLI
    apps/menubar/    SwiftUI MenuBarExtra app + native desktop widget (flagship)
    apps/widget/     WidgetKit Notification Center widget (doc placeholder; ~15min, unadvertised — ADR-002)
    apps/ios/        Native iOS app scaffold (cookie auth, reuses FetcherCore — ADR-008)
    site/            Astro + Tailwind landing page (houdini.salomao.org, deploys via Vercel)
    scripts/         developer bootstrap (this script) — release automation lives in .github/workflows/release.yml
    install.sh       one-liner installer (SHA-256 verified download from a pinned Release)
MAP

# ── 3. Real commands ─────────────────────────────────────────────────────────
h "core/ — FetcherCore + houdini CLI  (Swift 6)"
cmd "cd core && swift build"
cmd "cd core && swift test                 # swift-testing; no-ops on CommandLineTools-only"
cmd "cd core && swift run houdini-selftest  # runnable test mirror for CommandLineTools-only machines"
cmd "cd core && swift run houdini --json    # exercise the Claude provider against your account"

h "apps/menubar — flagship menu bar app + desktop widget"
cmd "cd apps/menubar && ./build.sh release  # -> build/Houdini.app (ad-hoc signed, hardened runtime)"
cmd "open apps/menubar/build/Houdini.app"

h "apps/ios — native iOS scaffold (needs macOS + Xcode + xcodegen; not buildable on CommandLineTools-only)"
cmd "cd apps/ios && xcodegen generate && open HoudiniMobile.xcodeproj"

h "site/ — Astro + Tailwind (npm)"
cmd "cd site && npm install"
cmd "cd site && npm run dev      # local dev server"
cmd "cd site && npm run build    # production build -> site/dist"
cmd "cd site && npm run preview  # preview the production build"
info "Deploy: Vercel project 'houdini' (site/.vercel). No lint/test scripts are defined."

h "release / install"
cmd "less install.sh             # pinned tag + SHA-256 verify; installs without sudo"
info "A vX.Y.Z tag push triggers .github/workflows/release.yml — the SOLE publisher: it builds,"
info "verifies (core tests + selftest + app smoke), checksums, and publishes the Release."
info "Manual role: bump, tag, watch, verify — see RELEASE.md."

# ── 4. Current top priority ──────────────────────────────────────────────────
h "Top BACKLOG item"
if [ -f BACKLOG.md ]; then
  # Print the FIRST non-done "## P" heading (skip items marked `[x]`) and its
  # Problem/Goal teaser lines; stop at the next "## P" heading.
  awk '
    /^## P[0-9]/ {
      if (n == 1) exit
      if ($0 ~ /\[x\]/) next
      n = 1; print "    " $0; next
    }
    n == 1 && /^\*\*(Problem|Goal)\.\*\*/ { line=$0; gsub(/\*\*/,"",line); print "    " line }
  ' BACKLOG.md
else
  warn "BACKLOG.md not found."
fi

# ── Done ─────────────────────────────────────────────────────────────────────
if [ "$MISSING" -ne 0 ]; then
  printf '\n%s✗ One or more required tools are missing (see above). Install them, then re-run.%s\n' "$RED" "$RST" >&2
  exit 1
fi
printf '\n%s✓ Toolchain OK. See CLAUDE.md (how we work) · CONTEXT.md (why) · BACKLOG.md (what next).%s\n' "$GREEN" "$RST"
