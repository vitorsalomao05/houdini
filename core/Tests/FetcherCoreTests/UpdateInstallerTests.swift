import Testing
import Foundation
@testable import FetcherCore

/// Phase E2 (audit 07 R3 / 08): the update MUTATION, exercised end-to-end — including
/// rollback — through a fully in-memory fake environment. No real filesystem, no
/// network, no spawned installer, so the destructive path is safe to test. Covers the
/// §7 edge-case matrix: happy update, no-op, installer failure → restore, TAG mismatch,
/// unmanaged-install refusal, post-install version mismatch → rollback, installer
/// throw (Ctrl-C-like) → restore, named downgrade, 404, and fresh install. Plus the
/// pure TAG parser and the detached-spawn primitive. `houdini-selftest` mirrors the
/// critical subset.

// MARK: - Fake environment

/// An in-memory model of the two owned paths + their stashes and the installer's
/// effect. `versionAt[appPath]` is the "installed version"; moves carry the version
/// with the app so a stash/restore round-trip is faithful.
final class FakeInstallEnv: @unchecked Sendable {
    let managedCLI = "/home/.local/bin/houdini"
    let appPath = "/home/Applications/Houdini.app"

    var paths: Set<String> = []
    var versionAt: [String: SemanticVersion] = [:]
    var running: String?
    var resolveResult: Result<SemanticVersion, Error>
    var fetchResult: Result<String, Error>

    enum InstallerBehavior {
        case succeeds(installing: SemanticVersion)  // writes app+cli, sets version, exit 0
        case exits(Int32)                            // nonzero, no filesystem change
        case throwsError(Error)                      // spawn failure / interruption
    }
    var installerBehavior: InstallerBehavior

    private(set) var moves: [(from: String, to: String)] = []
    private(set) var removes: [String] = []

    /// Default: an installed `0.4.0`, running from the managed CLI, resolving `0.5.0`,
    /// fetching a matching installer, and an installer that succeeds installing `0.5.0`.
    init(installed: SemanticVersion? = SemanticVersion("0.4.0"),
         resolve: SemanticVersion = SemanticVersion("0.5.0")!,
         installerTag: String = "v0.5.0",
         installs: SemanticVersion = SemanticVersion("0.5.0")!) {
        self.resolveResult = .success(resolve)
        self.fetchResult = .success(Self.script(tag: installerTag))
        self.installerBehavior = .succeeds(installing: installs)
        paths.insert(managedCLI)
        running = managedCLI
        if let installed {
            paths.insert(appPath)
            versionAt[appPath] = installed
        }
    }

    static func script(tag: String) -> String {
        "REPO=\"vitorsalomao05/houdini\"\nTAG=\"\(tag)\"\nREL=\"x/$TAG\"\n"
    }

    enum FakeFSError: Error { case missing(String) }

    func installer() -> UpdateInstaller {
        UpdateInstaller(
            managedCLIPath: managedCLI,
            appPath: appPath,
            runningCLIPath: { self.running },
            pathExists: { self.paths.contains($0) },
            move: { from, to in
                guard self.paths.contains(from) else { throw FakeFSError.missing(from) }
                self.paths.remove(from)
                self.paths.insert(to)
                self.versionAt[to] = self.versionAt[from]
                self.versionAt[from] = nil
                self.moves.append((from, to))
            },
            remove: { path in
                self.paths.remove(path)
                self.versionAt[path] = nil
                self.removes.append(path)
            },
            installedVersion: { self.versionAt[self.appPath] },
            resolveVersion: { _ in try self.resolveResult.get() },
            fetchInstaller: { _ in try self.fetchResult.get() },
            runInstaller: { _, _ in
                switch self.installerBehavior {
                case .succeeds(let v):
                    self.paths.insert(self.appPath)
                    self.paths.insert(self.managedCLI)
                    self.versionAt[self.appPath] = v
                    return 0
                case .exits(let code):
                    return code
                case .throwsError(let e):
                    throw e
                }
            })
    }

    /// Post-run invariant for the "unchanged" cases: exactly the two owned paths exist,
    /// no leftover stash, and the app is back at `version`.
    func isCleanInstall(version: SemanticVersion?) -> Bool {
        let expected: Set<String> = version == nil ? [managedCLI] : [managedCLI, appPath]
        return paths == expected && versionAt[appPath] == version
    }
}

// MARK: - Orchestration matrix

@Suite struct UpdateInstallerTests {

    @Test func happyUpdateReplacesAndCleansStashes() async {
        let env = FakeInstallEnv()
        let outcome = await env.installer().run(target: .latest)
        #expect(outcome == .updated(from: SemanticVersion("0.4.0"), to: SemanticVersion("0.5.0")!))
        #expect(env.isCleanInstall(version: SemanticVersion("0.5.0")))       // 0.5.0 installed, stashes gone
        #expect(env.moves.contains { $0.from == env.managedCLI })            // CLI renamed aside
        #expect(env.moves.contains { $0.from == env.appPath })               // app pre-stashed
    }

    @Test func alreadyCurrentIsNoOp() async {
        let env = FakeInstallEnv(installed: SemanticVersion("0.5.0"), resolve: SemanticVersion("0.5.0")!)
        let outcome = await env.installer().run(target: .latest)
        #expect(outcome == .alreadyCurrent(SemanticVersion("0.5.0")!))
        #expect(env.moves.isEmpty && env.removes.isEmpty)                    // nothing touched
    }

    @Test func installerFailureRestoresInstall() async {
        let env = FakeInstallEnv()
        env.installerBehavior = .exits(1)                                    // e.g. shasum mismatch → die
        let outcome = await env.installer().run(target: .latest)
        guard case .failed(_, let unchanged, let clean) = outcome else {
            Issue.record("expected .failed, got \(outcome)"); return
        }
        #expect(unchanged == SemanticVersion("0.4.0") && clean)
        #expect(env.isCleanInstall(version: SemanticVersion("0.4.0")))       // rolled back to 0.4.0
    }

    @Test func tagMismatchRefusesBeforeTouchingDisk() async {
        let env = FakeInstallEnv(installerTag: "v9.9.9")                     // installer targets wrong tag
        let outcome = await env.installer().run(target: .latest)
        guard case .failed = outcome else { Issue.record("expected .failed, got \(outcome)"); return }
        #expect(env.moves.isEmpty && env.removes.isEmpty)                    // aborted before any move
        #expect(env.isCleanInstall(version: SemanticVersion("0.4.0")))
    }

    @Test func unmanagedInstallIsRefused() async {
        let env = FakeInstallEnv()
        env.running = "/usr/local/bin/houdini"                               // not the managed CLI
        let outcome = await env.installer().run(target: .latest)
        guard case .refused = outcome else { Issue.record("expected .refused, got \(outcome)"); return }
        #expect(env.moves.isEmpty && env.removes.isEmpty)                    // nothing touched
    }

    @Test func postInstallVersionMismatchRollsBack() async {
        let env = FakeInstallEnv()
        env.installerBehavior = .succeeds(installing: SemanticVersion("0.4.9")!)  // exit 0 but wrong version
        let outcome = await env.installer().run(target: .latest)
        guard case .failed(_, let unchanged, let clean) = outcome else {
            Issue.record("expected .failed, got \(outcome)"); return
        }
        #expect(unchanged == SemanticVersion("0.4.0") && clean)
        #expect(env.isCleanInstall(version: SemanticVersion("0.4.0")))       // restored original
    }

    @Test func installerThrowRestoresInstall() async {
        struct Interrupted: Error {}
        let env = FakeInstallEnv()
        env.installerBehavior = .throwsError(Interrupted())                  // Ctrl-C / spawn failure
        let outcome = await env.installer().run(target: .latest)
        guard case .failed = outcome else { Issue.record("expected .failed, got \(outcome)"); return }
        #expect(env.isCleanInstall(version: SemanticVersion("0.4.0")))       // rolled back
    }

    @Test func bareUpdateNeverDowngradesAnAheadBuild() async {
        // Dev build 1.0.0 installed, latest release 0.5.0: bare `update` must NOT downgrade.
        let env = FakeInstallEnv(installed: SemanticVersion("1.0.0"), resolve: SemanticVersion("0.5.0")!)
        let outcome = await env.installer().run(target: .latest)
        #expect(outcome == .ahead(installed: SemanticVersion("1.0.0")!, latest: SemanticVersion("0.5.0")!))
        #expect(env.moves.isEmpty && env.removes.isEmpty)                    // nothing touched
    }

    @Test func namedDowngradeWhenTagExists() async {
        // Revised ADR-010 keeps superseded releases, so an explicit downgrade is valid.
        let env = FakeInstallEnv(installed: SemanticVersion("0.5.0"),
                                 resolve: SemanticVersion("0.3.0")!,
                                 installerTag: "v0.3.0",
                                 installs: SemanticVersion("0.3.0")!)
        let outcome = await env.installer().run(target: .version("0.3.0"))
        #expect(outcome == .updated(from: SemanticVersion("0.5.0"), to: SemanticVersion("0.3.0")!))
        #expect(env.isCleanInstall(version: SemanticVersion("0.3.0")))
    }

    @Test func missingTagFailsCleanly() async {
        let env = FakeInstallEnv()
        env.resolveResult = .failure(UpdateError.tagNotFound("v0.3.0"))      // 404
        let outcome = await env.installer().run(target: .version("0.3.0"))
        guard case .failed = outcome else { Issue.record("expected .failed, got \(outcome)"); return }
        #expect(env.moves.isEmpty)                                           // never began mutating
    }

    @Test func freshInstallWhenAppMissing() async {
        let env = FakeInstallEnv(installed: nil)                             // CLI present, no app
        let outcome = await env.installer().run(target: .latest)
        #expect(outcome == .installedFresh(SemanticVersion("0.5.0")!))
        #expect(env.isCleanInstall(version: SemanticVersion("0.5.0")))
    }

    // MARK: - Pure helpers

    @Test func parsesInstallerTag() {
        #expect(UpdateInstaller.parseInstallerTag(FakeInstallEnv.script(tag: "v0.5.0"))
                == SemanticVersion("0.5.0"))
        // A commented TAG is ignored; the real assignment (with trailing comment) wins.
        let tricky = "# TAG=\"v9.9.9\"\nTAG=\"v0.6.0\"   # bump me\nREL=\"x\"\n"
        #expect(UpdateInstaller.parseInstallerTag(tricky) == SemanticVersion("0.6.0"))
        #expect(UpdateInstaller.parseInstallerTag("REPO=\"x\"\nno tag here\n") == nil)
    }

    @Test func samePathCanonicalizes() {
        #expect(UpdateInstaller.samePath("/a/b/houdini", "/a/b/houdini"))
        #expect(!UpdateInstaller.samePath("/a/b/houdini", "/usr/local/bin/houdini"))
    }

    // MARK: - Detached spawn primitive (safe real spawns)

    @Test func detachedRunReturnsExitCode() throws {
        let code = try DetachedProcess.run("/bin/sh", ["/bin/sh", "-c", "exit 42"],
                                           env: ["PATH": "/usr/bin:/bin"])
        #expect(code == 42)
    }

    @Test func detachedRunHasNoControllingTerminal() throws {
        // In a new session there is no controlling terminal, so opening /dev/tty fails.
        // Under a real terminal this catches a broken detach (it would exit 0 instead).
        let code = try DetachedProcess.run(
            "/bin/sh",
            ["/bin/sh", "-c", "if : 2>/dev/null >/dev/tty; then exit 0; else exit 3; fi"],
            env: ["PATH": "/usr/bin:/bin"])
        #expect(code == 3)
    }
}
