import Foundation
import Combine
import FetcherCore

/// App-scoped Claude authentication state. Decides which credential is active
/// (Claude Code OAuth token → saved claude.ai cookie → signed out) and starts
/// the official Claude Code browser login. The menu bar's
/// `UsageModel` reads `currentProvider` on each fetch, so sign-in/out and the
/// prefer-cookie toggle take effect without restarting the app.
@MainActor
final class ClaudeSession: ObservableObject {
    /// The credential currently driving the provider (shown in Settings).
    @Published private(set) var activeAuth: ClaudeAuthKind = .none
    /// Whether each credential exists right now (Settings context lines).
    @Published private(set) var hasOAuthToken = false
    @Published private(set) var hasCookie = false
    /// Last non-sensitive error from a sign-in attempt (never contains the cookie).
    @Published private(set) var lastError: String?
    @Published private(set) var isSigningIn = false

    /// Cached provider for the active auth; `UsageModel` reads this each fetch.
    private(set) var currentProvider: (any UsageProvider)?

    /// Set by the owner so the `UsageModel` re-fetches whenever auth changes.
    var onAuthChange: (() -> Void)?

    private let settings: AppSettings
    private let resolver: ClaudeAuthResolver
    private let store = CredentialStore()
    private let login: @MainActor () async throws -> Void
    private var loginTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    /// `resolver` is injectable purely as a testing seam (`--authtest`): a fake, in-memory
    /// credential source can be supplied so re-resolution is exercised without touching the
    /// real Keychain. Production always uses the default (real) resolver.
    init(settings: AppSettings, resolver: ClaudeAuthResolver = ClaudeAuthResolver(),
         login: (@MainActor () async throws -> Void)? = nil) {
        self.settings = settings
        self.resolver = resolver
        self.login = login ?? {
            guard let executable = ClaudeCodeLogin.findExecutable() else {
                throw ClaudeCodeLogin.LoginError.missingClient
            }
            try await ClaudeCodeLogin(executableURL: executable).signIn()
        }
        refresh()
        // Re-resolve when the user flips the prefer-cookie escape hatch.
        settings.$preferCookieAuth
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)
    }

    /// Re-read credentials, recompute the active provider, and notify the owner —
    /// but ONLY when the resolved outcome actually changed. Gating the callback is what
    /// makes re-resolution safe to drive from the poll loop: `UsageModel`'s signed-out /
    /// error re-resolve calls back here, and `onAuthChange` re-enters `reloadAuth()` →
    /// `refreshNow()` → (re-resolve) → `refresh()`; firing it unconditionally on an
    /// unchanged signed-out tick would recurse forever. The "outcome" is the pair
    /// (active-auth kind, provider present?) — enough to know a credential appeared,
    /// vanished, or swapped kinds so a re-fetch is warranted.
    func refresh() {
        let previousAuth = activeAuth
        let hadProvider = currentProvider != nil
        hasOAuthToken = resolver.hasUsableOAuthToken()
        hasCookie = resolver.hasSessionCookie()
        activeAuth = resolver.resolve(preferCookie: settings.preferCookieAuth)
        currentProvider = resolver.makeProvider(preferCookie: settings.preferCookieAuth)
        if activeAuth != previousAuth || (currentProvider != nil) != hadProvider {
            onAuthChange?()
        }
    }

    /// The official client owns the browser, OAuth callback and credential writes.
    /// Completion triggers discovery and a fresh usage request through the owner.
    func signIn() {
        guard loginTask == nil else { return }
        lastError = nil
        isSigningIn = true
        loginTask = Task { [weak self] in
            guard let self else { return }
            defer { self.isSigningIn = false; self.loginTask = nil }
            do {
                try await self.login()
                try Task.checkCancellation()
                // An explicit Claude Code connection takes precedence over a legacy
                // testing preference; the saved cookie remains untouched as fallback.
                self.settings.preferCookieAuth = false
                self.refresh()
                if !self.hasOAuthToken {
                    self.lastError = "Claude Code finished, but no usable subscription credential was found. Complete sign-in in Claude Code and try again."
                }
                self.onAuthChange?()
            } catch is CancellationError {
                // Cancellation leaves all existing credentials untouched.
            } catch let error as ClaudeCodeLogin.LoginError {
                if error != .cancelled { self.lastError = error.localizedDescription }
            } catch {
                self.lastError = "Claude Code sign-in did not finish. Open Claude Code to complete sign-in, then refresh Houdini."
            }
        }
    }

    func cancelSignIn() { loginTask?.cancel() }

    /// Remove the stored cookie and re-resolve (falls back to OAuth, else signed out).
    func signOut() {
        try? store.nativeDeleteGenericPassword(
            service: ClaudeCookieProvider.keychainService,
            account: ClaudeCookieProvider.keychainAccount
        )
        lastError = nil
        refresh()
    }

    /// Human-readable active-auth label for the Settings indicator.
    var activeAuthLabel: String {
        switch activeAuth {
        case .oauth:  return "Claude Code credential detected"
        case .cookie: return "Saved Claude.ai session detected"
        case .none:   return "No Claude credential detected"
        }
    }
}
