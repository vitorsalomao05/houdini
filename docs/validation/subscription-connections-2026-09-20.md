# Subscription connections — validation, 2026-09-20

Base: `master@7a6d6f7119efa7c375cf7746cdff747cd507c626`. Work lives on a separate
`feat/subscription-connections` checkout. No release, installation, remote push,
provider login/logout, or signing command was performed.

## Observed results

| Check | Result |
| --- | --- |
| Core Swift Testing | 103 tests, 11 suites passed; includes 8 Claude process tests and 12 Codex tests with parameterized cases |
| Core `houdini-selftest` | 88 checks passed |
| App debug build, SDK macOS 26.5 | Passed |
| App `--authtest` | 26 passed, 0 failed; fake credentials and providers only |
| App `--metrictest` | 10 checks passed |
| App `--widgettest` | Skipped: no display available in the command environment; not a pass |
| Sample-data rendering | Popover and compact/regular widget rendered for Claude and ChatGPT · Codex; populated layouts inspected |
| Native controls / keyboard | Pending: automatic approval review rejected launching the isolated preview app; user approval requested |
| Diff checks | Passed |
| Independent standards review | One missing subscription accessibility label fixed; duplicated metric-availability rule centralized; reviewer confirmed both resolved |
| Independent spec review | No functional deviation identified |
| Original WIP preservation | All 192 files, status, index, and staged/unstaged patches identical to the preservation snapshot |

Native controls are not rendered by SwiftUI `ImageRenderer`; its placeholders are
not evidence of a broken live control or of successful native UI validation. The
debug-only `--connection-preview` mode supplies a native offline surface with
isolated preferences and fake providers. Its launch remains approval-dependent.

The owner's original screenshot shows a Google cross-device/passkey step with a
Bluetooth/proximity error. The replacement Claude connection flow delegates to
the official client's external browser. A successful real login through that flow,
and real Codex quota access, have not been observed. Process-fixture results must
not be reported as proof that Google's original error has been resolved.

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
and failure handling. The earlier isolated, unauthenticated real-client spike proved
initialization/account lookup with ephemeral storage; it did not prove a real
Keychain or authenticated quota round trip. Missing official clients receive setup
links, and incompatible versions fail with an explicit message.

The published app/site remain unchanged. The iOS scaffold, API billing providers,
paused WIPs #3/#4, and the old issue #5 gate proposal were not implemented here.
