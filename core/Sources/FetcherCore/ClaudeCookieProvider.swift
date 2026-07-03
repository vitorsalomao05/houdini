import Foundation

/// Claude Pro/Max provider via the **claude.ai session cookie** (`sessionKey`,
/// `sk-ant-sid01-…`) — the fallback auth for users who don't run Claude Code
/// (PROVIDERS.md → "claude", `.sessionCookie`).
///
/// Flow: read the cookie from the Keychain → `GET /api/organizations` (pick the
/// org) → `GET /api/organizations/{id}/usage` → normalize with the shared
/// `ClaudeUsageParser`. The cookie is read from the Keychain only and is **never
/// logged**. A 401/403 surfaces as `ProviderError.needsLogin` so the UI can
/// re-run the WebView login.
public struct ClaudeCookieProvider: UsageProvider {
    public let id = "claude-cookie"
    public let displayName = "Claude (Pro/Max)"
    public let authMethod: AuthMethod = .sessionCookie
    // Same capabilities as the OAuth path: %, reset timers, and "Claude Extra" $.
    public let capabilities: Capabilities = [.usagePct, .resetTimer, .dollarBalance]
    public let refreshInterval: TimeInterval = 60

    /// Keychain coordinates for the cookie Houdini captures via its WebView login.
    /// Distinct from the Claude Code OAuth item — this one is created and owned by
    /// Houdini itself, so the app reads it back silently.
    public static let keychainService = "Houdini-claude-session"
    public static let keychainAccount = "sessionKey"

    static let orgsURL = URL(string: "https://claude.ai/api/organizations")!
    static func usageURL(orgId: String) -> URL {
        URL(string: "https://claude.ai/api/organizations/\(orgId)/usage")!
    }

    /// Reads the `sessionKey` cookie value. Injectable so tests never touch the
    /// Keychain or the network. Default reads Houdini's own Keychain item natively.
    private let sessionKeyReader: @Sendable () throws -> String
    private let transport: HTTPTransport

    public init(store: CredentialStore = CredentialStore()) {
        self.transport = PinnedURLSession.transport
        self.sessionKeyReader = {
            let data: Data
            do {
                // Houdini created this item, so the native path reads it without a prompt.
                data = try store.nativeReadGenericPassword(
                    service: Self.keychainService, account: Self.keychainAccount
                )
            } catch CredentialError.notFound {
                throw ProviderError.needsLogin
            } catch {
                throw ProviderError.credential("\(error)")
            }
            let key = (String(data: data, encoding: .utf8) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { throw ProviderError.needsLogin }
            return key
        }
    }

    /// Injection seam (tests / the `houdini-selftest` mirror): inject the cookie value
    /// directly (no Keychain) and optionally a scripted transport (no network). `public`
    /// for the same reason the `ClaudeOAuthCredentialSource` seam is: the selftest
    /// executable (plain `import FetcherCore`) must drive these assertions on a
    /// CommandLineTools-only machine. Defaults keep production behavior identical
    /// (`PinnedURLSession.transport`).
    public init(
        sessionKeyReader: @escaping @Sendable () throws -> String,
        transport: @escaping HTTPTransport = PinnedURLSession.transport
    ) {
        self.sessionKeyReader = sessionKeyReader
        self.transport = transport
    }

    public func fetch() async throws -> [UsageMetric] {
        let sessionKey = try sessionKeyReader()
        let orgsData = try await get(Self.orgsURL, sessionKey: sessionKey)
        let orgId = try Self.selectOrganization(from: orgsData)
        let usageData = try await get(Self.usageURL(orgId: orgId), sessionKey: sessionKey)
        return try ClaudeUsageParser.parse(usageData, providerId: id)
    }

    // MARK: - HTTP

    /// Authenticated GET against claude.ai. Sends only the `sessionKey` cookie (never
    /// logged) plus a browser-like User-Agent the web API expects. Maps auth/rate
    /// failures to typed `ProviderError`s.
    private func get(_ url: URL, sessionKey: String) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("sessionKey=\(sessionKey)", forHTTPHeaderField: "Cookie")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        // claude.ai's web API rejects obviously-non-browser clients; send a plausible UA.
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 "
            + "(KHTML, like Gecko) Version/17.0 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )

        let data: Data
        let response: URLResponse
        do {
            // Default transport = PinnedURLSession: ephemeral, cookie-jar-less, cache-less;
            // its redirect guard never lets the sessionKey follow a redirect off claude.ai.
            (data, response) = try await transport(request)
        } catch {
            throw ProviderError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw ProviderError.network("response was not HTTP")
        }
        switch http.statusCode {
        case 200:
            return data
        case 401, 403:
            throw ProviderError.needsLogin
        case 429:
            throw ProviderError.rateLimited
        default:
            let snippet = String(data: data.prefix(300), encoding: .utf8) ?? "<binary>"
            throw ProviderError.http(status: http.statusCode, body: snippet)
        }
    }

    // MARK: - Organization selection

    /// Choose which organization's usage to report from `GET /api/organizations`.
    ///
    /// Rule (documented in PROVIDERS.md): prefer an org on a **paid/active plan**
    /// — detected via a paid `capabilities` marker (e.g. `claude_pro`, `claude_max`,
    /// `raven`, `enterprise`) or a non-free `billing_type` — and among those, the
    /// first listed. If none look clearly paid, fall back to the first org. The
    /// parse is tolerant of `uuid`/`id` key naming and missing optional fields.
    public static func selectOrganization(from data: Data) throws -> String {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let orgs: [Org]
        do {
            orgs = try decoder.decode([Org].self, from: data)
        } catch {
            throw ProviderError.parse("organizations: \(error)")
        }
        guard !orgs.isEmpty else {
            throw ProviderError.parse("no organizations returned for this account")
        }
        // 1) Prefer an org on a paid/active plan.
        if let paid = orgs.first(where: { $0.isPaid }), let id = paid.id {
            return id
        }
        // 2) Otherwise the first org with a usable id.
        if let id = orgs.compactMap(\.id).first {
            return id
        }
        throw ProviderError.parse("organizations had no usable uuid/id")
    }

    /// Tolerant org record. Accepts `uuid` or `id`; reads optional `capabilities`
    /// and `billing_type` to detect a paid plan.
    private struct Org: Decodable {
        let id: String?
        let capabilities: [String]?
        let billingType: String?

        private enum Keys: String, CodingKey {
            case uuid, id, capabilities, billingType
        }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: Keys.self)
            id = try c.decodeIfPresent(String.self, forKey: .uuid)
                ?? c.decodeIfPresent(String.self, forKey: .id)
            capabilities = try c.decodeIfPresent([String].self, forKey: .capabilities)
            billingType = try c.decodeIfPresent(String.self, forKey: .billingType)
        }

        /// A paid/active marker in `capabilities`, or any non-"free" `billing_type`.
        var isPaid: Bool {
            let paidCaps: Set<String> = [
                "claude_pro", "claude_max", "pro", "max", "raven",
                "team", "claude_team", "enterprise", "claude_enterprise",
            ]
            if let caps = capabilities,
               caps.contains(where: { paidCaps.contains($0.lowercased()) }) {
                return true
            }
            if let billing = billingType?.lowercased(), !billing.isEmpty, billing != "free" {
                return true
            }
            return false
        }
    }
}
