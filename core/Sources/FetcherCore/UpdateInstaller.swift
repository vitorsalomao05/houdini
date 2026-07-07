import Foundation
#if canImport(Darwin)
import Darwin
#endif

// The MUTATION half of `houdini update` (audit 07 R3 conditions + 08 · Phase E2).
//
// `houdini update` NEVER re-implements download/verify/swap. It delegates to the
// *verified per-tag `install.sh`* (SHA-256 vs SHASUMS256.txt, no sudo, no Gatekeeper
// prompt) and only adds a safety envelope around it:
//
//   1. unmanaged-install guard — refuse unless the running binary is the managed
//      `~/.local/bin/houdini` (uv/mise pattern);
//   2. resolve the target (latest, or a named tag — downgrade allowed when the tag
//      still exists under the revised ADR-010; a 404 is a clean error);
//   3. fetch that tag's own `install.sh` (no edit to the shipping installer);
//   4. TAG-match guard — the fetched installer's `TAG=` must equal the resolved tag;
//   5. rename-aside the CLI + pre-stash the app (same-volume renames → free rollback,
//      and frees the CLI inode so install.sh's `cp -f` writes a NEW inode while the
//      running updater keeps executing from the old one — Apple's cp-vs-signature
//      hazard, R3.1/R3.2);
//   6. run the installer DETACHED from any controlling terminal and WITHOUT
//      HOUDINI_YES → install.sh's `/dev/tty`-gated prompt defaults to "No", so the
//      login item is left exactly as the user had it (R3.4);
//   7. on success, verify the freshly-installed app reports the target, then delete
//      the stashes; on ANY failure, restore both stashes so the install is untouched.
//
// It touches NO credential, NO Keychain item, NO `~/.claude/*`, and adds NO telemetry.
// Every side-effecting step is an injected seam so the whole flow — including rollback
// — is testable with fakes, never touching the real install or the network.

// MARK: - Target / outcome

public enum UpdateTarget: Sendable, Equatable {
    case latest
    case version(String)   // "0.5.0" / "v0.5.0"
}

public enum UpdateOutcome: Sendable, Equatable {
    /// An existing install moved to `to` (from `from`, nil only in odd states).
    case updated(from: SemanticVersion?, to: SemanticVersion)
    /// No app was installed; the target was installed fresh.
    case installedFresh(SemanticVersion)
    /// Already exactly on the target — nothing done.
    case alreadyCurrent(SemanticVersion)
    /// The installed build is NEWER than the latest release; a bare `update` never
    /// auto-downgrades, so nothing was done (an explicit `update <version>` still can).
    case ahead(installed: SemanticVersion, latest: SemanticVersion)
    /// Aborted; `unchanged` is the still-installed version. `rollbackClean` is false
    /// only if restoring a stash itself failed (a stash may remain on disk).
    case failed(reason: String, unchanged: SemanticVersion?, rollbackClean: Bool)
    /// Refused before doing anything (e.g. unmanaged install).
    case refused(String)
}

public enum DetachedProcessError: Error, CustomStringConvertible, Sendable {
    case spawnFailed(Int32)
    public var description: String {
        switch self {
        case .spawnFailed(let rc): return "could not spawn the installer (posix_spawn rc=\(rc))"
        }
    }
}

// MARK: - Installer

/// Orchestrates a verified, delegated update. All environment access is injected;
/// ``live(userAgent:)`` wires the production seams.
public struct UpdateInstaller: Sendable {
    // Owned install paths (least-privilege: these two, and their stashes, are the
    // ONLY paths this type ever writes).
    public var managedCLIPath: String
    public var appPath: String

    // Injected seams.
    public var runningCLIPath: @Sendable () -> String?
    public var pathExists: @Sendable (String) -> Bool
    public var move: @Sendable (String, String) throws -> Void
    public var remove: @Sendable (String) throws -> Void
    public var installedVersion: @Sendable () -> SemanticVersion?
    public var resolveVersion: @Sendable (UpdateTarget) async throws -> SemanticVersion
    public var fetchInstaller: @Sendable (String) async throws -> String   // (tag) -> script text
    public var runInstaller: @Sendable (String, String) async throws -> Int32  // (text, tag) -> exit code

    public init(
        managedCLIPath: String,
        appPath: String,
        runningCLIPath: @escaping @Sendable () -> String?,
        pathExists: @escaping @Sendable (String) -> Bool,
        move: @escaping @Sendable (String, String) throws -> Void,
        remove: @escaping @Sendable (String) throws -> Void,
        installedVersion: @escaping @Sendable () -> SemanticVersion?,
        resolveVersion: @escaping @Sendable (UpdateTarget) async throws -> SemanticVersion,
        fetchInstaller: @escaping @Sendable (String) async throws -> String,
        runInstaller: @escaping @Sendable (String, String) async throws -> Int32
    ) {
        self.managedCLIPath = managedCLIPath
        self.appPath = appPath
        self.runningCLIPath = runningCLIPath
        self.pathExists = pathExists
        self.move = move
        self.remove = remove
        self.installedVersion = installedVersion
        self.resolveVersion = resolveVersion
        self.fetchInstaller = fetchInstaller
        self.runInstaller = runInstaller
    }

    // MARK: The run

    public func run(target: UpdateTarget) async -> UpdateOutcome {
        // 1. Unmanaged-install guard.
        guard let running = runningCLIPath() else {
            return .refused("could not determine the running houdini path")
        }
        guard Self.samePath(running, managedCLIPath) else {
            return .refused("""
            this houdini runs from \(running), not \(managedCLIPath) — \
            `houdini update` only manages the install.sh install. Reinstall with install.sh instead.
            """)
        }

        // 2. Resolve the target version.
        let installed = installedVersion()
        let targetVersion: SemanticVersion
        do {
            targetVersion = try await resolveVersion(target)
        } catch {
            return .failed(reason: Self.errorText(error), unchanged: installed, rollbackClean: true)
        }

        // 3. Decide whether to proceed, per target kind. A bare `update` only ever moves
        //    forward — it must never auto-downgrade a build that is ahead of the latest
        //    release (matches `--check`, which reports "newer than the latest release").
        //    An explicit `update <version>` still allows a downgrade when the tag exists.
        if let installed {
            switch target {
            case .latest:
                if installed == targetVersion { return .alreadyCurrent(installed) }
                if installed > targetVersion {
                    return .ahead(installed: installed, latest: targetVersion)
                }
            case .version:
                if installed == targetVersion { return .alreadyCurrent(installed) }
            }
        }

        let tag = "v\(targetVersion)"

        // 4. Fetch the per-tag installer (runs that tag's own copy — install.sh unedited).
        let scriptText: String
        do {
            scriptText = try await fetchInstaller(tag)
        } catch {
            return .failed(reason: "could not fetch the installer for \(tag) (\(Self.errorText(error)))",
                           unchanged: installed, rollbackClean: true)
        }

        // 5. TAG-match guard — refuse a mismatched installer BEFORE touching disk.
        guard let scriptTag = Self.parseInstallerTag(scriptText), scriptTag == targetVersion else {
            return .failed(
                reason: "the fetched installer does not target \(tag) — refusing "
                      + "(a release may have skipped its version bump)",
                unchanged: installed, rollbackClean: true)
        }

        // 6. Rename-aside the CLI + pre-stash the app.
        let cliBackup = managedCLIPath + ".old"
        let appStash = appPath + ".houdini-update-stash"
        // Sweep any leftover stashes from a prior interrupted run so they can't shadow us.
        try? remove(cliBackup)
        try? remove(appStash)

        var stashedCLI = false
        var stashedApp = false
        do {
            if pathExists(managedCLIPath) { try move(managedCLIPath, cliBackup); stashedCLI = true }
            if pathExists(appPath)        { try move(appPath, appStash);         stashedApp = true }
        } catch {
            // The app move is the last step, so only the CLI can have been stashed here;
            // undo it (if any) and abort with the install untouched.
            let clean = restore(cliBackup: stashedCLI ? cliBackup : nil, appStash: nil)
            return .failed(reason: "could not prepare the update (\(Self.errorText(error)))",
                           unchanged: installed, rollbackClean: clean)
        }

        // 7. Delegate to the verified installer (detached, no HOUDINI_YES).
        let exitCode: Int32
        do {
            exitCode = try await runInstaller(scriptText, tag)
        } catch {
            let clean = restore(cliBackup: stashedCLI ? cliBackup : nil,
                                appStash: stashedApp ? appStash : nil)
            return .failed(reason: "the installer could not run (\(Self.errorText(error)))",
                           unchanged: installed, rollbackClean: clean)
        }

        // 8a. Installer failure → restore both stashes.
        guard exitCode == 0 else {
            let clean = restore(cliBackup: stashedCLI ? cliBackup : nil,
                                appStash: stashedApp ? appStash : nil)
            return .failed(reason: "the installer exited with code \(exitCode) — nothing was changed",
                           unchanged: installed, rollbackClean: clean)
        }

        // 8b. Post-install verify — the fresh app must report the target version.
        let after = installedVersion()
        guard after == targetVersion else {
            let clean = restore(cliBackup: stashedCLI ? cliBackup : nil,
                                appStash: stashedApp ? appStash : nil)
            return .failed(
                reason: "post-install version is \(after?.description ?? "missing"), "
                      + "expected \(targetVersion) — rolled back",
                unchanged: installed, rollbackClean: clean)
        }

        // 9. Success → drop the stashes (best-effort; a leftover stash never fails success).
        try? remove(cliBackup)
        try? remove(appStash)

        if installed == nil { return .installedFresh(targetVersion) }
        return .updated(from: installed, to: targetVersion)
    }

    /// Restore stashed artifacts after a failure: remove any freshly-written copy at
    /// the live path, then move the stash back. Returns false if a restore move failed
    /// (a stash may remain — the caller warns the user).
    private func restore(cliBackup: String?, appStash: String?) -> Bool {
        var clean = true
        if let appStash {
            if pathExists(appPath) { try? remove(appPath) }
            do { try move(appStash, appPath) } catch { clean = false }
        }
        if let cliBackup {
            if pathExists(managedCLIPath) { try? remove(managedCLIPath) }
            do { try move(cliBackup, managedCLIPath) } catch { clean = false }
        }
        return clean
    }

    // MARK: Pure helpers

    /// Parse the installer's `TAG="vX.Y.Z"` line into a version. Ignores comments and
    /// unrelated assignments (`REL=`, `HOUDINI_TAG=`, …).
    public static func parseInstallerTag(_ text: String) -> SemanticVersion? {
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("TAG=") else { continue }
            var value = String(line.dropFirst("TAG=".count))
            if let hash = value.firstIndex(of: "#") { value = String(value[..<hash]) }
            value = value.trimmingCharacters(in: CharacterSet(charactersIn: "\"' \t"))
            return SemanticVersion(value)
        }
        return nil
    }

    /// Canonical-path equality (resolves symlinks + `/var`→`/private/var`).
    public static func samePath(_ a: String, _ b: String) -> Bool {
        let ca = URL(fileURLWithPath: a).resolvingSymlinksInPath().standardizedFileURL.path
        let cb = URL(fileURLWithPath: b).resolvingSymlinksInPath().standardizedFileURL.path
        return ca == cb
    }

    static func errorText(_ error: Error) -> String {
        if let u = error as? UpdateError { return u.description }
        if let d = error as? DetachedProcessError { return d.description }
        return error.localizedDescription
    }
}

// MARK: - Production wiring

extension UpdateInstaller {
    /// The production installer, resolving the two owned paths under `$HOME`.
    public static func live(userAgent: String = "houdini") -> UpdateInstaller {
        let home = NSHomeDirectory()
        let cli = home + "/.local/bin/houdini"
        let app = home + "/Applications/Houdini.app"
        return UpdateInstaller(
            managedCLIPath: cli,
            appPath: app,
            runningCLIPath: { Bundle.main.executablePath ?? CommandLine.arguments.first },
            pathExists: { FileManager.default.fileExists(atPath: $0) },
            move: { try FileManager.default.moveItem(atPath: $0, toPath: $1) },
            remove: { try FileManager.default.removeItem(atPath: $0) },
            installedVersion: { InstalledVersion.read(plistPath: app + "/Contents/Info.plist") },
            resolveVersion: { try await Self.resolve($0, userAgent: userAgent) },
            fetchInstaller: { try await Self.fetchInstaller(tag: $0, userAgent: userAgent) },
            runInstaller: { text, tag in try Self.spawnInstaller(scriptText: text, tag: tag) }
        )
    }

    private static func resolve(_ target: UpdateTarget, userAgent: String) async throws -> SemanticVersion {
        switch target {
        case .latest:            return try await ReleaseResolver.latest(userAgent: userAgent)
        case .version(let name): return try await ReleaseResolver.resolve(tag: name, userAgent: userAgent)
        }
    }

    /// Fetch the target tag's own `install.sh` over the pinned session (HTTPS, no
    /// credential). This is the exact artifact the site/README advertise for that tag.
    private static func fetchInstaller(tag: String, userAgent: String) async throws -> String {
        let urlString =
            "https://raw.githubusercontent.com/\(ReleaseResolver.defaultRepo)/\(tag)/install.sh"
        guard let url = URL(string: urlString) else {
            throw UpdateError.badResponse("bad installer URL for \(tag)")
        }
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await PinnedURLSession.transport(request)
        } catch {
            throw UpdateError.network(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw UpdateError.badResponse("non-HTTP response fetching the installer")
        }
        guard http.statusCode == 200 else { throw UpdateError.httpStatus(http.statusCode) }
        guard let text = String(data: data, encoding: .utf8) else {
            throw UpdateError.badResponse("the installer was not UTF-8 text")
        }
        return text
    }

    /// Write the fetched installer to a private temp file and run it detached.
    private static func spawnInstaller(scriptText: String, tag: String) throws -> Int32 {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("houdini-update-\(tag)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: dir) }

        let script = dir.appendingPathComponent("install.sh")
        try scriptText.write(to: script, atomically: true, encoding: .utf8)

        // Current environment MINUS HOUDINI_YES — running the installer without it (and
        // without a controlling terminal) makes install.sh's login-item prompt default
        // to "No" (R3.4). We keep PATH/HOME so curl/shasum/ditto and `$HOME/Applications`
        // resolve exactly as in a normal install.
        var env = ProcessInfo.processInfo.environment
        env.removeValue(forKey: "HOUDINI_YES")

        return try DetachedProcess.run("/bin/bash", ["/bin/bash", script.path], env: env)
    }
}

// MARK: - Detached process

public enum DetachedProcess {
    /// Run `launchPath` with `args` (argv[0] included) in a NEW SESSION — no controlling
    /// terminal — with stdin ← `/dev/null` and stdout/stderr inherited (so the installer's
    /// progress is visible). Returns the child's exit code (128+signal if it was killed).
    ///
    /// The new session is why install.sh's `{ true > /dev/tty; }` probe fails and its
    /// login prompt takes the default-No branch, achieved without editing the installer.
    public static func run(_ launchPath: String, _ args: [String], env: [String: String]) throws -> Int32 {
        var attr: posix_spawnattr_t?
        posix_spawnattr_init(&attr)
        defer { posix_spawnattr_destroy(&attr) }
        // New session leader → detached from any controlling terminal.
        posix_spawnattr_setflags(&attr, Int16(POSIX_SPAWN_SETSID))

        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0)

        let argv: [UnsafeMutablePointer<CChar>?] = args.map { strdup($0) } + [nil]
        let envp: [UnsafeMutablePointer<CChar>?] =
            env.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer {
            for p in argv where p != nil { free(p) }
            for p in envp where p != nil { free(p) }
        }

        var pid: pid_t = 0
        let rc = posix_spawn(&pid, launchPath, &actions, &attr, argv, envp)
        guard rc == 0 else { throw DetachedProcessError.spawnFailed(rc) }

        var status: Int32 = 0
        while waitpid(pid, &status, 0) == -1 && errno == EINTR {}
        if (status & 0o177) == 0 {           // WIFEXITED
            return (status >> 8) & 0xFF       // WEXITSTATUS
        }
        return 128 + (status & 0o177)         // killed by a signal
    }
}
