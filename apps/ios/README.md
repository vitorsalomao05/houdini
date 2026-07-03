# Houdini for iPhone (`apps/ios`) — scaffold

**This does not build on this machine.** It is **source + plan only**. An iOS app
and a WidgetKit extension require **Xcode** (full IDE + iOS SDK); `swift build` on
CommandLineTools cannot produce them. Nothing here has been compiled — see the
`// TODO(xcode)` markers and [`PLAN.md`](./PLAN.md).

## What this is

A SwiftUI iPhone app + WidgetKit widget that reuses the **shared `FetcherCore`**
(by path, `../../core`) for all auth, fetching, and parsing. The phone authenticates
to claude.ai with the **session cookie** (no Claude Code on iOS), stored in the iOS
Keychain — exactly FetcherCore's cookie path. Full rationale: [`PLAN.md`](./PLAN.md);
decision record: `../../DECISIONS.md` ADR-008.

## Layout

```
apps/ios/
├── PLAN.md                      # the mobile plan (read this first)
├── README.md                    # you are here
├── project.yml                  # XcodeGen spec — documents the two targets + App Group
├── HoudiniMobile/                 # the app target (SwiftUI)
│   ├── HoudiniMobileApp.swift     #   @main entry
│   ├── ContentView.swift        #   main screen (gauges / signed-out / error states)
│   ├── UsageViewModel.swift     #   @MainActor model over FetcherCore (cookie path)
│   ├── ClaudeLoginView.swift    #   WKWebView login → capture sessionKey → Keychain
│   └── GaugeRow.swift           #   one usage gauge row (Houdini's signature)
├── Shared/                      # compiled into BOTH the app and the widget targets
│   ├── Theme.swift              #   dark/blue palette matching the site tokens
│   └── SharedSnapshot.swift     #   App Group read/write of the cached UsageSnapshot
└── HoudiniWidget/                 # the widget extension target (placeholder)
    ├── HoudiniWidgetBundle.swift  #   @main WidgetBundle
    └── HoudiniWidget.swift        #   Home + Lock Screen timeline reading the cache
```

## How it will be built (in Xcode, once unblocked)

1. **Generate the project** (documents intent without Xcode GUI clicking):
   ```sh
   brew install xcodegen      # requires Xcode to then open/build the result
   cd apps/ios && xcodegen generate
   open Houdini.xcodeproj
   ```
   …or create the two targets by hand in Xcode and add the files above.
2. Add **`../../core`** as a local Swift Package dependency; link the `FetcherCore`
   library product to **both** the app and the widget targets.
3. Enable the **App Group** capability (`group.org.salomao.houdini`) on both targets,
   and Keychain Sharing on both.
4. Set a real **Team** and bundle IDs (placeholders are `org.salomao.houdini.*`).
5. Build to a device (free personal team = 7-day signature) to smoke-test, then
   TestFlight → App Store (needs the **$99/yr** Apple Developer Program).

## Blocked on

Xcode, the **$99/yr** Apple Developer Program, and a confirmed Team ID / bundle-ID
prefix. None can be produced on this CommandLineTools-only Mac. The core
(`../../core`) is iOS-compilable **by construction** — its `#if os(macOS)` guards were
verified by inspection and its macOS build still passes — but the **iOS compile itself
is unverified** (no iOS SDK here); it stays a documented assumption until a real Xcode
build runs. See [`PLAN.md`](./PLAN.md) §5.
