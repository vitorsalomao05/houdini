import Foundation
import FetcherCore

// houdini-selftest — a runnable proof of the FetcherCore parser + org-selection
// logic, reading the SAME committed fixtures as Tests/FetcherCoreTests.
//
// Why this exists alongside the swift-testing suite: this machine has only
// CommandLineTools, which ships `Testing.framework` but whose SwiftPM async
// entry point no-ops under `swift test` (it executes normally on a full Xcode
// toolchain / CI). This executable lets us actually *observe* the assertions
// pass here. It mirrors the `--selftest` idiom already used by the menu bar app.
//
// Exit code: 0 if every check passes, 1 otherwise.

var failures = 0
var checks = 0

@MainActor
func check(_ name: String, _ passed: Bool, _ detail: @autoclosure () -> String = "") {
    checks += 1
    if passed {
        print("  ✔ \(name)")
    } else {
        failures += 1
        let d = detail()
        print("  ✘ \(name)\(d.isEmpty ? "" : " — \(d)")")
    }
}

// Locate the committed fixtures relative to this source file.
let fixturesDir = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()            // Sources/houdini-selftest
    .deletingLastPathComponent()            // Sources
    .deletingLastPathComponent()            // core
    .appendingPathComponent("Tests/FetcherCoreTests/Fixtures")

func fixture(_ name: String) -> Data {
    let url = fixturesDir.appendingPathComponent("\(name).json")
    guard let data = try? Data(contentsOf: url) else {
        print("FATAL: cannot read fixture \(url.path)")
        exit(2)
    }
    return data
}

func iso(_ s: String) -> Date {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime]
    return f.date(from: s)!
}

let expected: [UsageMetric] = {
    let fiveHourReset = iso("2026-06-16T11:39:59Z")
    let weeklyReset = iso("2026-06-22T05:59:59Z")
    return [
        UsageMetric(label: "5-hour", pct: 3, resetAt: fiveHourReset, providerId: "claude"),
        UsageMetric(label: "Weekly", pct: 15, resetAt: weeklyReset, providerId: "claude"),
        UsageMetric(label: "Opus weekly", pct: 42, resetAt: weeklyReset, providerId: "claude"),
        UsageMetric(label: "Sonnet weekly", pct: 0, resetAt: weeklyReset, providerId: "claude"),
        UsageMetric(label: "Extra usage ($)", pct: 93.07, used: 93.07, limit: 100,
                    dollars: 93.07, providerId: "claude"),
    ]
}()

print("=== houdini-selftest: ClaudeUsageParser (2 fixtures) ===")

do {
    let oauth = try ClaudeUsageParser.parse(fixture("oauth_usage"), providerId: "claude")
    let cookie = try ClaudeUsageParser.parse(fixture("cookie_usage"), providerId: "claude")

    check("OAuth dialect → expected metrics", oauth == expected, "got \(oauth)")
    check("cookie dialect → expected metrics", cookie == expected, "got \(cookie)")
    check("both dialects are equivalent", oauth == cookie, "oauth=\(oauth)\n      cookie=\(cookie)")

    let partial = try ClaudeUsageParser.parse(Data(#"{ "five_hour": { "utilization": 7 } }"#.utf8),
                                              providerId: "claude")
    check("missing windows skipped (not fatal)",
          partial == [UsageMetric(label: "5-hour", pct: 7, providerId: "claude")])

    let empty = try ClaudeUsageParser.parse(Data("{}".utf8), providerId: "claude")
    check("empty object → no metrics", empty.isEmpty)
} catch {
    check("parser did not throw on valid fixtures", false, "\(error)")
}

do {
    _ = try ClaudeUsageParser.parse(Data("not json".utf8), providerId: "claude")
    check("malformed JSON throws .parse", false, "no error thrown")
} catch ProviderError.parse {
    check("malformed JSON throws .parse", true)
} catch {
    check("malformed JSON throws .parse", false, "wrong error: \(error)")
}

print("=== reset-date tolerance ===")
let micros = ClaudeUsageParser.parseResetDate("2026-06-16T11:39:59.602994+00:00")
let millis = ClaudeUsageParser.parseResetDate("2026-06-16T11:39:59.602+00:00")
check("microsecond precision normalizes to milliseconds", micros != nil && micros == millis)
check("plain timestamp parses", ClaudeUsageParser.parseResetDate("2026-06-22T05:59:59+00:00") != nil)
check("nil / empty → nil",
      ClaudeUsageParser.parseResetDate(nil) == nil && ClaudeUsageParser.parseResetDate("") == nil)

print("=== org selection ===")
do {
    let paid = try ClaudeCookieProvider.selectOrganization(from: fixture("organizations"))
    check("prefers paid org over free", paid == "org-paid-0002", "got \(paid)")

    let free = try ClaudeCookieProvider.selectOrganization(from: fixture("organizations_all_free"))
    check("falls back to first when none paid", free == "org-first-9001", "got \(free)")

    let idKey = try ClaudeCookieProvider.selectOrganization(
        from: Data(#"[{ "id": "org-id-key-7", "capabilities": ["claude_max"] }]"#.utf8))
    check("tolerates id key instead of uuid", idKey == "org-id-key-7", "got \(idKey)")
} catch {
    check("org selection did not throw on valid lists", false, "\(error)")
}
do {
    _ = try ClaudeCookieProvider.selectOrganization(from: Data("[]".utf8))
    check("empty org list throws", false, "no error thrown")
} catch {
    check("empty org list throws", true)
}

print("=== error surface ===")
check("needsLogin has a clear description",
      ProviderError.needsLogin.description.contains("Claude.ai"))

// === P1 slice (a): Claude OAuth credential source — discovery + file fallback + refresh ===
// Mirrors ClaudeAuthResolverTests.swift. All secrets here are OBVIOUSLY-FAKE placeholders,
// and no check prints a token value (only booleans / lengths), so grepping this output for
// a token-shaped string finds nothing.
print("=== oauth credential source (slice a) ===")

/// Build a Claude Code OAuth blob `{ "claudeAiOauth": { ... } }` with only the given keys.
func oauthBlobData(access: String?, expiresAt: Double? = nil, refresh: String? = nil) -> Data {
    var inner: [String: Any] = [:]
    if let access { inner["accessToken"] = access }
    if let expiresAt { inner["expiresAt"] = expiresAt }
    if let refresh { inner["refreshToken"] = refresh }
    return try! JSONSerialization.data(withJSONObject: ["claudeAiOauth": inner])
}

let fixedNow = Date(timeIntervalSince1970: 1_750_000_000) // deterministic clock for expiry
let pastMs = (fixedNow.timeIntervalSince1970 - 3600) * 1000
let futureMs = (fixedNow.timeIntervalSince1970 + 3600) * 1000
let clock: @Sendable () -> Date = { fixedNow }

/// Injected Keychain reader: yields data for `present` services, else `.notFound` (skip).
func keychainReader(_ present: [String: Data]) -> @Sendable (String) throws -> Data {
    { service in
        guard let d = present[service] else { throw CredentialError.notFound(service: service) }
        return d
    }
}

let FRESH = "sk-ant-oat01-FRESH-FOR-TESTS"
let fakeRefresher: ClaudeOAuthCredentialSource.Refresher = { rt in
    ClaudeOAuthCredentialSource.Blob(accessToken: FRESH, expiresAt: futureMs, refreshToken: rt)
}

@MainActor
func expectNoThrow(_ name: String, _ body: @MainActor () async throws -> Void) async {
    do { try await body() } catch { check(name, false, "threw \(error)") }
}

await expectNoThrow("ordered discovery + file fallback") {
    // 1) falls through to the classic "Claude Code" item when the primary is absent
    let a = ClaudeOAuthCredentialSource(
        services: ["Claude Code-credentials", "Claude Code"],
        keychainRead: keychainReader(["Claude Code": oauthBlobData(access: "sk-ant-oat01-FAKE-CLASSIC", expiresAt: futureMs)]),
        now: clock)
    check("discovery falls through to classic \"Claude Code\" item",
          try await a.resolveForFetch().accessToken == "sk-ant-oat01-FAKE-CLASSIC")

    // 2) primary "Claude Code-credentials" still wins when BOTH are present (no regression)
    let b = ClaudeOAuthCredentialSource(
        services: ["Claude Code-credentials", "Claude Code"],
        keychainRead: keychainReader([
            "Claude Code-credentials": oauthBlobData(access: "sk-ant-oat01-FAKE-PRIMARY", expiresAt: futureMs),
            "Claude Code": oauthBlobData(access: "sk-ant-oat01-FAKE-CLASSIC", expiresAt: futureMs),
        ]), now: clock)
    check("primary item wins when both present",
          try await b.resolveForFetch().accessToken == "sk-ant-oat01-FAKE-PRIMARY")

    // 3) ~/.claude/.credentials.json fallback when NO keychain item exists
    let c = ClaudeOAuthCredentialSource(
        services: ["Claude Code-credentials", "Claude Code"],
        keychainRead: keychainReader([:]),
        fileRead: { oauthBlobData(access: "sk-ant-oat01-FAKE-FILE", expiresAt: futureMs, refresh: "sk-ant-ort01-FAKE") },
        now: clock)
    check("file fallback used when no keychain item",
          try await c.resolveForFetch().accessToken == "sk-ant-oat01-FAKE-FILE")
}

// 4) usability semantics
func usabilitySrc(_ blob: Data?, refresher: ClaudeOAuthCredentialSource.Refresher? = nil) -> ClaudeOAuthCredentialSource {
    ClaudeOAuthCredentialSource(services: ["only"],
                                keychainRead: keychainReader(blob.map { ["only": $0] } ?? [:]),
                                refresher: refresher, now: clock)
}
check("unexpired token is usable",
      usabilitySrc(oauthBlobData(access: "sk-ant-oat01-FAKE", expiresAt: futureMs)).hasUsableToken())
check("expired + refreshToken + refresher wired ⇒ usable",
      usabilitySrc(oauthBlobData(access: "sk-ant-oat01-FAKE", expiresAt: pastMs, refresh: "sk-ant-ort01-FAKE"), refresher: fakeRefresher).hasUsableToken())
check("expired + refreshToken + NO refresher ⇒ unusable",
      usabilitySrc(oauthBlobData(access: "sk-ant-oat01-FAKE", expiresAt: pastMs, refresh: "sk-ant-ort01-FAKE")).hasUsableToken() == false)
check("expired + NO refreshToken ⇒ unusable",
      usabilitySrc(oauthBlobData(access: "sk-ant-oat01-FAKE", expiresAt: pastMs)).hasUsableToken() == false)
check("absent credential ⇒ unusable", usabilitySrc(nil).hasUsableToken() == false)

// 5) in-memory refresh yields the fresh token; unexpired is used as-is
await expectNoThrow("in-memory refresh of an expired token") {
    let stale = usabilitySrc(oauthBlobData(access: "sk-ant-oat01-FAKE-STALE", expiresAt: pastMs, refresh: "sk-ant-ort01-FAKE"), refresher: fakeRefresher)
    check("expired token refreshes in memory to a fresh token", try await stale.resolveForFetch().accessToken == FRESH)
    let live = usabilitySrc(oauthBlobData(access: "sk-ant-oat01-FAKE-LIVE", expiresAt: futureMs, refresh: "sk-ant-ort01-FAKE"), refresher: fakeRefresher)
    check("unexpired token used as-is (refresher NOT invoked)", try await live.resolveForFetch().accessToken == "sk-ant-oat01-FAKE-LIVE")
}

// 6) resolver preference (OAuth vs cookie) with injected source + cookie presence
func testResolver(oauthBlob: Data?, refresher: ClaudeOAuthCredentialSource.Refresher? = nil, cookie: Bool) -> ClaudeAuthResolver {
    ClaudeAuthResolver(oauthSource: usabilitySrc(oauthBlob, refresher: refresher), cookiePresent: { cookie })
}
let absent = testResolver(oauthBlob: nil, cookie: false)
check("absent credential ⇒ resolver reports OAuth absent", absent.hasUsableOAuthToken() == false)
check("absent credential ⇒ resolve() == .none (never throws)", absent.resolve() == .none)
check("cookie only ⇒ resolve() == .cookie", testResolver(oauthBlob: nil, cookie: true).resolve() == .cookie)
check("stale-but-refreshable OAuth preferred over cookie ⇒ .oauth",
      testResolver(oauthBlob: oauthBlobData(access: "sk-ant-oat01-FAKE", expiresAt: pastMs, refresh: "sk-ant-ort01-FAKE"), refresher: fakeRefresher, cookie: true).resolve() == .oauth)
check("expired + no refresh, cookie present ⇒ demote to cookie",
      testResolver(oauthBlob: oauthBlobData(access: "sk-ant-oat01-FAKE", expiresAt: pastMs), cookie: true).resolve() == .cookie)

// === Unit B2: redirect-guard host + scheme decision (SEC-01 / CORE-07) ===
// Mirrors HTTPRedirectGuardTests.swift. Pure host/scheme logic — no network, no
// credentials, no token values printed. Proves credential headers are forwarded
// ONLY across a same-site HTTPS redirect and stripped on a cross-site hop, a
// lookalike host, or an https→http downgrade.
print("=== redirect guard (sameSite + scheme) ===")
check("exact host is same-site",
      CredentialRedirectGuard.sameSite("claude.ai", "claude.ai"))
check("subdomain → base is same-site",
      CredentialRedirectGuard.sameSite("api.claude.ai", "claude.ai"))
check("base → subdomain is same-site",
      CredentialRedirectGuard.sameSite("claude.ai", "api.claude.ai"))
check("evil-claude.ai lookalike is NOT same-site",
      CredentialRedirectGuard.sameSite("evil-claude.ai", "claude.ai") == false)
check("unrelated host is NOT same-site",
      CredentialRedirectGuard.sameSite("example.com", "claude.ai") == false)
check("same-site https redirect forwards credentials",
      CredentialRedirectGuard.canForwardCredentials(
        fromHost: "claude.ai", to: URL(string: "https://claude.ai/api/organizations")))
check("https→http downgrade strips credentials",
      CredentialRedirectGuard.canForwardCredentials(
        fromHost: "claude.ai", to: URL(string: "http://claude.ai/api/organizations")) == false)
check("cross-site redirect strips credentials",
      CredentialRedirectGuard.canForwardCredentials(
        fromHost: "claude.ai", to: URL(string: "https://evil-claude.ai/api")) == false)
check("hostless redirect strips credentials",
      CredentialRedirectGuard.canForwardCredentials(fromHost: "claude.ai", to: nil) == false)

print("---")
if failures == 0 {
    print("PASS — \(checks) checks")
    exit(0)
} else {
    print("FAIL — \(failures)/\(checks) checks failed")
    exit(1)
}
