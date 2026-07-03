import Foundation

/// `URLSession` delegate that strips credential headers (`Cookie`,
/// `Authorization`) from any redirect that isn't a **same-site HTTPS** hop.
/// Foundation's default redirect handling copies a manually-set
/// `Cookie`/`Authorization` header onto the redirected request even when it
/// targets a different host — or downgrades the scheme to cleartext `http` — so
/// an unexpected redirect could leak the session cookie or bearer token. This
/// guard keeps headers only when the target is the same registrable site *and*
/// still HTTPS, and removes them otherwise.
///
/// Wired in as the delegate of ``PinnedURLSession`` (process-wide). Stateless →
/// safe to share as a singleton.
public final class CredentialRedirectGuard: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    static let shared = CredentialRedirectGuard()

    public func urlSession(_ session: URLSession,
                           task: URLSessionTask,
                           willPerformHTTPRedirection response: HTTPURLResponse,
                           newRequest request: URLRequest,
                           completionHandler: @escaping (URLRequest?) -> Void) {
        if Self.canForwardCredentials(fromHost: task.originalRequest?.url?.host, to: request.url) {
            completionHandler(request) // same site, still HTTPS → preserve headers
        } else {
            var stripped = request
            stripped.setValue(nil, forHTTPHeaderField: "Cookie")
            stripped.setValue(nil, forHTTPHeaderField: "Authorization")
            completionHandler(stripped)
        }
    }

    /// Whether the `Cookie` / `Authorization` headers may ride a redirect from
    /// `originalHost` to `newURL`. Both conditions must hold: the target is the
    /// same registrable site, **and** the target is still HTTPS (no `https`→`http`
    /// downgrade). Any missing host/scheme falls through to `false` (strip).
    public static func canForwardCredentials(fromHost originalHost: String?, to newURL: URL?) -> Bool {
        guard let originalHost,
              let newHost = newURL?.host,
              sameSite(originalHost, newHost),
              newURL?.scheme?.lowercased() == "https"
        else { return false }
        return true
    }

    /// Same registrable site: identical hosts, or one a subdomain of the other.
    /// Conservative — anything else falls through to header stripping.
    public static func sameSite(_ a: String, _ b: String) -> Bool {
        a == b || a.hasSuffix("." + b) || b.hasSuffix("." + a)
    }
}
