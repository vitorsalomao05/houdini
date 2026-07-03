import Foundation
import FetcherCore

private func err(_ s: String) { FileHandle.standardError.write(Data((s + "\n").utf8)) }

/// Headless proof of the sticky-auth fix (`Houdini --authtest`): a Claude credential
/// that appears — or expires — while Houdini is already running is picked up by the
/// running `UsageModel` without a relaunch, and healthy polling never pays for it.
///
/// Every Keychain read is served from an in-memory `FakeKeychain`; the real Keychain,
/// disk, and network are never touched. Cookie presence is stubbed `false` and the OAuth
/// source has NO write closure (the injection seam only exposes a *read*), so a re-resolve
/// is read-only by construction — the fake's `writes` counter can only ever be 0.
///
/// The model is wired exactly like `HoudiniApp` (`resolveProvider` reads `session.currentProvider`,
/// `reresolveAuth` calls `session.refresh()`, and `session.onAuthChange` re-enters
/// `model.reloadAuth()`), except `resolveProvider` returns an offline `StubProvider` once
/// signed in so the flip is observed on `session.activeAuth`/`currentProvider` WITHOUT a
/// real fetch to api.anthropic.com. Exits non-zero on any failed assertion.
enum AuthTest {
    /// In-memory stand-in for the Claude Code OAuth Keychain item(s). Thread-safe because
    /// the injected read closure is `@Sendable`; in practice it is only ever called on the
    /// main actor. Records read invocations (to prove re-resolution runs) and write
    /// invocations (which stay 0 — nothing writes through this seam).
    final class FakeKeychain: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [String: Data] = [:]
        private var readCount = 0
        private var writeCount = 0

        /// Seed / mutate a fake item mid-test (used to make a credential "appear").
        func put(_ service: String, _ data: Data) {
            lock.lock(); defer { lock.unlock() }
            items[service] = data
        }

        /// The injected `keychainRead`: counts the read and yields the fake blob, or
        /// `.notFound` so discovery falls through (never hits the real Keychain).
        func read(_ service: String) throws -> Data {
            lock.lock(); defer { lock.unlock() }
            readCount += 1
            guard let d = items[service] else { throw CredentialError.notFound(service: service) }
            return d
        }

        var reads: Int { lock.lock(); defer { lock.unlock() }; return readCount }
        var writes: Int { lock.lock(); defer { lock.unlock() }; return writeCount }
    }

    /// The two candidate Keychain services production discovers, in order.
    private static let services = ClaudeOAuthCredentialSource.candidateKeychainServices

    /// A far-future, obviously-fake OAuth blob in the exact shape the parser expects.
    private static func fakeOAuthBlob() -> Data {
        Data("""
        {"claudeAiOauth":{"accessToken":"sk-ant-oat01-FAKE-AUTHTEST",\
        "expiresAt":4102444800000,"refreshToken":"sk-ant-ort01-FAKE-AUTHTEST"}}
        """.utf8)
    }

    /// Build a read-only, network-free resolver over a fake Keychain (no refresher, per the
    /// ADR-012 freeze; no cookie; no disk fallback).
    private static func resolver(_ store: FakeKeychain) -> ClaudeAuthResolver {
        let source = ClaudeOAuthCredentialSource(
            services: services,
            keychainRead: { try store.read($0) },
            fileRead: { nil },
            refresher: nil,
            now: { Date() })
        return ClaudeAuthResolver(oauthSource: source, cookiePresent: { false })
    }

    /// Pump the main run loop so the model's `Timer` fires and its main-actor fetch Tasks run.
    private static func pump(_ seconds: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    static func run() {
        MainActor.assumeIsolated {
            var pass = 0, fail = 0
            func check(_ name: String, _ cond: Bool) {
                if cond { pass += 1; err("  ✓ \(name)") } else { fail += 1; err("  ✗ \(name)") }
            }

            let interval: TimeInterval = 0.5
            err("=== authtest: sticky-auth re-resolution (fake Keychain; no real Keychain/disk/network) ===")

            // Isolated defaults so the real prefs are never touched.
            @MainActor func settings(_ suite: String) -> AppSettings {
                let name = "houdini.authtest.\(suite)"
                let d = UserDefaults(suiteName: name)!
                d.removePersistentDomain(forName: name)
                return AppSettings(defaults: d)
            }

            // ---- Phases 1 & 2: one continuous model run (empty store → credential appears) ----
            let store = FakeKeychain()
            let session = ClaudeSession(settings: settings("p12"), resolver: resolver(store))
            // `resolveProvider` returns an offline stub once the session has a credential, so a
            // sign-in never triggers a real network fetch; `reresolveAuth` drives the re-read.
            let model = UsageModel(
                refreshInterval: interval,
                resolveProvider: { session.currentProvider != nil ? StubProvider() : nil },
                reresolveAuth: { session.refresh() })
            session.onAuthChange = { [weak model] in model?.reloadAuth() }

            model.start()
            let readsAfterStart = store.reads          // session construction only; tick 0 is .loading
            err("--- phase 1: empty store stays signed out, re-resolving each tick ---")
            err("    reads after start(): \(readsAfterStart)")
            pump(interval * 3.2)                        // ~3 signed-out ticks

            let signedOutReads = store.reads
            err("    reads after signed-out ticks: \(signedOutReads) (Δ=\(signedOutReads - readsAfterStart))")
            check("state stays .signedOut across ticks", model.state.isSignedOut)
            check("re-resolution runs on signed-out ticks (keychainRead invoked)",
                  signedOutReads > readsAfterStart)
            check("at least one full re-resolve happened (Δreads ≥ 6)",
                  signedOutReads - readsAfterStart >= 6)
            check("no Keychain writes during phase 1", store.writes == 0)

            err("--- phase 2: a valid OAuth credential appears mid-run ---")
            let readsBeforeBlob = store.reads
            store.put("Claude Code-credentials", fakeOAuthBlob())   // credential "appears"
            pump(interval * 2.4)                        // within a tick or two

            check("session.activeAuth flipped to .oauth without relaunch", session.activeAuth == .oauth)
            check("session.currentProvider is non-nil after the credential appeared",
                  session.currentProvider != nil)
            check("model left the signed-out state", !model.state.isSignedOut)
            check("re-resolution observed the new item (reads grew)", store.reads > readsBeforeBlob)
            check("no Keychain writes during phase 2", store.writes == 0)

            // ---- Phase 3: healthy ticks must NOT re-resolve (no extra `security` spawns) ----
            err("--- phase 3: healthy state does not re-resolve ---")
            let store3 = FakeKeychain()
            let session3 = ClaudeSession(settings: settings("p3"), resolver: resolver(store3))
            // Always-healthy: a stub provider is fetched every tick, so state reaches .ok and
            // stays there; `reresolveAuth` must never fire in .ok.
            let model3 = UsageModel(
                refreshInterval: interval,
                resolveProvider: { StubProvider() },
                reresolveAuth: { session3.refresh() })
            session3.onAuthChange = { [weak model3] in model3?.reloadAuth() }

            model3.start()
            pump(interval * 1.6)                        // settle into .ok
            check("model reaches healthy .ok state", model3.state == .ok)
            let baselineReads = store3.reads
            pump(interval * 3.2)                        // several healthy ticks
            let healthyDelta = store3.reads - baselineReads
            err("    reads across healthy ticks: Δ=\(healthyDelta) (expected 0)")
            check("no keychainRead on healthy ticks", healthyDelta == 0)
            check("no Keychain writes during phase 3", store3.writes == 0)

            err("=== authtest: \(pass) passed, \(fail) failed ===")
            exit(fail == 0 ? 0 : 1)
        }
    }
}
