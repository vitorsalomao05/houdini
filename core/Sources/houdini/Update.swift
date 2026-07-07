import Foundation
import FetcherCore

// `houdini update` — the CLI surface (audit 07/08 · Phase E).
//
// E1 (this commit) wires the READ-ONLY `--check`: resolve installed-vs-target and
// report, mutating nothing on disk. The mutation (`houdini update` / `update
// <version>`) delegates to the verified per-tag `install.sh` and lands in E2; until
// then the mutation path refuses cleanly rather than half-working.

let updateUsage = """
houdini update — update Houdini through the same verified path as install.sh

USAGE:
  houdini update --check [--json]     show installed vs. latest; change nothing
  houdini update                      update to the latest release
  houdini update <version>            update to a specific release (e.g. 0.5.0)

FLAGS:
  --check        dry-run: report installed + latest and whether an update exists
  --json         with --check, print machine-readable status
  --yes, -y      non-interactive (for scripts/CI)
  --help, -h     show this help
"""

/// User-agent for the GitHub API call — versioned so requests are identifiable,
/// but carrying no credential.
private let updateUserAgent = "houdini/\(houdiniVersion)"

/// Machine-readable `--check --json` shape. `installed`/`target` are always present
/// (explicit `null` when absent) so consumers can rely on a fixed key set; `state`
/// mirrors ``UpdateStatus/State``.
private struct UpdateCheckJSON: Encodable {
    let installed: String?
    let latest: String
    let target: String?
    let update_available: Bool
    let state: String

    enum CodingKeys: String, CodingKey {
        case installed, latest, target, update_available, state
    }

    // Custom encode so nil `installed`/`target` serialize as explicit `null` rather
    // than being omitted (the synthesized Encodable would drop them).
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(installed, forKey: .installed)
        try c.encode(latest, forKey: .latest)
        try c.encode(target, forKey: .target)
        try c.encode(update_available, forKey: .update_available)
        try c.encode(state, forKey: .state)
    }
}

/// Parse the `update` verb's own arguments and dispatch. Flags are parsed here (not
/// by the top-level loop) so `--check`/`--json` aren't rejected as unknown.
func runUpdate(arguments: [String]) async {
    var check = false
    var json = false
    var yes = false
    var target: String?

    for argument in arguments {
        switch argument {
        case "--check":
            check = true
        case "--json":
            json = true
        case "--yes", "-y":
            yes = true
        case "--help", "-h":
            print(updateUsage)
            exit(0)
        default:
            guard !argument.hasPrefix("-") else {
                emitError("error: unknown flag '\(argument)'\n\n\(updateUsage)")
                exit(64) // EX_USAGE
            }
            guard target == nil else {
                emitError("error: give at most one version\n\n\(updateUsage)")
                exit(64)
            }
            target = argument
        }
    }

    if check {
        await runUpdateCheck(target: target, json: json)
    } else {
        await runUpdateInstall(target: target, yes: yes)
    }
}

/// Read-only dry-run: resolve installed vs. the target (latest, or a named tag) and
/// print the comparison. Never writes to disk. Exit 0 on a clean resolve; exit 2 if
/// GitHub can't be reached or the tag doesn't exist.
func runUpdateCheck(target: String?, json: Bool) async {
    let installed = InstalledVersion.read()

    let resolved: SemanticVersion
    do {
        if let target {
            resolved = try await ReleaseResolver.resolve(tag: target, userAgent: updateUserAgent)
        } else {
            resolved = try await ReleaseResolver.latest(userAgent: updateUserAgent)
        }
    } catch {
        emitError("error: \(error)")
        exit(2)
    }

    let status = UpdateStatus(installed: installed, latest: resolved)
    let runHint = target.map { "houdini update \($0)" } ?? "houdini update"

    if json {
        let payload = UpdateCheckJSON(
            installed: installed?.description,
            latest: resolved.description,
            target: target,
            update_available: status.updateAvailable,
            state: status.state.rawValue)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        if let data = try? encoder.encode(payload), let text = String(data: data, encoding: .utf8) {
            print(text)
        }
        exit(0)
    }

    switch status.state {
    case .notInstalled:
        if target == nil {
            print("Houdini.app is not installed in ~/Applications. Latest release is v\(resolved).")
        } else {
            print("Houdini.app is not installed in ~/Applications. Release v\(resolved) is available.")
        }
    case .updateAvailable:
        print("Update available: v\(installed!) → v\(resolved)  (run: \(runHint))")
    case .upToDate:
        print("Already on the latest (v\(resolved)).")
    case .ahead:
        if target == nil {
            print("You're on v\(installed!) — newer than the latest release (v\(resolved)).")
        } else {
            print("v\(resolved) is older than your installed v\(installed!)  (downgrade: \(runHint))")
        }
    }
    exit(0)
}

/// After a successful update, report any stale non-owned Houdini copies for manual
/// removal. The updater never deletes outside its two owned paths (least-privilege).
private func reportLegacyArtifacts() {
    let legacy = LegacyArtifacts.detect()
    guard !legacy.isEmpty else { return }
    print("  Note: older/duplicate Houdini copies the updater does not manage:")
    for path in legacy { print("    • \(path)") }
    print("    Remove them by hand if unused — the updater only ever touches "
        + "~/Applications/Houdini.app and ~/.local/bin/houdini.")
}

/// The mutation: update through the verified per-tag install.sh with rename-aside
/// rollback (audit 07 R3 / Phase E2). `--yes`/`-y` is accepted for script-compat but
/// no confirmation is prompted — invoking `houdini update` is itself the intent, and
/// the delegated installer runs non-interactively (login item left as-is).
func runUpdateInstall(target: String?, yes: Bool) async {
    let installer = UpdateInstaller.live(userAgent: updateUserAgent)
    let updateTarget: UpdateTarget = target.map { .version($0) } ?? .latest

    switch await installer.run(target: updateTarget) {
    case .refused(let message):
        emitError("error: \(message)")
        exit(1)
    case .alreadyCurrent(let version):
        print("Already on the latest (v\(version)).")
        exit(0)
    case .ahead(let installed, let latest):
        print("You're on v\(installed) — newer than the latest release (v\(latest)). Nothing to update.")
        print("  (to move to an older release explicitly: houdini update \(latest))")
        exit(0)
    case .updated(let from, let to):
        let fromLabel = from.map { "v\($0)" } ?? "an earlier version"
        print("✓ Updated Houdini \(fromLabel) → v\(to).")
        print("  App: ~/Applications/Houdini.app   CLI: ~/.local/bin/houdini")
        print("  If Houdini is running, quit it (menu bar ▸ Quit) and relaunch to load v\(to).")
        reportLegacyArtifacts()
        exit(0)
    case .installedFresh(let version):
        print("✓ Installed Houdini v\(version).")
        reportLegacyArtifacts()
        exit(0)
    case .failed(let reason, let unchanged, let rollbackClean):
        let current = unchanged.map { "Your current install (v\($0)) is unchanged." }
            ?? "Your install is unchanged."
        emitError("✗ Update failed: \(reason). \(current)")
        if !rollbackClean {
            emitError("  ! rollback may be incomplete — check ~/Applications/Houdini.app "
                    + "and ~/.local/bin/houdini.")
        }
        exit(1)
    }
}
