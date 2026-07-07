import Foundation

// Update resolution — the READ-ONLY half of `houdini update` (audit 07/08 · Phase E1).
//
// Everything here answers one question without touching disk: "what version is
// installed, what is the latest (or a named) release, and is an update available?".
// It lives in FetcherCore (not the `houdini` executable target) so both the CLI and
// the test targets — `FetcherCoreTests` and the `houdini-selftest` mirror — can drive
// it through injected seams with no network and no filesystem writes.
//
// The GitHub call goes through `PinnedURLSession` like every other FetcherCore
// request (ephemeral config, no cookie jar, no disk cache, 20s ceiling) and carries
// NO credential — it is a public, tokenless GET. The mutation (fetch + delegate to
// install.sh + rollback) lives separately in the update installer (Phase E2).

// MARK: - Semantic version

/// A minimal `major.minor.patch` version, tolerant of a leading `v`. Houdini's
/// releases are always plain `vX.Y.Z` tags (RELEASE.md / `install.sh`), so a strict
/// three-component parse is all the update tooling needs — anything that is not a
/// non-negative integer triple is rejected rather than guessed at.
public struct SemanticVersion: Comparable, CustomStringConvertible, Sendable, Hashable {
    public let major: Int
    public let minor: Int
    public let patch: Int

    public init(major: Int, minor: Int, patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    /// Parse `"v0.4.0"` / `"0.4.0"`. Returns `nil` for anything that is not a
    /// non-negative `X.Y.Z` triple (no ranges, no pre-release/build suffixes).
    public init?(_ raw: String) {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let first = s.first, first == "v" || first == "V" { s.removeFirst() }
        let parts = s.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3,
              let mj = Int(parts[0]), let mn = Int(parts[1]), let pt = Int(parts[2]),
              mj >= 0, mn >= 0, pt >= 0
        else { return nil }
        self.init(major: mj, minor: mn, patch: pt)
    }

    /// The bare `X.Y.Z` string (no `v`). Prefix with `v` where a tag is needed.
    public var description: String { "\(major).\(minor).\(patch)" }

    public static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }
}

// MARK: - Installed version (from the app bundle)

/// Reads the one authoritative on-disk version marker: the installed app bundle's
/// `CFBundleShortVersionString` (`install.sh` places the app at
/// `~/Applications/Houdini.app`). Strictly read-only.
public enum InstalledVersion {
    /// `~/Applications/Houdini.app/Contents/Info.plist` — the fixed install path.
    public static var defaultPlistPath: String {
        NSHomeDirectory() + "/Applications/Houdini.app/Contents/Info.plist"
    }

    /// Read `CFBundleShortVersionString` from the app plist. Returns `nil` when the
    /// app is absent (no file → `readData` yields `nil`) or the value is missing/
    /// malformed — callers treat `nil` as "not installed". The `readData` seam lets
    /// tests inject plist bytes with no filesystem access; the default never writes.
    public static func read(
        plistPath: String = defaultPlistPath,
        readData: (String) -> Data? = { FileManager.default.contents(atPath: $0) }
    ) -> SemanticVersion? {
        guard let data = readData(plistPath),
              let plist = try? PropertyListSerialization.propertyList(
                  from: data, options: [], format: nil) as? [String: Any],
              let raw = plist["CFBundleShortVersionString"] as? String
        else { return nil }
        return SemanticVersion(raw)
    }
}

// MARK: - Errors

/// Failures the update resolver can surface. Descriptions are user-facing (the CLI
/// prints them verbatim) and never contain a credential — none is ever attached.
public enum UpdateError: Error, CustomStringConvertible, Sendable, Equatable {
    case network(String)
    case httpStatus(Int)
    case tagNotFound(String)
    case badResponse(String)

    public var description: String {
        switch self {
        case .network(let detail):
            return "could not reach GitHub (\(detail))"
        case .httpStatus(let code):
            return "GitHub returned HTTP \(code)"
        case .tagNotFound(let tag):
            return "\(tag) is not published on GitHub"
        case .badResponse(let detail):
            return detail
        }
    }
}

// MARK: - Latest / named release (GitHub Releases API)

/// The one field of the GitHub Releases payload the updater needs.
public struct GitHubRelease: Decodable, Sendable {
    public let tagName: String
    enum CodingKeys: String, CodingKey { case tagName = "tag_name" }
}

/// Resolves release versions from the GitHub Releases API over the pinned session.
/// Unauthenticated: no token, no credential, no telemetry — just a public GET.
public enum ReleaseResolver {
    public static let defaultRepo = "vitorsalomao05/houdini"
    public static let apiBase = "https://api.github.com"

    /// The latest published release's version (`GET /releases/latest`).
    public static func latest(
        repo: String = defaultRepo,
        userAgent: String = "houdini",
        transport: HTTPTransport = PinnedURLSession.transport
    ) async throws -> SemanticVersion {
        let release = try await get(
            path: "/repos/\(repo)/releases/latest",
            as: GitHubRelease.self, userAgent: userAgent, transport: transport)
        guard let version = SemanticVersion(release.tagName) else {
            throw UpdateError.badResponse(
                "latest release tag '\(release.tagName)' is not a vX.Y.Z version")
        }
        return version
    }

    /// A specific tag's version (`GET /releases/tags/vX.Y.Z`), for
    /// `houdini update <version>`. A 404 → `.tagNotFound` — under the revised ADR-010
    /// superseded releases are *kept* (retitled), so a 404 means the tag was never
    /// published, and the caller surfaces a clean "no longer/never published" error.
    public static func resolve(
        tag: String,
        repo: String = defaultRepo,
        userAgent: String = "houdini",
        transport: HTTPTransport = PinnedURLSession.transport
    ) async throws -> SemanticVersion {
        guard let wanted = SemanticVersion(tag) else {
            throw UpdateError.badResponse("'\(tag)' is not a valid version (expected vX.Y.Z)")
        }
        let normalized = "v\(wanted)"
        do {
            let release = try await get(
                path: "/repos/\(repo)/releases/tags/\(normalized)",
                as: GitHubRelease.self, userAgent: userAgent, transport: transport)
            guard let version = SemanticVersion(release.tagName) else {
                throw UpdateError.badResponse(
                    "release tag '\(release.tagName)' is not a vX.Y.Z version")
            }
            return version
        } catch UpdateError.httpStatus(404) {
            throw UpdateError.tagNotFound(normalized)
        }
    }

    /// Shared GET → status-map → decode. Attaches only the headers GitHub asks for
    /// (a User-Agent is required); never an `Authorization` header.
    private static func get<T: Decodable>(
        path: String,
        as type: T.Type,
        userAgent: String,
        transport: HTTPTransport
    ) async throws -> T {
        guard let url = URL(string: apiBase + path) else {
            throw UpdateError.badResponse("bad request URL for \(path)")
        }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await transport(request)
        } catch {
            throw UpdateError.network(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw UpdateError.badResponse("non-HTTP response from GitHub")
        }
        guard http.statusCode == 200 else {
            throw UpdateError.httpStatus(http.statusCode)
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw UpdateError.badResponse("could not decode GitHub response")
        }
    }
}

// MARK: - Update status

/// The resolved comparison between the installed app and a target release.
public struct UpdateStatus: Sendable, Equatable {
    /// `nil` when Houdini.app isn't installed in `~/Applications`.
    public let installed: SemanticVersion?
    /// The target release the check resolved (latest, or a named tag).
    public let latest: SemanticVersion

    public init(installed: SemanticVersion?, latest: SemanticVersion) {
        self.installed = installed
        self.latest = latest
    }

    public enum State: String, Sendable {
        case notInstalled     // no Houdini.app in ~/Applications
        case updateAvailable  // installed < target
        case upToDate         // installed == target
        case ahead            // installed > target (a dev build newer than any release)
    }

    public var state: State {
        guard let installed else { return .notInstalled }
        if installed < latest { return .updateAvailable }
        if installed > latest { return .ahead }
        return .upToDate
    }

    /// True only when a bare `houdini update` would move the install forward.
    public var updateAvailable: Bool { state == .updateAvailable }
}
