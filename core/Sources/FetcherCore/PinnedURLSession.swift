import Foundation

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
}
