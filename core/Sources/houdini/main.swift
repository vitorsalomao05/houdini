import Foundation
import FetcherCore

// houdini — Phase 1 validation tool (ROADMAP.md).
// Fetches the "claude" provider snapshot and prints it as readable JSON to stdout.
// No UI, no colors. NEVER prints the OAuth token.
//
// JSON is the only output mode, so `--json` is accepted and ignored — an explicit
// flag lets scripting consumers pin a stable contract. Unknown flags print usage
// and exit 64 (EX_USAGE).

func emitError(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

let usage = """
houdini — local-first AI usage snapshots, as JSON on stdout

USAGE:
  houdini [<provider-id>] [--json]   fetch a provider snapshot (default: claude)
  houdini update [--check]           update Houdini (see: houdini update --help)
  houdini --version                  print the version
  houdini --help                     show this help

EXIT CODES:
  0   success
  1   unexpected error
  2   provider error (auth, network, decode)
  64  usage error (unknown flag or provider id)
"""

// MARK: - Top-level (implicit `fetch`) verb

/// Parse the default verb's flags + positionals, then fetch. `--help`/`--version`
/// short-circuit here; unknown flags exit 64. The `update` verb is dispatched
/// separately (below) so its own flags aren't rejected by this loop.
func runTopLevel(arguments: [String]) async {
    var positionals: [String] = []
    for argument in arguments {
        switch argument {
        case "--help", "-h":
            print(usage)
            exit(0)
        case "--version":
            print("houdini \(houdiniVersion)")
            exit(0)
        case "--json":
            continue // JSON is the only output mode; accepted for a stable contract.
        default:
            guard !argument.hasPrefix("-") else {
                emitError("error: unknown flag '\(argument)'\n\n\(usage)")
                exit(64) // EX_USAGE
            }
            positionals.append(argument)
        }
    }
    await runFetch(providerId: positionals.first ?? "claude")
}

// MARK: - Commands

/// The implicit `fetch` verb: snapshot one provider and print it as JSON.
func runFetch(providerId: String) async {
    let registry = ProviderRegistry.makeDefault()

    guard let provider = registry.provider(id: providerId) else {
        emitError("error: no provider registered with id '\(providerId)'\n\n\(usage)")
        exit(64) // EX_USAGE
    }

    do {
        let snapshot = try await provider.snapshot()

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601

        let json = try encoder.encode(snapshot)
        if let text = String(data: json, encoding: .utf8) {
            print(text)
        }
    } catch let error as ProviderError {
        emitError("error: \(error)")
        exit(2)
    } catch {
        emitError("error: \(error)")
        exit(1)
    }
}

// MARK: - Verb dispatch

// The first argument selects the verb. `update` (Phase E) is intercepted here so its
// own flags (`--check`, `--json`, `-y`) are parsed in that verb's context rather than
// rejected by the top-level flag loop. No provider is named `update`, so there is no
// collision with the implicit `fetch` path.
let arguments = Array(CommandLine.arguments.dropFirst())

switch arguments.first {
case "update":
    await runUpdate(arguments: Array(arguments.dropFirst()))
default:
    await runTopLevel(arguments: arguments)
}
