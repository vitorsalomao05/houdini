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

// === Unit C2: provider status mapping + refresh-retry + cookie flow (CORE-09/DX-05) ===
// Mirrors ProviderTransportTests.swift. The transport is a scripted fake — no network
// is touched. All credentials are OBVIOUSLY-FAKE placeholders and never printed.
print("=== provider transport: status mapping + refresh-retry + cookie flow ===")

/// Fake `HTTPTransport`: answers queued `(status, body)` steps in order, records requests.
final class ScriptedTransport: @unchecked Sendable {
    private let lock = NSLock()
    private var script: [(status: Int, body: Data)]
    private(set) var seen: [URLRequest] = []
    init(_ script: [(status: Int, body: Data)]) { self.script = script }
    var requests: [URLRequest] { lock.withLock { seen } }
    var transport: HTTPTransport {
        { request in
            let step: (status: Int, body: Data) = self.lock.withLock {
                self.seen.append(request)
                return self.script.isEmpty ? (599, Data()) : self.script.removeFirst()
            }
            let http = HTTPURLResponse(url: request.url!, statusCode: step.status,
                                       httpVersion: "HTTP/1.1", headerFields: nil)!
            return (step.body, http)
        }
    }
}

let LIVE = "sk-ant-oat01-FAKE-LIVE-C2"
let COOKIE = "sk-ant-sid01-FAKE-COOKIE-C2"

/// OAuth provider over a scripted transport holding an unexpired fake token
/// (optional refresh token / refresher). Pinned clientVersion → deterministic UA.
func oauthProvider(
    script: [(Int, Data)], refresh: String? = nil,
    refresher: ClaudeOAuthCredentialSource.Refresher? = nil
) -> (ClaudeOAuthProvider, ScriptedTransport) {
    let stub = ScriptedTransport(script)
    let source = ClaudeOAuthCredentialSource(
        services: ["only"],
        keychainRead: { _ in oauthBlobData(access: LIVE, expiresAt: futureMs, refresh: refresh) },
        refresher: refresher, now: clock)
    return (ClaudeOAuthProvider(source: source, clientVersion: "0.0.0-test",
                                transport: stub.transport), stub)
}

func cookieProvider(script: [(Int, Data)]) -> (ClaudeCookieProvider, ScriptedTransport) {
    let stub = ScriptedTransport(script)
    return (ClaudeCookieProvider(sessionKeyReader: { COOKIE },
                                 transport: stub.transport), stub)
}

/// Run `body` and check that it throws a ProviderError matching `matches`.
@MainActor
func checkThrows(_ name: String, matches: (ProviderError) -> Bool,
                 _ body: () async throws -> Void) async {
    do {
        try await body()
        check(name, false, "no error thrown")
    } catch let e as ProviderError {
        check(name, matches(e), "wrong case: \(e)")
    } catch {
        check(name, false, "wrong error type: \(error)")
    }
}

func isAuthExpired(_ e: ProviderError) -> Bool { if case .authExpired = e { true } else { false } }
func isNeedsLogin(_ e: ProviderError) -> Bool { if case .needsLogin = e { true } else { false } }
func isRateLimited(_ e: ProviderError) -> Bool { if case .rateLimited = e { true } else { false } }

// -- OAuth status mapping --
await expectNoThrow("OAuth 200 path") {
    let (p, stub) = oauthProvider(script: [(200, fixture("oauth_usage"))])
    let metrics = try await p.fetch()
    check("OAuth 200 → parsed metrics (one request)", metrics == expected && stub.requests.count == 1)
    let req = stub.requests.first
    check("OAuth sends Bearer token + claude-code User-Agent",
          req?.value(forHTTPHeaderField: "Authorization") == "Bearer \(LIVE)"
          && req?.value(forHTTPHeaderField: "User-Agent") == "claude-code/0.0.0-test")
}
await checkThrows("OAuth 401 → authExpired", matches: isAuthExpired) {
    _ = try await oauthProvider(script: [(401, Data())]).0.fetch()
}
await checkThrows("OAuth 403 → authExpired", matches: isAuthExpired) {
    _ = try await oauthProvider(script: [(403, Data())]).0.fetch()
}
await checkThrows("OAuth 429 → rateLimited", matches: isRateLimited) {
    _ = try await oauthProvider(script: [(429, Data())]).0.fetch()
}
await checkThrows("OAuth 5xx → http(status, body snippet)", matches: { e in
    if case .http(let status, let body) = e { status == 500 && body.contains("boom") } else { false }
}) {
    _ = try await oauthProvider(script: [(500, Data("boom".utf8))]).0.fetch()
}

// -- OAuth 401 → refresh → retry once (fake refresher; production wires none, ADR-012) --
await expectNoThrow("OAuth live-401 refresh-retry") {
    let (p, stub) = oauthProvider(script: [(401, Data()), (200, fixture("oauth_usage"))],
                                  refresh: "sk-ant-ort01-FAKE-C2", refresher: fakeRefresher)
    let metrics = try await p.fetch()
    check("OAuth live 401 + refresher → refresh + retry once → metrics",
          metrics == expected && stub.requests.count == 2
          && stub.requests.last?.value(forHTTPHeaderField: "Authorization") == "Bearer \(FRESH)")
}
do {
    let (p, stub) = oauthProvider(script: [(401, Data()), (401, Data())],
                                  refresh: "sk-ant-ort01-FAKE-C2", refresher: fakeRefresher)
    await checkThrows("OAuth refresh-retry happens exactly once (second 401 → authExpired)",
                      matches: { isAuthExpired($0) && stub.requests.count == 2 }) {
        _ = try await p.fetch()
    }
}
do {
    let (p, stub) = oauthProvider(script: [(401, Data())], refresh: "sk-ant-ort01-FAKE-C2")
    await checkThrows("OAuth 401 + refreshToken but NO refresher → authExpired, no retry",
                      matches: { isAuthExpired($0) && stub.requests.count == 1 }) {
        _ = try await p.fetch()
    }
}

// -- Cookie flow: orgs → usage, then status mapping --
await expectNoThrow("cookie happy flow") {
    let (p, stub) = cookieProvider(script: [(200, fixture("organizations")),
                                            (200, fixture("cookie_usage"))])
    let metrics = try await p.fetch()
    let expectedCookie = try ClaudeUsageParser.parse(fixture("cookie_usage"),
                                                     providerId: "claude-cookie")
    check("cookie flow: orgs → usage of the selected paid org",
          metrics == expectedCookie && stub.requests.count == 2
          && stub.requests.first?.url?.absoluteString == "https://claude.ai/api/organizations"
          && stub.requests.last?.url?.absoluteString
             == "https://claude.ai/api/organizations/org-paid-0002/usage")
    check("cookie header sent on both requests",
          stub.requests.allSatisfy {
              $0.value(forHTTPHeaderField: "Cookie") == "sessionKey=\(COOKIE)"
          })
}
do {
    let stub = ScriptedTransport([])
    let p = ClaudeCookieProvider(sessionKeyReader: { throw ProviderError.needsLogin },
                                 transport: stub.transport)
    await checkThrows("missing cookie → needsLogin with zero requests",
                      matches: { isNeedsLogin($0) && stub.requests.isEmpty }) {
        _ = try await p.fetch()
    }
}
await checkThrows("cookie 401 → needsLogin", matches: isNeedsLogin) {
    _ = try await cookieProvider(script: [(401, Data())]).0.fetch()
}
await checkThrows("cookie 429 → rateLimited", matches: isRateLimited) {
    _ = try await cookieProvider(script: [(429, Data())]).0.fetch()
}
await checkThrows("cookie 5xx → http(status, body snippet)", matches: { e in
    if case .http(let status, let body) = e { status == 503 && body.contains("overloaded") } else { false }
}) {
    _ = try await cookieProvider(script: [(503, Data("overloaded".utf8))]).0.fetch()
}

// === Phase E1: update resolver — semver, installed-read, GitHub resolve, state ===
// Mirrors UpdateResolverTests.swift. Pure logic + a scripted transport: no network,
// no filesystem, no credential. Proves the GitHub request carries no Authorization.
print("=== update resolver (E1) ===")

check("semver parses plain X.Y.Z",
      SemanticVersion("0.4.0") == SemanticVersion(major: 0, minor: 4, patch: 0))
check("semver parses v-prefix",
      SemanticVersion("v1.2.3") == SemanticVersion(major: 1, minor: 2, patch: 3))
check("semver rejects two-part", SemanticVersion("0.4") == nil)
check("semver rejects four-part", SemanticVersion("1.2.3.4") == nil)
check("semver compares numerically (0.9.0 < 0.10.0)",
      SemanticVersion("0.9.0")! < SemanticVersion("0.10.0")!)

func plistBytes(_ dict: [String: Any]) -> Data {
    try! PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
}
check("installed read from app plist → 0.4.0",
      InstalledVersion.read(plistPath: "/x",
        readData: { _ in plistBytes(["CFBundleShortVersionString": "0.4.0"]) })
        == SemanticVersion("0.4.0"))
check("installed missing file → nil (not installed)",
      InstalledVersion.read(plistPath: "/x", readData: { _ in nil }) == nil)
check("installed missing key → nil",
      InstalledVersion.read(plistPath: "/x",
        readData: { _ in plistBytes(["CFBundleName": "Houdini"]) }) == nil)

func releaseBytes(_ tag: String) -> Data { Data("{\"tag_name\":\"\(tag)\"}".utf8) }

await expectNoThrow("latest parses tag over scripted transport") {
    let stub = ScriptedTransport([(200, releaseBytes("v0.5.0"))])
    let v = try await ReleaseResolver.latest(transport: stub.transport)
    check("latest → 0.5.0, hits /releases/latest, sends NO Authorization",
          v == SemanticVersion("0.5.0")
          && stub.requests.first?.url?.absoluteString
             == "https://api.github.com/repos/vitorsalomao05/houdini/releases/latest"
          && stub.requests.first?.value(forHTTPHeaderField: "Authorization") == nil)
}
do {
    let stub = ScriptedTransport([(200, releaseBytes("garbage"))])
    do {
        _ = try await ReleaseResolver.latest(transport: stub.transport)
        check("latest rejects non-semver tag", false, "no throw")
    } catch { check("latest rejects non-semver tag", true) }
}
do {
    let stub = ScriptedTransport([(500, Data())])
    do {
        _ = try await ReleaseResolver.latest(transport: stub.transport)
        check("latest maps HTTP 500 → httpStatus", false, "no throw")
    } catch let e as UpdateError {
        check("latest maps HTTP 500 → httpStatus", e == .httpStatus(500), "\(e)")
    } catch { check("latest maps HTTP 500 → httpStatus", false, "wrong type \(error)") }
}
await expectNoThrow("resolve named tag hits tags endpoint") {
    let stub = ScriptedTransport([(200, releaseBytes("v0.3.0"))])
    let v = try await ReleaseResolver.resolve(tag: "0.3.0", transport: stub.transport)
    check("resolve 0.3.0 → tags/v0.3.0",
          v == SemanticVersion("0.3.0")
          && stub.requests.first?.url?.absoluteString
             == "https://api.github.com/repos/vitorsalomao05/houdini/releases/tags/v0.3.0")
}
do {
    let stub = ScriptedTransport([(404, Data())])
    do {
        _ = try await ReleaseResolver.resolve(tag: "99.0.0", transport: stub.transport)
        check("resolve 404 → tagNotFound", false, "no throw")
    } catch let e as UpdateError {
        check("resolve 404 → tagNotFound", e == .tagNotFound("v99.0.0"), "\(e)")
    } catch { check("resolve 404 → tagNotFound", false, "wrong type \(error)") }
}
do {
    let stub = ScriptedTransport([(200, releaseBytes("v0.3.0"))])
    do {
        _ = try await ReleaseResolver.resolve(tag: "not-a-version", transport: stub.transport)
        check("resolve bad version rejected before any request", false, "no throw")
    } catch { check("resolve bad version rejected before any request", stub.requests.isEmpty) }
}

let e1Latest = SemanticVersion("0.5.0")!
check("state: nil installed → notInstalled",
      UpdateStatus(installed: nil, latest: e1Latest).state == .notInstalled)
check("state: older installed → updateAvailable",
      UpdateStatus(installed: SemanticVersion("0.4.0"), latest: e1Latest).state == .updateAvailable)
check("state: equal → upToDate",
      UpdateStatus(installed: SemanticVersion("0.5.0"), latest: e1Latest).state == .upToDate)
check("state: newer installed → ahead",
      UpdateStatus(installed: SemanticVersion("0.6.0"), latest: e1Latest).state == .ahead)

// === Phase E2: update mutation — delegated install with rollback ===
// Mirrors UpdateInstallerTests.swift. In-memory fake env: no real fs, no network, no
// spawned installer — the destructive path is safe to exercise. Plus the detached-spawn
// primitive (real, harmless /bin/sh spawns) proving no controlling terminal (R3.4).
print("=== update mutation (E2) ===")

final class FakeInstall: @unchecked Sendable {
    let cli = "/home/.local/bin/houdini"
    let app = "/home/Applications/Houdini.app"
    var paths: Set<String> = []
    var versionAt: [String: SemanticVersion] = [:]
    var running: String?
    var resolve: Result<SemanticVersion, Error>
    var fetch: Result<String, Error>
    enum Behavior { case ok(SemanticVersion); case exits(Int32); case fails(Error) }
    var behavior: Behavior
    var moves = 0
    init(installed: SemanticVersion? = SemanticVersion("0.4.0"),
         resolveTo: SemanticVersion = SemanticVersion("0.5.0")!,
         tag: String = "v0.5.0",
         installs: SemanticVersion = SemanticVersion("0.5.0")!) {
        resolve = .success(resolveTo)
        fetch = .success("REPO=\"x\"\nTAG=\"\(tag)\"\n")
        behavior = .ok(installs)
        paths.insert(cli); running = cli
        if let installed { paths.insert(app); versionAt[app] = installed }
    }
    enum E: Error { case missing }
    func inst() -> UpdateInstaller {
        UpdateInstaller(
            managedCLIPath: cli, appPath: app,
            runningCLIPath: { self.running },
            pathExists: { self.paths.contains($0) },
            move: { f, t in
                guard self.paths.contains(f) else { throw E.missing }
                self.paths.remove(f); self.paths.insert(t)
                self.versionAt[t] = self.versionAt[f]; self.versionAt[f] = nil
                self.moves += 1
            },
            remove: { self.paths.remove($0); self.versionAt[$0] = nil },
            installedVersion: { self.versionAt[self.app] },
            resolveVersion: { _ in try self.resolve.get() },
            fetchInstaller: { _ in try self.fetch.get() },
            runInstaller: { _, _ in
                switch self.behavior {
                case .ok(let v):
                    self.paths.insert(self.app); self.paths.insert(self.cli)
                    self.versionAt[self.app] = v; return 0
                case .exits(let c): return c
                case .fails(let e): throw e
                }
            })
    }
    func clean(_ v: SemanticVersion?) -> Bool {
        let want: Set<String> = v == nil ? [cli] : [cli, app]
        return paths == want && versionAt[app] == v
    }
}

func isFailed(_ o: UpdateOutcome) -> Bool { if case .failed = o { true } else { false } }
func isRefused(_ o: UpdateOutcome) -> Bool { if case .refused = o { true } else { false } }

check("parseInstallerTag reads TAG line",
      UpdateInstaller.parseInstallerTag("REPO=\"x\"\nTAG=\"v0.5.0\"\n") == SemanticVersion("0.5.0"))
check("parseInstallerTag ignores commented TAG",
      UpdateInstaller.parseInstallerTag("# TAG=\"v9.9.9\"\nTAG=\"v0.6.0\" # bump\n") == SemanticVersion("0.6.0"))
check("samePath canonical equal / not-equal",
      UpdateInstaller.samePath("/a/houdini", "/a/houdini")
      && !UpdateInstaller.samePath("/a/houdini", "/b/houdini"))

do {
    let e = FakeInstall()
    let o = await e.inst().run(target: .latest)
    check("happy update → .updated(0.4.0→0.5.0), stashes cleaned",
          o == .updated(from: SemanticVersion("0.4.0"), to: SemanticVersion("0.5.0")!)
          && e.clean(SemanticVersion("0.5.0")))
}
do {
    let e = FakeInstall(installed: SemanticVersion("0.5.0"), resolveTo: SemanticVersion("0.5.0")!)
    let o = await e.inst().run(target: .latest)
    check("already current → no-op, no moves", o == .alreadyCurrent(SemanticVersion("0.5.0")!) && e.moves == 0)
}
do {
    let e = FakeInstall(); e.behavior = .exits(1)                       // e.g. shasum mismatch → die
    let o = await e.inst().run(target: .latest)
    var restored = false
    if case .failed(_, let unchanged, let cleanRB) = o { restored = (unchanged == SemanticVersion("0.4.0") && cleanRB) }
    check("installer failure → restore to 0.4.0", restored && e.clean(SemanticVersion("0.4.0")))
}
do {
    let e = FakeInstall(tag: "v9.9.9")
    let o = await e.inst().run(target: .latest)
    check("TAG mismatch → failed before any move", isFailed(o) && e.moves == 0)
}
do {
    let e = FakeInstall(); e.running = "/usr/local/bin/houdini"
    let o = await e.inst().run(target: .latest)
    check("unmanaged install → refused, nothing touched", isRefused(o) && e.moves == 0)
}
do {
    let e = FakeInstall(); e.behavior = .ok(SemanticVersion("0.4.9")!)  // exit 0 but wrong version
    let o = await e.inst().run(target: .latest)
    check("post-install wrong version → rolled back to 0.4.0", isFailed(o) && e.clean(SemanticVersion("0.4.0")))
}
do {
    struct Boom: Error {}
    let e = FakeInstall(); e.behavior = .fails(Boom())
    let o = await e.inst().run(target: .latest)
    check("installer throw (Ctrl-C-like) → restore", isFailed(o) && e.clean(SemanticVersion("0.4.0")))
}
do {
    // Bare `update` on an ahead build (dev 1.0.0, latest 0.5.0) must NOT downgrade.
    let e = FakeInstall(installed: SemanticVersion("1.0.0"), resolveTo: SemanticVersion("0.5.0")!)
    let o = await e.inst().run(target: .latest)
    check("bare update on an ahead build → .ahead, no downgrade",
          o == .ahead(installed: SemanticVersion("1.0.0")!, latest: SemanticVersion("0.5.0")!) && e.moves == 0)
}
do {
    let e = FakeInstall(installed: SemanticVersion("0.5.0"), resolveTo: SemanticVersion("0.3.0")!,
                        tag: "v0.3.0", installs: SemanticVersion("0.3.0")!)
    let o = await e.inst().run(target: .version("0.3.0"))
    check("named downgrade when tag exists → updated",
          o == .updated(from: SemanticVersion("0.5.0"), to: SemanticVersion("0.3.0")!) && e.clean(SemanticVersion("0.3.0")))
}
do {
    let e = FakeInstall(); e.resolve = .failure(UpdateError.tagNotFound("v0.3.0"))
    let o = await e.inst().run(target: .version("0.3.0"))
    check("404 named version → failed, no moves", isFailed(o) && e.moves == 0)
}
do {
    let e = FakeInstall(installed: nil)
    let o = await e.inst().run(target: .latest)
    check("fresh install when app missing → installedFresh",
          o == .installedFresh(SemanticVersion("0.5.0")!) && e.clean(SemanticVersion("0.5.0")))
}

// Detached spawn primitive — real but harmless /bin/sh spawns.
let e2ExitCode = try? DetachedProcess.run("/bin/sh", ["/bin/sh", "-c", "exit 42"], env: ["PATH": "/usr/bin:/bin"])
check("detached run returns child exit code (42)", e2ExitCode == 42)
let e2Tty = try? DetachedProcess.run("/bin/sh",
    ["/bin/sh", "-c", "if : 2>/dev/null >/dev/tty; then exit 0; else exit 3; fi"],
    env: ["PATH": "/usr/bin:/bin"])
check("detached run has NO controlling terminal (/dev/tty unavailable)", e2Tty == 3)

print("---")
// DX-06 parity guard: the pinned number of checks this mirror must run — 53 prior
// (38 baseline + 15 unit-C2 provider checks) + 18 Phase-E1 update-resolver + 16
// Phase-E2 update-mutation checks. Adding/removing a check above (or a mirrored @Test)
// means updating this pin in the SAME commit; any mismatch fails the run, so silent
// mirror drift is impossible.
let pinnedCheckCount = 87
if checks != pinnedCheckCount {
    failures += 1
    print("  ✘ parity — expected exactly \(pinnedCheckCount) checks, ran \(checks) (mirror drift? update the pin)")
}

if failures == 0 {
    print("PASS — \(checks) checks (pinned \(pinnedCheckCount))")
    exit(0)
} else {
    print("FAIL — \(failures)/\(checks) checks failed")
    exit(1)
}
