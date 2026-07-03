import Foundation
import Combine
import FetcherCore

/// App-scoped view model. Polls a `UsageProvider` every `refreshInterval` seconds
/// and publishes the result. Keeps the last good reading on error (never flashes
/// empty), per ARCHITECTURE.md. On `.rateLimited` the automatic cadence backs off
/// multiplicatively (skip 1, 3, then 7 ticks — 2×/4×/8× the interval, capped) and
/// snaps back to the user's cadence on the next success; manual Refresh is never
/// gated.
@MainActor
final class UsageModel: ObservableObject {
    enum State: Equatable {
        case loading
        case ok
        case error(String)
        case signedOut           // no Claude credential at all → prompt to sign in
        var isError: Bool { if case .error = self { return true } else { return false } }
        var isSignedOut: Bool { self == .signedOut }
    }

    @Published private(set) var metrics: [UsageMetric] = []
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var state: State = .loading
    /// True when the last failure was a claude.ai cookie expiry — drives the
    /// "Sign in to Claude" CTA off the typed error, not the message text.
    @Published private(set) var needsLogin = false

    private let provider: any UsageProvider
    /// When set, the active provider is read from the session's cache on each fetch (so
    /// sign-in/out and the prefer-cookie toggle take effect immediately). `nil` → signed
    /// out. When unset, the fixed `provider` above is used (previews / self-tests).
    private let resolveProvider: (@MainActor () -> (any UsageProvider)?)?
    /// Optional self-heal: re-read the Keychain for a credential that appeared or expired
    /// while Houdini was already running. Invoked from `refreshNow()` ONLY in the
    /// signed-out / error states (never on healthy ticks), so "install Houdini, then log
    /// into Claude Code" is picked up without a relaunch. `nil` for previews / self-tests.
    private let reresolveAuth: (@MainActor () -> Void)?
    /// Live, not constant — Settings can change it and the timer reschedules.
    private(set) var refreshInterval: TimeInterval
    private var timer: Timer?
    /// The single in-flight fetch. A monotonic `fetchGeneration` stamps each one so
    /// a late-completing fetch (e.g. against a credential the user just removed)
    /// can never resurrect stale state after an auth change.
    private var fetchTask: Task<Void, Never>?
    private var fetchGeneration = 0
    private var cancellables = Set<AnyCancellable>()

    // MARK: Rate-limit backoff (real, not just copy — ARC-02/CORE-06/MB-06)
    /// Timer ticks to swallow before the next automatic fetch. Set after a
    /// `.rateLimited` failure, decremented per tick, cleared on success.
    private var ticksToSkip = 0
    /// Consecutive `.rateLimited` failures. Drives the multiplicative skip
    /// (2^strikes − 1 ticks → 2×, 4×, 8× the base interval). Capped where the
    /// skip saturates so it can't overflow.
    private var rateLimitStrikes = 0
    /// Skip at most 7 ticks → the effective interval never exceeds 8× the
    /// user's cadence (8 min at the default 60s).
    private static let maxBackoffTicks = 7
    private static let maxBackoffStrikes = 3 // (1 << 3) − 1 == maxBackoffTicks

    init(provider: any UsageProvider = ClaudeOAuthProvider(),
         refreshInterval: TimeInterval = 60,
         settings: AppSettings? = nil,
         resolveProvider: (@MainActor () -> (any UsageProvider)?)? = nil,
         reresolveAuth: (@MainActor () -> Void)? = nil) {
        self.provider = provider
        self.resolveProvider = resolveProvider
        self.reresolveAuth = reresolveAuth
        self.refreshInterval = settings?.refreshInterval ?? refreshInterval

        // Mirror the user's interval choice live: when Settings publishes a new
        // value, reschedule the running timer without restarting the app.
        settings?.$refreshInterval
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] interval in self?.setRefreshInterval(interval) }
            .store(in: &cancellables)
    }

    /// Build a model from pre-fetched data, for the headless `--snapshot` renderer.
    convenience init(previewResult: Result<[UsageMetric], Error>, refreshInterval: TimeInterval = 60) {
        self.init(refreshInterval: refreshInterval)
        switch previewResult {
        case .success(let m):
            metrics = m
            lastUpdated = Date()
            state = m.isEmpty ? .error("No usage metrics available") : .ok
        case .failure(let error):
            state = .error(UsageModel.message(for: error))
        }
    }

    /// Build a model pinned to an explicit state, for headless `--snapshot` renders
    /// of the desktop widget's loading / needs-auth / error variants. No timer runs.
    convenience init(previewState: State, metrics: [UsageMetric] = [], needsLogin: Bool = false) {
        self.init()
        self.metrics = metrics
        self.lastUpdated = metrics.isEmpty ? nil : Date()
        self.needsLogin = needsLogin
        self.state = previewState
    }

    /// Start the immediate fetch + repeating timer. Idempotent.
    func start() {
        guard timer == nil else { return }
        refreshNow()
        scheduleTimer()
    }

    /// Change the refresh cadence and reschedule the live timer (if running)
    /// without restarting the app. No-op when the value is unchanged.
    func setRefreshInterval(_ interval: TimeInterval) {
        guard interval != refreshInterval else { return }
        refreshInterval = interval
        guard timer != nil else { return } // not started yet → start() will pick it up
        timer?.invalidate()
        timer = nil
        scheduleTimer()
    }

    private func scheduleTimer() {
        let t = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            // Hop back onto the main actor; the Timer block itself is non-isolated.
            Task { @MainActor in self?.timerTick() }
        }
        // Coalesce wake-ups proportionally (still sub-interval); we don't need
        // sub-second accuracy, but a 5s tolerance on a 30s timer is fine too.
        t.tolerance = min(5, refreshInterval * 0.1)
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// True only for the live app model (a resolver is wired). The popover reads it to
    /// avoid kicking a real fetch / re-resolve from the headless `--snapshot` preview
    /// models, which have no resolver.
    var resolvesAuthLive: Bool { resolveProvider != nil }

    /// One automatic timer tick. While rate-limit backoff is active, swallow the
    /// tick instead of fetching — only the automatic cadence widens; the Refresh
    /// button and popover-open path still call `refreshNow()` directly, so a
    /// manual retry is always allowed.
    private func timerTick() {
        if ticksToSkip > 0 {
            ticksToSkip -= 1
            return
        }
        refreshNow()
    }

    /// Fetch once now. Safe to call from the Refresh button or the timer.
    func refreshNow() {
        // Auth self-heal: only while signed-out or in an error state, ask the session to
        // re-read the Keychain so a Claude credential that appeared (or expired) while the
        // app was already running is picked up without a relaunch. Deliberately skipped on
        // healthy / loading ticks so steady-state polling never spawns extra `security`
        // reads — a fully signed-out re-resolve costs up to ~6 short `/usr/bin/security`
        // spawns (3 usability checks × 2 candidate Keychain items). Re-entrancy is bounded
        // by `ClaudeSession.refresh()`, which fires its change callback only on an actual
        // outcome change (see there).
        if state.isSignedOut || state.isError { reresolveAuth?() }

        // Auth-aware: when a resolver is wired, pick the current provider each time
        // so sign-in/out and the prefer-cookie toggle apply without a restart.
        let activeProvider: (any UsageProvider)? = resolveProvider.map { $0() } ?? provider
        guard let activeProvider else {
            // No credential → signed out. Drop stale data; the UI shows the CTA.
            invalidateFetch()
            needsLogin = false
            state = .signedOut
            metrics = []
            lastUpdated = nil
            return
        }

        guard fetchTask == nil else { return } // one fetch in flight at a time
        if metrics.isEmpty { state = .loading } // only show the spinner before first data

        let generation = fetchGeneration
        fetchTask = Task { @MainActor in
            do {
                let fresh = try await activeProvider.fetch()
                guard generation == self.fetchGeneration else { return } // superseded → drop
                self.metrics = fresh
                self.lastUpdated = Date()
                self.needsLogin = false
                self.state = .ok
                // Success ends any rate-limit backoff: snap back to the user's cadence.
                self.rateLimitStrikes = 0
                self.ticksToSkip = 0
            } catch {
                guard generation == self.fetchGeneration else { return } // superseded → drop
                // Last-good cache: keep `metrics`/`lastUpdated`; just flag the reason.
                self.needsLogin = (error as? ProviderError).map { if case .needsLogin = $0 { true } else { false } } ?? false
                self.state = .error(UsageModel.message(for: error))
                if case ProviderError.rateLimited = error {
                    // Widen the automatic cadence: skip 1, 3, then 7 ticks (2×/4×/8×
                    // the interval, capped) until a fetch succeeds again.
                    self.rateLimitStrikes = min(self.rateLimitStrikes + 1, Self.maxBackoffStrikes)
                    self.ticksToSkip = min((1 << self.rateLimitStrikes) - 1, Self.maxBackoffTicks)
                }
            }
            if generation == self.fetchGeneration { self.fetchTask = nil }
        }
    }

    /// Re-resolve auth and fetch immediately. Call after sign-in / sign-out / a
    /// prefer-cookie change so the menu bar reflects the new credential at once.
    func reloadAuth() {
        // Cancel + supersede any in-flight fetch so its (old-credential) result can
        // never land late and overwrite the new state.
        invalidateFetch()

        // Reflect a sign-out instantly, even if a fetch was still in flight.
        if let resolveProvider, resolveProvider() == nil {
            needsLogin = false
            state = .signedOut
            metrics = []
            lastUpdated = nil
            return
        }
        refreshNow()
    }

    /// Supersede the current fetch: bump the generation (so a late result is
    /// ignored), cancel the task, and clear the handle.
    private func invalidateFetch() {
        fetchGeneration &+= 1
        fetchTask?.cancel()
        fetchTask = nil
    }

    /// Human-readable, token-safe error text. Credential/auth failures name the
    /// actual fix instead of a number — `.authExpired` is the CLI OAuth token
    /// going stale, and the honest remedy is re-running `claude`, not the
    /// claude.ai cookie sign-in (CORE-02/05).
    static func message(for error: Error) -> String {
        if let providerError = error as? ProviderError {
            switch providerError {
            case .authExpired:
                return "Claude token expired — run `claude` to refresh your token."
            case .needsLogin:
                return "Claude.ai session expired — sign in again."
            case .rateLimited:
                return "Rate limited — backing off, will retry."
            case .credential(let detail):
                return detail
            case .network(let detail):
                return "Network error: \(detail)"
            default:
                return providerError.description
            }
        }
        return error.localizedDescription
    }
}
