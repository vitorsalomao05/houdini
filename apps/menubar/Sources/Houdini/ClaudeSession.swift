import Foundation
import Combine
import FetcherCore

/// App-scoped Claude authentication state. Decides which credential is active
/// (Claude Code OAuth token → claude.ai cookie → signed out), drives the WebView
/// login, and stores/removes the cookie in the Keychain. The menu bar's
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

    /// Cached provider for the active auth; `UsageModel` reads this each fetch.
    private(set) var currentProvider: (any UsageProvider)?

    /// Set by the owner so the `UsageModel` re-fetches whenever auth changes.
    var onAuthChange: (() -> Void)?

    private let settings: AppSettings
    private let resolver: ClaudeAuthResolver
    private let store = CredentialStore()
    private var loginController: ClaudeLoginWindowController?
    private var cancellables = Set<AnyCancellable>()

    /// `resolver` is injectable purely as a testing seam (`--authtest`): a fake, in-memory
    /// credential source can be supplied so re-resolution is exercised without touching the
    /// real Keychain. Production always uses the default (real) resolver.
    init(settings: AppSettings, resolver: ClaudeAuthResolver = ClaudeAuthResolver()) {
        self.settings = settings
        self.resolver = resolver
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

    /// Open the WebView login. On success the captured cookie is stored, then auth
    /// is re-resolved when the window closes.
    func signIn() {
        if loginController == nil { loginController = ClaudeLoginWindowController() }
        loginController?.present(
            onSuccess: { [weak self] sessionKey in
                guard let self else { return }
                do {
                    try self.store.nativeWriteGenericPassword(
                        service: ClaudeCookieProvider.keychainService,
                        account: ClaudeCookieProvider.keychainAccount,
                        data: Data(sessionKey.utf8)
                    )
                    self.lastError = nil
                } catch {
                    // OSStatus only — never the cookie value.
                    self.lastError = "Couldn't save the Claude.ai session to the Keychain."
                }
            },
            onClose: { [weak self] in
                self?.loginController = nil
                self?.refresh()
            }
        )
    }

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
        case .oauth:  return "Claude Code token"
        case .cookie: return "Claude.ai login"
        case .none:   return "Not signed in"
        }
    }
}
