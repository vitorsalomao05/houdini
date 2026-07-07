import Testing
import Foundation
@testable import FetcherCore

/// Phase E1 (audit 07/08): the READ-ONLY update resolver — semver parse/compare, the
/// installed-app version read (injected plist bytes, no filesystem), the GitHub
/// latest/named-tag resolution over the injected `HTTPTransport` seam (no network),
/// and the installed-vs-target state machine. `houdini-selftest` mirrors the critical
/// subset so it's observable on a CommandLineTools-only machine where `swift test`'s
/// runner no-ops. No credential is ever attached to the GitHub request — the tests
/// assert the absence of an `Authorization` header.
@Suite struct UpdateResolverTests {

    // MARK: - SemanticVersion

    @Test func parsesPlainAndVPrefixed() {
        #expect(SemanticVersion("0.4.0") == SemanticVersion(major: 0, minor: 4, patch: 0))
        #expect(SemanticVersion("v0.4.0") == SemanticVersion(major: 0, minor: 4, patch: 0))
        #expect(SemanticVersion("  v1.2.3 ") == SemanticVersion(major: 1, minor: 2, patch: 3))
    }

    @Test func rejectsNonTriples() {
        #expect(SemanticVersion("0.4") == nil)
        #expect(SemanticVersion("1.2.3.4") == nil)
        #expect(SemanticVersion("v1.2.3-beta") == nil)
        #expect(SemanticVersion("x.y.z") == nil)
        #expect(SemanticVersion("") == nil)
        #expect(SemanticVersion("-1.0.0") == nil)
    }

    @Test func comparesNumericallyNotLexically() {
        #expect(SemanticVersion("0.4.0")! < SemanticVersion("0.4.1")!)
        #expect(SemanticVersion("0.9.0")! < SemanticVersion("0.10.0")!)  // not lexical
        #expect(SemanticVersion("0.4.0")! < SemanticVersion("1.0.0")!)
        #expect(!(SemanticVersion("0.4.0")! < SemanticVersion("0.4.0")!))
        #expect(SemanticVersion("0.4.0")!.description == "0.4.0")
    }

    // MARK: - InstalledVersion (injected plist bytes)

    private func plistData(_ dict: [String: Any]) -> Data {
        try! PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
    }

    @Test func readsInstalledVersionFromPlist() {
        let data = plistData(["CFBundleShortVersionString": "0.4.0"])
        let v = InstalledVersion.read(plistPath: "/any", readData: { _ in data })
        #expect(v == SemanticVersion("0.4.0"))
    }

    @Test func missingAppFileMeansNotInstalled() {
        // No file → readData yields nil → nil (treated as "not installed").
        #expect(InstalledVersion.read(plistPath: "/any", readData: { _ in nil }) == nil)
    }

    @Test func missingOrMalformedKeyIsNil() {
        let noKey = plistData(["CFBundleName": "Houdini"])
        #expect(InstalledVersion.read(plistPath: "/any", readData: { _ in noKey }) == nil)
        let bad = plistData(["CFBundleShortVersionString": "not-a-version"])
        #expect(InstalledVersion.read(plistPath: "/any", readData: { _ in bad }) == nil)
    }

    // MARK: - ReleaseResolver.latest / resolve (scripted transport)

    private func releaseBody(_ tag: String) -> Data { Data("{\"tag_name\":\"\(tag)\"}".utf8) }

    @Test func latestParsesTagAndSendsNoCredential() async throws {
        let stub = TransportStub([(200, releaseBody("v0.5.0"))])
        let v = try await ReleaseResolver.latest(transport: stub.transport)
        #expect(v == SemanticVersion("0.5.0"))
        let req = stub.requests.first
        #expect(req?.url?.absoluteString
            == "https://api.github.com/repos/vitorsalomao05/houdini/releases/latest")
        #expect(req?.value(forHTTPHeaderField: "Authorization") == nil)   // tokenless
        #expect(req?.value(forHTTPHeaderField: "User-Agent") != nil)      // GitHub requires one
    }

    @Test func latestRejectsNonSemverTag() async {
        let stub = TransportStub([(200, releaseBody("garbage"))])
        await #expect(throws: UpdateError.self) {
            _ = try await ReleaseResolver.latest(transport: stub.transport)
        }
    }

    @Test func latestMapsHttpErrorStatus() async {
        let stub = TransportStub([(500, Data())])
        do {
            _ = try await ReleaseResolver.latest(transport: stub.transport)
            Issue.record("expected throw")
        } catch let e as UpdateError {
            #expect(e == .httpStatus(500))
        } catch { Issue.record("wrong error \(error)") }
    }

    @Test func latestRejectsNonJSON() async {
        let stub = TransportStub([(200, Data("<html>".utf8))])
        do {
            _ = try await ReleaseResolver.latest(transport: stub.transport)
            Issue.record("expected throw")
        } catch let e as UpdateError {
            if case .badResponse = e {} else { Issue.record("wrong case \(e)") }
        } catch { Issue.record("wrong error \(error)") }
    }

    @Test func resolveNamedTagHitsTagsEndpoint() async throws {
        let stub = TransportStub([(200, releaseBody("v0.3.0"))])
        let v = try await ReleaseResolver.resolve(tag: "0.3.0", transport: stub.transport)
        #expect(v == SemanticVersion("0.3.0"))
        #expect(stub.requests.first?.url?.absoluteString
            == "https://api.github.com/repos/vitorsalomao05/houdini/releases/tags/v0.3.0")
    }

    @Test func resolveMaps404ToTagNotFound() async {
        let stub = TransportStub([(404, Data())])
        do {
            _ = try await ReleaseResolver.resolve(tag: "99.0.0", transport: stub.transport)
            Issue.record("expected throw")
        } catch let e as UpdateError {
            #expect(e == .tagNotFound("v99.0.0"))
        } catch { Issue.record("wrong error \(error)") }
    }

    @Test func resolveRejectsBadVersionWithoutNetwork() async {
        let stub = TransportStub([(200, releaseBody("v0.3.0"))])
        do {
            _ = try await ReleaseResolver.resolve(tag: "not-a-version", transport: stub.transport)
            Issue.record("expected throw")
        } catch let e as UpdateError {
            if case .badResponse = e {} else { Issue.record("wrong case \(e)") }
        } catch { Issue.record("wrong error \(error)") }
        #expect(stub.requests.isEmpty)  // rejected before any request
    }

    // MARK: - UpdateStatus state machine

    @Test func stateMachineCoversAllFour() {
        let latest = SemanticVersion("0.5.0")!
        #expect(UpdateStatus(installed: nil, latest: latest).state == .notInstalled)
        #expect(UpdateStatus(installed: SemanticVersion("0.4.0"), latest: latest).state == .updateAvailable)
        #expect(UpdateStatus(installed: SemanticVersion("0.5.0"), latest: latest).state == .upToDate)
        #expect(UpdateStatus(installed: SemanticVersion("0.6.0"), latest: latest).state == .ahead)
        #expect(UpdateStatus(installed: SemanticVersion("0.4.0"), latest: latest).updateAvailable)
        #expect(!UpdateStatus(installed: SemanticVersion("0.5.0"), latest: latest).updateAvailable)
    }
}
