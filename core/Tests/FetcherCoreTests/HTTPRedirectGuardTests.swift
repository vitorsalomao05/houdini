import Testing
import Foundation
@testable import FetcherCore

/// Redirect-guard credential-safety logic (SEC-01 / CORE-07). Covers the pure
/// host comparison (`sameSite`) and the combined host+scheme decision
/// (`canForwardCredentials`) that governs whether the `Cookie` / `Authorization`
/// header may ride an HTTP redirect. All cases are pure — no network, no
/// credentials. `houdini-selftest` mirrors these assertions so they're observable
/// on a CommandLineTools-only machine where `swift test`'s runner no-ops.
@Suite struct HTTPRedirectGuardTests {

    // MARK: - sameSite (host only)

    @Test func exactHostIsSameSite() {
        #expect(CredentialRedirectGuard.sameSite("claude.ai", "claude.ai"))
    }

    @Test func subdomainOfBaseIsSameSite() {
        #expect(CredentialRedirectGuard.sameSite("api.claude.ai", "claude.ai"))
    }

    @Test func baseUnderSubdomainIsSameSite() {
        #expect(CredentialRedirectGuard.sameSite("claude.ai", "api.claude.ai"))
    }

    @Test func lookalikeHostIsNotSameSite() {
        // "evil-claude.ai" ends with "claude.ai" but NOT with ".claude.ai".
        #expect(CredentialRedirectGuard.sameSite("evil-claude.ai", "claude.ai") == false)
        #expect(CredentialRedirectGuard.sameSite("claude.ai", "evil-claude.ai") == false)
    }

    @Test func unrelatedHostIsNotSameSite() {
        #expect(CredentialRedirectGuard.sameSite("example.com", "claude.ai") == false)
    }

    // MARK: - canForwardCredentials (host + scheme)

    @Test func sameSiteHttpsRedirectForwardsCredentials() {
        #expect(CredentialRedirectGuard.canForwardCredentials(
            fromHost: "claude.ai", to: URL(string: "https://claude.ai/api/organizations")))
    }

    @Test func subdomainHttpsRedirectForwardsCredentials() {
        #expect(CredentialRedirectGuard.canForwardCredentials(
            fromHost: "api.anthropic.com", to: URL(string: "https://anthropic.com/api/oauth/usage")))
    }

    @Test func schemeDowngradeStripsCredentials() {
        // Same host, but https → http: cleartext, so headers must be dropped.
        #expect(CredentialRedirectGuard.canForwardCredentials(
            fromHost: "claude.ai", to: URL(string: "http://claude.ai/api/organizations")) == false)
    }

    @Test func crossSiteRedirectStripsCredentials() {
        #expect(CredentialRedirectGuard.canForwardCredentials(
            fromHost: "claude.ai", to: URL(string: "https://evil-claude.ai/api")) == false)
    }

    @Test func hostlessRedirectStripsCredentials() {
        #expect(CredentialRedirectGuard.canForwardCredentials(fromHost: "claude.ai", to: nil) == false)
    }
}
