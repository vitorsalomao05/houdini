# Subscription connections — validation, 2026-09-20

Base: `master@7a6d6f7119efa7c375cf7746cdff747cd507c626`. Work lives on a separate
`feat/subscription-connections` checkout. No release, replacement of the installed
app, remote push, provider logout, or signing command was performed. The owner
approved opening a separate real validation bundle and completed Codex sign-in.

## Observed results

| Check | Result |
| --- | --- |
| Core Swift Testing | 103 tests, 11 suites passed for the implementation; 12 tests in the two Codex suites passed again after the visible-name change |
| Core `houdini-selftest` | 88 checks passed |
| App debug build, SDK macOS 26.5 | Passed |
| App `--authtest` | 26 passed, 0 failed; repeated on the final Codex-name build; fake credentials and providers only |
| App `--metrictest` | 10 checks passed |
| App `--widgettest` | Initial sandbox run skipped; real-display run exposed 2 size-limit failures, corrected in `dfee79f`; 11 passed, 0 failed in three subsequent runs |
| Sample-data rendering | Popover and compact/regular widget rendered for Claude and Codex; populated layouts inspected |
| Native controls / layout | Passed in the user-approved offline preview: Claude and Codex selection, appropriate metric choices, percentage/reset labels, and missing-client error; caption truncation found and fixed |
| Keyboard / visible focus | Passed in the real Settings window with Keyboard navigation temporarily enabled: Tab/Shift+Tab, arrow navigation, Space activation, visible connection-button/radio/switch focus; global setting restored off |
| Real Codex login and quotas | Official browser login completed by owner; Houdini displayed up-to-date data: one 7-day window, 0% used, reset in approximately 6d 23h; selection away/back performed another successful quota read without login |
| Final bundle restart | After quitting and updating the separate bundle to code commit `1a7cf6d`, reopening restored the Codex selection and displayed Connected · usage updated without another browser login; native Settings showed Codex / Connect Codex / Set up Codex |
| Codex local persistence boundary | Dedicated directory exists with mode 0700; no plaintext `auth.json`; token contents were not inspected |
| Real Claude connection | Official external browser opened; provider required Pro/Max for the current browser session; owner explicitly deferred account validation |
| Diff checks | Passed |
| Independent standards review | One missing subscription accessibility label fixed; duplicated metric-availability rule centralized; reviewer confirmed both resolved |
| Independent spec review | No functional deviation identified |
| Original WIP preservation | All 192 files, status, index, and staged/unstaged patches identical to the preservation snapshot |

Native controls are not rendered by SwiftUI `ImageRenderer`; its placeholders are
not evidence of a broken live control or of successful native UI validation. The
debug-only `--connection-preview` mode supplies a native offline surface with
isolated preferences and fake providers. Automatic review initially blocked launch;
the owner then explicitly approved it, and native inspection was completed. The
preview showed Claude 32%/95% and Codex 24%/63% with resets, correct provider names,
and native controls without renderer placeholders. Codex exposes only Auto, 5-hour,
and Weekly metric choices. A deliberately missing fake Codex executable displayed
the setup error without making a provider request. Explanatory text now keeps its
full multiline height when that error is shown. Text and contrast were visually
checked; no instrumented contrast measurement was performed.

The initial keyboard attempt was inconclusive with macOS Keyboard navigation off.
The owner subsequently approved enabling it temporarily. Native UI inspection
confirmed its initial off state, enabled it, exercised Tab/Shift+Tab, arrows and
Space in the real app, and restored it to off. Connection-button, metric-radio and
widget-switch focus rings were visible. Weekly metric selection, widget on/off,
interval 60s → 120s → 60s, and subscription switching responded correctly. Launch
at login remained off. The earlier ineffective volatile-domain experiment was
removed; the preview retains only its read-only diagnostic banner.

With display access, the existing widget smoke test initially returned 9 passed,
2 failed. Installing `NSHostingView` changed the explicit 252×182 / 512×392 limits
to 0×28 / infinity. The master's widget layout reproduced the same fault. The fix
disables hosting-view sizing and applies the controller's bounds after installing
the content view. Existing regression checks then passed 11/0 three times,
including frame persistence, restoration and off-screen recovery.

The owner's original screenshot shows a Google cross-device/passkey step with a
Bluetooth/proximity error. The replacement Claude connection flow delegates to
the official client's external browser; this was observed in the real app. The
provider reported that the active browser session required Pro/Max. The owner
deferred Claude validation and proceeded with Codex, whose browser login and real
quota reads succeeded. This does not prove Google's original error is resolved.

## Toolchain and reproduction

Installed compiler: Apple Swift 6.4 / CommandLineTools. SDK27 fails on a minimal
SwiftUI `@State` example because `SwiftUIMacros.StateMacro` is unavailable. The
already-installed SDK26.5 compiles the same example and the complete app. This is
a per-command SDK selection; no global toolchain setting changed.

Run core tests from `core/`, with writable temporary caches and scratch paths:

```sh
swift test --build-system native --disable-sandbox --enable-swift-testing \
  --cache-path /private/tmp/houdini-codex-cache \
  --scratch-path /private/tmp/houdini-codex-actual-native \
  -Xswiftc -F -Xswiftc /Library/Developer/CommandLineTools/Library/Developer/Frameworks \
  -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/Frameworks \
  -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/usr/lib
```

The executed environment also set `CLANG_MODULE_CACHE_PATH` and
`SWIFTPM_MODULECACHE_OVERRIDE` to task-specific directories under `/private/tmp`.
Confirm the final **test count**; a zero-test exit is not validation.

From `apps/menubar/`, build with `swift build --disable-sandbox --sdk
/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk` plus writable cache/scratch
paths. Run the built `HoudiniApp` with `--authtest` and `--metrictest`.
`HOUDINI_SNAPSHOT_SAMPLE=1` selects offline data for `--snapshot <directory>`.
The CI app smoke step now includes `--authtest`.

## Compatibility boundary

Codex protocol and keyring namespace were checked against official `rust-v0.150.1`;
this implementation accepts `codex-cli 0.150.x`. Fake processes prove the protocol
and failure handling. Real `codex-cli 0.150.1` subsequently completed browser login
and authenticated quota reads across separate client processes. Only one returned
7-day window was rendered; no missing 5-hour window was synthesized. Missing
official clients receive setup links, and incompatible versions fail with an
explicit message. The owner requested the visible name **Codex** during this QA;
the protocol and persisted subscription identifiers remain unchanged.

The real test bundle is `Houdini Connections Validation.app`, with bundle identifier
`org.salomao.houdini.connections-validation`; its preferences are separate from the
installed app. Initial automation could not reach a menu-only app until the owner
opened its Settings window. Subsequent native actions and keyboard checks were
automated. The final bundle remains available with the real Codex session connected.
Claude account validation is deferred by the owner's explicit instruction.

The published app/site remain unchanged. The iOS scaffold, API billing providers,
paused WIPs #3/#4, and the old issue #5 gate proposal were not implemented here.
