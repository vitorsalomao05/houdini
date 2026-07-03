import Foundation
import Combine
import FetcherCore

private func err(_ s: String) { FileHandle.standardError.write(Data((s + "\n").utf8)) }

/// Headless proof modes for the things that are awkward to screenshot:
/// • `--selftest`   — drives the real `UsageModel` timer and changes the interval
///                    live, proving the timer reschedules without a restart; then
///                    runs a persistent-429 stub proving the rate-limit backoff
///                    widens the effective interval and resets on success.
/// • `--metrictest` — asserts the known-answer menu-bar text for every
///                    primary-metric choice (deterministic `PreviewData`) and
///                    exits non-zero on any mismatch (DX-07).
/// • `--launchtest` — calls SMAppService.register()/unregister() and reports the
///                    real result (ad-hoc signing usually can't fully register).
enum SelfTest {
    // MARK: Interval reschedule

    /// Starts at `interval`, logs every refresh, then halfway through switches to
    /// a faster cadence live. The gap between logged refreshes proves the change
    /// took effect without restarting. Uses a stub provider so timing is clean.
    static func run(interval: TimeInterval, duration: TimeInterval) {
        MainActor.assumeIsolated {
            let model = UsageModel(provider: StubProvider(), refreshInterval: interval)
            var cancellables = Set<AnyCancellable>()
            let start = Date()
            var lastTick = start

            model.$lastUpdated
                .compactMap { $0 }
                .removeDuplicates()
                .sink { _ in
                    let now = Date()
                    let elapsed = String(format: "%.1f", now.timeIntervalSince(start))
                    let delta = String(format: "%.1f", now.timeIntervalSince(lastTick))
                    lastTick = now
                    let primary = model.metrics.primary.map(Format.compactPrimary) ?? "—"
                    err("[t+\(elapsed)s] refresh (Δ\(delta)s) activeInterval=\(model.refreshInterval)s primary=\(primary)")
                }
                .store(in: &cancellables)

            model.start()
            err("=== selftest: starting at interval=\(interval)s for \(duration)s ===")

            // Halfway through, switch to a faster cadence — live, no restart.
            let faster = max(0.5, interval / 3)
            Timer.scheduledTimer(withTimeInterval: duration / 2, repeats: false) { _ in
                Task { @MainActor in
                    err(">>> live change: setRefreshInterval(\(interval)s → \(faster)s) — no restart")
                    model.setRefreshInterval(faster)
                }
            }

            RunLoop.main.run(until: Date().addingTimeInterval(duration))
            err("=== selftest done (ended at activeInterval=\(model.refreshInterval)s) ===")
            cancellables.removeAll()

            let backoffOK = backoffPhase(interval: 0.4)
            exit(backoffOK ? 0 : 1)
        }
    }

    // MARK: Rate-limit backoff

    /// Fails every `fetch()` with `.rateLimited` until `failFirst` attempts have
    /// happened, then succeeds — timestamping each attempt so the test can measure
    /// the real gap between polls. `@unchecked Sendable`: mutable state is
    /// lock-guarded.
    private final class RateLimit429Stub: UsageProvider, @unchecked Sendable {
        let id = "stub-429"
        let displayName = "Stub (429)"
        let authMethod: AuthMethod = .keychainOAuth
        let capabilities: Capabilities = [.usagePct, .resetTimer, .dollarBalance]
        let refreshInterval: TimeInterval = 60

        private let lock = NSLock()
        private let failFirst: Int
        private var attempts: [Date] = []

        init(failFirst: Int) { self.failFirst = failFirst }

        var recordedAttempts: [Date] {
            lock.lock(); defer { lock.unlock() }
            return attempts
        }

        func fetch() async throws -> [UsageMetric] {
            lock.lock()
            attempts.append(Date())
            let n = attempts.count
            lock.unlock()
            guard n > failFirst else { throw ProviderError.rateLimited }
            return PreviewData.sampleMetrics()
        }
    }

    /// Persistent-429 backoff proof: with a provider that rate-limits the first
    /// three fetches, the gap between fetch attempts must widen multiplicatively
    /// (≈2×, 4×, 8× the base interval — skips of 1, 3, 7 ticks), then snap back
    /// to ≈1× after the first success. Prints each measured gap; returns whether
    /// all gaps fell inside a generous timing window.
    @MainActor
    private static func backoffPhase(interval: TimeInterval) -> Bool {
        let stub = RateLimit429Stub(failFirst: 3)
        let model = UsageModel(provider: stub, refreshInterval: interval)
        err("=== backofftest: persistent 429 must widen the effective interval (base=\(interval)s) ===")
        model.start()
        // Attempts land at ~0, 2×, +4×, +8× the interval (14 ticks), then every
        // 1× after the success — 25 intervals covers the reset proof with margin.
        let phaseStart = Date()
        RunLoop.main.run(until: Date().addingTimeInterval(interval * 25))

        let attempts = stub.recordedAttempts
        for (i, at) in attempts.enumerated() {
            err(String(format: "  attempt #%d at t+%.2fs", i + 1, at.timeIntervalSince(phaseStart)))
        }
        let deltas = zip(attempts.dropFirst(), attempts).map { $0.0.timeIntervalSince($0.1) }
        // Expected gap (in multiples of the base interval) and accepted window.
        let expected: [(multiple: Double, range: ClosedRange<Double>)] = [
            (2, 1.5...3.0),   // after 429 #1: skip 1 tick
            (4, 3.0...6.0),   // after 429 #2: skip 3 ticks
            (8, 6.0...12.0),  // after 429 #3: skip 7 ticks
            (1, 0.5...1.8),   // success → reset to the user's cadence
        ]
        var ok = deltas.count >= expected.count
        if !ok { err("  FAIL: only \(attempts.count) fetch attempts recorded") }
        for (i, exp) in expected.enumerated() where i < deltas.count {
            let multiple = deltas[i] / interval
            let inWindow = exp.range.contains(multiple)
            ok = ok && inWindow
            let verdict = inWindow ? "ok" : "FAIL"
            err(String(format: "  attempt #%d → #%d: Δ%.2fs ≈ %.1f× base (expected ~%.0f×) %@",
                       i + 1, i + 2, deltas[i], multiple, exp.multiple, verdict))
        }
        err("=== backofftest \(ok ? "PASS" : "FAIL"): interval widened 2×→4×→8× under 429, reset on success ===")
        return ok
    }

    // MARK: Primary-metric switch

    /// For each `PrimaryMetricChoice`, assert the exact menu-bar text against a
    /// known answer. `PreviewData.sampleMetrics()` is deterministic (5-hour 32%,
    /// Weekly 95%, Sonnet weekly 61%, Extra usage $93/100), so the expected strings
    /// are fixed — a formatting or metric-selection regression makes this exit
    /// non-zero instead of green-lighting whatever got printed (DX-07).
    static func metricTest() {
        var pass = 0, fail = 0
        func check(_ name: String, got: String, want: String) {
            if got == want {
                pass += 1
                err("  ✓ \(name) → \"\(got)\"")
            } else {
                fail += 1
                err("  ✗ \(name) → got \"\(got)\", want \"\(want)\"")
            }
        }

        let metrics = PreviewData.sampleMetrics()
        err("=== metrictest: menu-bar text per primary-metric choice ===")
        // Known answers for the sample fixture. `auto` picks the tightest limit —
        // Weekly at 95% beats the $93/100 overage (93%).
        let expected: [PrimaryMetricChoice: String] = [
            .auto: "95%",
            .fiveHour: "32%",
            .weekly: "95%",
            .sonnetWeekly: "61%",
            .extraUsage: "$93/100",
        ]
        for choice in PrimaryMetricChoice.allCases {
            let text = metrics.primary(for: choice).map(Format.barLabel) ?? "—"
            let name = choice.displayName.padding(toLength: 22, withPad: " ", startingAt: 0)
            check("\(name) menu bar", got: text, want: expected[choice] ?? "—")
        }

        MainActor.assumeIsolated {
            // What a *fresh* install shows (no saved preference) vs. a user who
            // already chose. Isolated, volatile suites so the real prefs are
            // untouched; values flow through the real AppSettings persistence path.
            err("--- default resolution (clean vs. saved UserDefaults) ---")

            let cleanName = "houdini.metrictest.clean"
            let clean = UserDefaults(suiteName: cleanName)!
            clean.removePersistentDomain(forName: cleanName)
            let freshChoice = AppSettings(defaults: clean).primaryMetric
            let freshText = metrics.primary(for: freshChoice).map(Format.barLabel) ?? "—"
            check("clean install pins 5-hour", got: freshChoice.rawValue,
                  want: PrimaryMetricChoice.fiveHour.rawValue)
            check("clean install menu bar", got: freshText, want: "32%")

            let savedName = "houdini.metrictest.saved"
            let saved = UserDefaults(suiteName: savedName)!
            saved.removePersistentDomain(forName: savedName)
            // Simulate a user who explicitly picked Extra usage, then relaunched.
            AppSettings(defaults: saved).primaryMetric = .extraUsage
            let keptChoice = AppSettings(defaults: saved).primaryMetric
            let keptText = metrics.primary(for: keptChoice).map(Format.barLabel) ?? "—"
            check("saved choice survives relaunch", got: keptChoice.rawValue,
                  want: PrimaryMetricChoice.extraUsage.rawValue)
            check("saved=extra usage menu bar", got: keptText, want: "$93/100")
            saved.removePersistentDomain(forName: savedName)
        }

        // Fallback: if the pinned 5-hour window is absent (rare), the bar should
        // land on the next % window (Weekly 95%) — never the dollar overage
        // unless it's alone.
        err("--- fallback when the 5-hour window is absent ---")
        let no5h = metrics.filter { $0.label != "5-hour" }
        let fbText = no5h.primary(for: .fiveHour).map(Format.barLabel) ?? "—"
        check("5-hour pinned but missing falls back to next % window", got: fbText, want: "95%")

        if fail == 0 {
            err("metrictest: PASS — \(pass) checks")
        } else {
            err("metrictest: FAIL — \(fail) of \(pass + fail) checks failed")
        }
        exit(fail == 0 ? 0 : 1)
    }

    // MARK: Login-item registration (used by install.sh)

    /// Register or unregister the *installed* app as a login item via the same
    /// `SMAppService.mainApp` path the Settings toggle uses — so the installer's
    /// "start at login" offer stays consistent with what the UI shows. Prints the
    /// resulting status (an ad-hoc build can land in `.requiresApproval`, which the
    /// user then approves in System Settings ▸ General ▸ Login Items). Idempotent:
    /// `register()` is guarded on the current status. Exits non-zero only on a
    /// thrown error so callers (install.sh) can react.
    static func setLoginItem(_ enable: Bool) {
        MainActor.assumeIsolated {
            let launch = LaunchAtLogin()
            let ok = launch.setEnabled(enable)
            let verb = enable ? "register" : "unregister"
            err("login-item \(verb): \(launch.statusText)")
            if let e = launch.lastError { err("login-item \(verb) error: \(e)") }
            exit(ok ? 0 : 1)
        }
    }

    // MARK: Launch-at-login

    /// Exercises SMAppService for real and reports what an ad-hoc signed build
    /// actually does. Registers, prints status + any error, then unregisters.
    static func launchTest() {
        MainActor.assumeIsolated {
            let launch = LaunchAtLogin()
            err("=== launchtest: SMAppService.mainApp ===")
            err("  initial status : \(launch.status.rawValue) (\(launch.statusText))")

            let okOn = launch.setEnabled(true)
            err("  register()     : returned ok=\(okOn)")
            err("  status now     : \(launch.status.rawValue) (\(launch.statusText))")
            if let e = launch.lastError { err("  error          : \(e)") }

            let okOff = launch.setEnabled(false)
            err("  unregister()   : returned ok=\(okOff)")
            err("  status now     : \(launch.status.rawValue) (\(launch.statusText))")
            if let e = launch.lastError { err("  error          : \(e)") }
            exit(0)
        }
    }
}
