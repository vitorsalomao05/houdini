import Foundation

// Owned-file manifest cleanup — the REPORT-only half (audit 07 §5.4 / Phase E3).
//
// `install.sh` installs to two FIXED paths (`~/Applications/Houdini.app`,
// `~/.local/bin/houdini`), so a normal upgrade overwrites in place — there is no
// version-numbered directory that accumulates (unlike Homebrew's Cellar). The only
// real "leftover old-version artifacts" are stale copies at *non-owned* locations
// from an older install convention (a copy dragged to the system `/Applications`, or
// a pre-rename `Tally.app` — ADR-009).
//
// Least-privilege is absolute here: `houdini update` NEVER deletes anything outside
// the two owned paths. It DETECTS these copies and REPORTS them for the user to remove
// by hand. It never touches user data, preferences, `~/.claude`, or the Keychain.

public enum LegacyArtifacts {
    /// Non-owned locations a previous install convention could have left an app copy.
    /// Returns those that currently exist, in a stable order, for the caller to print.
    /// Pure/read-only: it only probes existence.
    public static func detect(
        home: String = NSHomeDirectory(),
        pathExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) -> [String] {
        let candidates = [
            "/Applications/Houdini.app",         // system-wide drag-install (not owned by install.sh)
            "/Applications/Tally.app",           // pre-rename, system-wide (ADR-009)
            home + "/Applications/Tally.app",    // pre-rename, in the user Applications dir
        ]
        return candidates.filter(pathExists)
    }
}
