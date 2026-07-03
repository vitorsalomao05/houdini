import Foundation

/// One HTTP round trip (`URLRequest` → `(Data, URLResponse)`). Providers hold this as
/// an injectable seam — the same closure-seam style as `ClaudeOAuthCredentialSource`'s
/// `keychainRead` and `ClaudeCookieProvider`'s `sessionKeyReader` — so tests and the
/// `houdini-selftest` mirror can script status codes and bodies without any network.
/// Every production caller uses ``PinnedURLSession/transport``, so injecting a fake in
/// tests never changes what ships.
public typealias HTTPTransport = @Sendable (URLRequest) async throws -> (Data, URLResponse)

/// The single process-wide `URLSession` every credentialed Houdini request goes
/// through. It is built from an **ephemeral** configuration with cookie storage
/// and the disk cache turned off, so a token- or cookie-bearing GET can never
/// deposit a `Set-Cookie` into persistent `HTTPCookieStorage`
/// (`~/Library/HTTPStorages/…`) or a cacheable response into `Cache.db` on disk.
/// The "nothing hits disk" guardrail is thereby enforced by client configuration
/// rather than by trusting the server's cache/cookie response headers (SEC-01).
///
/// `CredentialRedirectGuard` is wired in as the session-level delegate, so any
/// cross-site or scheme-downgraded (`https`→`http`) redirect has its `Cookie` /
/// `Authorization` header stripped before the request is re-issued (CORE-07).
///
/// One shared instance is safe: `URLSession` is thread-safe and the configuration
/// is immutable after construction, so there is no per-request state to leak
/// between providers. All FetcherCore network calls (both Claude providers today,
/// and any future adapter or the `houdini update` check) must go through it.
public enum PinnedURLSession {
    public static let shared: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false          // never send stored cookies
        config.httpCookieAcceptPolicy = .never       // never accept Set-Cookie
        config.httpCookieStorage = nil               // no cookie jar at all
        config.urlCache = nil                         // no response cache (disk or memory)
        config.timeoutIntervalForRequest = 20         // explicit ~20s per-request ceiling
        return URLSession(
            configuration: config,
            delegate: CredentialRedirectGuard.shared,
            delegateQueue: nil
        )
    }()

    /// The production ``HTTPTransport``: one `data(for:)` round trip through the hardened
    /// `shared` session above. This is the default for every provider's transport seam,
    /// so the hardening (ephemeral config, no cookie jar, no cache, 20s ceiling,
    /// credential-stripping redirect guard) is what ships unless a test injects a fake.
    public static let transport: HTTPTransport = { try await shared.data(for: $0) }
}
