import Testing
import Foundation
@testable import FetcherCore

/// Unit C2 (CORE-09 / DX-05): the risky live paths, exercised through the injected
/// `HTTPTransport` seam — no network, no Keychain, no disk. Covers the HTTP
/// status→`ProviderError` mapping of both providers, the OAuth 401→refresh→retry-once
/// branch (fake, injected refresher — production still wires none, ADR-012), and the
/// cookie provider's two-request orgs→usage flow. All credentials are OBVIOUSLY-FAKE
/// placeholders and no assertion ever prints one. `houdini-selftest` mirrors these
/// checks so they're observable on a CommandLineTools-only machine where `swift test`'s
/// runner no-ops.

// MARK: - Scripted transport

/// Fake `HTTPTransport`: answers queued `(status, body)` steps in order and records
/// every request it saw. Class + lock (not an actor) so tests can assert on the
/// recorded requests synchronously after the fetch completes.
final class TransportStub: @unchecked Sendable {
    private let lock = NSLock()
    private var script: [(status: Int, body: Data)]
    private var seen: [URLRequest] = []

    init(_ script: [(status: Int, body: Data)]) { self.script = script }

    var requests: [URLRequest] { lock.withLock { seen } }

    var transport: HTTPTransport {
        { request in
            let step: (status: Int, body: Data) = self.lock.withLock {
                self.seen.append(request)
                // An exhausted script is a test bug: answer an unmistakable 599.
                return self.script.isEmpty ? (599, Data()) : self.script.removeFirst()
            }
            let http = HTTPURLResponse(url: request.url!, statusCode: step.status,
                                       httpVersion: "HTTP/1.1", headerFields: nil)!
            return (step.body, http)
        }
    }
}

private func fixtureData(_ name: String) throws -> Data {
    let url = try #require(
        Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"),
        "missing fixture \(name).json")
    return try Data(contentsOf: url)
}

// MARK: - OAuth provider: status mapping + refresh-retry

@Suite struct ClaudeOAuthProviderTransportTests {

    static let fixedNow = Date(timeIntervalSince1970: 1_750_000_000)
    static var futureMs: Double { (fixedNow.timeIntervalSince1970 + 3600) * 1000 }
    static let liveToken = "sk-ant-oat01-FAKE-LIVE-C2"
    static let freshToken = "sk-ant-oat01-FRESH-C2"
    static let refreshToken = "sk-ant-ort01-FAKE-C2"

    /// A refresher that always yields the fresh, unexpired fake token.
    static let refresher: ClaudeOAuthCredentialSource.Refresher = { rt in
        ClaudeOAuthCredentialSource.Blob(
            accessToken: freshToken, expiresAt: futureMs, refreshToken: rt)
    }

    /// Provider over a scripted transport, holding an unexpired fake token (plus an
    /// optional refresh token / refresher). Pinned `clientVersion` keeps the UA
    /// deterministic and skips the `claude --version` probe.
    func provider(
        script: [(Int, Data)],
        refresh: String? = nil,
        refresher: ClaudeOAuthCredentialSource.Refresher? = nil
    ) -> (ClaudeOAuthProvider, TransportStub) {
        var inner: [String: Any] = ["accessToken": Self.liveToken, "expiresAt": Self.futureMs]
        if let refresh { inner["refreshToken"] = refresh }
        let blob = try! JSONSerialization.data(withJSONObject: ["claudeAiOauth": inner])
        let source = ClaudeOAuthCredentialSource(
            services: ["only"],
            keychainRead: { _ in blob },
            refresher: refresher,
            now: { Self.fixedNow })
        let stub = TransportStub(script)
        let p = ClaudeOAuthProvider(source: source, clientVersion: "0.0.0-test",
                                    transport: stub.transport)
        return (p, stub)
    }

    @Test func okParsesUsagePayload() async throws {
        let usage = try fixtureData("oauth_usage")
        let (p, stub) = provider(script: [(200, usage)])
        let metrics = try await p.fetch()
        #expect(metrics == (try ClaudeUsageParser.parse(usage, providerId: "claude")))
        #expect(stub.requests.count == 1)
    }

    @Test func sendsBearerAndClaudeCodeUserAgent() async throws {
        let (p, stub) = provider(script: [(200, try fixtureData("oauth_usage"))])
        _ = try await p.fetch()
        let request = try #require(stub.requests.first)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer \(Self.liveToken)")
        #expect(request.value(forHTTPHeaderField: "User-Agent") == "claude-code/0.0.0-test")
    }

    @Test func unauthorizedMapsToAuthExpired() async {
        let (p, stub) = provider(script: [(401, Data())])
        do {
            _ = try await p.fetch()
            Issue.record("expected .authExpired, got success")
        } catch ProviderError.authExpired {
            // expected — and with no refresh token there is no second attempt.
            #expect(stub.requests.count == 1)
        } catch {
            Issue.record("expected .authExpired, got \(error)")
        }
    }

    @Test func forbiddenMapsToAuthExpired() async {
        let (p, _) = provider(script: [(403, Data())])
        do {
            _ = try await p.fetch()
            Issue.record("expected .authExpired, got success")
        } catch ProviderError.authExpired {
        } catch {
            Issue.record("expected .authExpired, got \(error)")
        }
    }

    @Test func rateLimitMapsToRateLimited() async {
        let (p, _) = provider(script: [(429, Data())])
        do {
            _ = try await p.fetch()
            Issue.record("expected .rateLimited, got success")
        } catch ProviderError.rateLimited {
        } catch {
            Issue.record("expected .rateLimited, got \(error)")
        }
    }

    @Test func serverErrorMapsToHTTPWithBodySnippet() async {
        let (p, _) = provider(script: [(500, Data("boom".utf8))])
        do {
            _ = try await p.fetch()
            Issue.record("expected .http, got success")
        } catch ProviderError.http(let status, let body) {
            #expect(status == 500)
            #expect(body.contains("boom"))
        } catch {
            Issue.record("expected .http, got \(error)")
        }
    }

    @Test func liveUnauthorizedRefreshesAndRetriesOnce() async throws {
        let usage = try fixtureData("oauth_usage")
        let (p, stub) = provider(script: [(401, Data()), (200, usage)],
                                 refresh: Self.refreshToken, refresher: Self.refresher)
        let metrics = try await p.fetch()
        #expect(metrics == (try ClaudeUsageParser.parse(usage, providerId: "claude")))
        #expect(stub.requests.count == 2)
        // The retry carries the refreshed token, not the rejected one.
        #expect(stub.requests.last?.value(forHTTPHeaderField: "Authorization")
                == "Bearer \(Self.freshToken)")
    }

    @Test func refreshRetryHappensExactlyOnce() async {
        // Refresh succeeds but the endpoint rejects the fresh token too:
        // the second .authExpired must propagate — no loop, no third request.
        let (p, stub) = provider(script: [(401, Data()), (401, Data())],
                                 refresh: Self.refreshToken, refresher: Self.refresher)
        do {
            _ = try await p.fetch()
            Issue.record("expected .authExpired, got success")
        } catch ProviderError.authExpired {
            #expect(stub.requests.count == 2)
        } catch {
            Issue.record("expected .authExpired, got \(error)")
        }
    }

    @Test func noRefresherLeavesAuthExpired() async {
        // A refresh token alone can't help while production wires no refresher (ADR-012).
        let (p, stub) = provider(script: [(401, Data())], refresh: Self.refreshToken)
        do {
            _ = try await p.fetch()
            Issue.record("expected .authExpired, got success")
        } catch ProviderError.authExpired {
            #expect(stub.requests.count == 1)
        } catch {
            Issue.record("expected .authExpired, got \(error)")
        }
    }
}

// MARK: - Cookie provider: orgs→usage flow + status mapping

@Suite struct ClaudeCookieProviderFlowTests {

    static let sessionKey = "sk-ant-sid01-FAKE-COOKIE-C2"

    func provider(script: [(Int, Data)]) -> (ClaudeCookieProvider, TransportStub) {
        let stub = TransportStub(script)
        let p = ClaudeCookieProvider(sessionKeyReader: { Self.sessionKey },
                                     transport: stub.transport)
        return (p, stub)
    }

    @Test func happyFlowFetchesOrgsThenUsage() async throws {
        let orgs = try fixtureData("organizations")
        let usage = try fixtureData("cookie_usage")
        let (p, stub) = provider(script: [(200, orgs), (200, usage)])
        let metrics = try await p.fetch()
        #expect(metrics == (try ClaudeUsageParser.parse(usage, providerId: "claude-cookie")))
        // Two GETs, in order: /api/organizations, then usage for the selected PAID org.
        #expect(stub.requests.count == 2)
        #expect(stub.requests.first?.url == ClaudeCookieProvider.orgsURL)
        #expect(stub.requests.last?.url == ClaudeCookieProvider.usageURL(orgId: "org-paid-0002"))
    }

    @Test func sendsSessionKeyCookieOnBothRequests() async throws {
        let (p, stub) = provider(script: [
            (200, try fixtureData("organizations")), (200, try fixtureData("cookie_usage")),
        ])
        _ = try await p.fetch()
        for request in stub.requests {
            #expect(request.value(forHTTPHeaderField: "Cookie") == "sessionKey=\(Self.sessionKey)")
        }
    }

    @Test func missingCookieMapsToNeedsLoginWithoutAnyRequest() async {
        // Mirrors the production reader's CredentialError.notFound → .needsLogin mapping.
        let stub = TransportStub([])
        let p = ClaudeCookieProvider(sessionKeyReader: { throw ProviderError.needsLogin },
                                     transport: stub.transport)
        do {
            _ = try await p.fetch()
            Issue.record("expected .needsLogin, got success")
        } catch ProviderError.needsLogin {
            #expect(stub.requests.isEmpty)
        } catch {
            Issue.record("expected .needsLogin, got \(error)")
        }
    }

    @Test func unauthorizedMapsToNeedsLogin() async {
        let (p, stub) = provider(script: [(401, Data())])
        do {
            _ = try await p.fetch()
            Issue.record("expected .needsLogin, got success")
        } catch ProviderError.needsLogin {
            #expect(stub.requests.count == 1)
        } catch {
            Issue.record("expected .needsLogin, got \(error)")
        }
    }

    @Test func rateLimitMapsToRateLimited() async {
        let (p, _) = provider(script: [(429, Data())])
        do {
            _ = try await p.fetch()
            Issue.record("expected .rateLimited, got success")
        } catch ProviderError.rateLimited {
        } catch {
            Issue.record("expected .rateLimited, got \(error)")
        }
    }

    @Test func serverErrorMapsToHTTPWithBodySnippet() async {
        let (p, _) = provider(script: [(503, Data("overloaded".utf8))])
        do {
            _ = try await p.fetch()
            Issue.record("expected .http, got success")
        } catch ProviderError.http(let status, let body) {
            #expect(status == 503)
            #expect(body.contains("overloaded"))
        } catch {
            Issue.record("expected .http, got \(error)")
        }
    }
}
