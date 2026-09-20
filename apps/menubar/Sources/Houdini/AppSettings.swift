import Foundation
import Combine

/// Which usage figure the menu bar shows. `auto` tracks the tightest limit; the
/// rest pin to a specific provider window. Persisted by raw value (UserDefaults).
enum PrimaryMetricChoice: String, CaseIterable, Identifiable, Sendable {
    case auto
    case fiveHour
    case weekly
    case sonnetWeekly
    case extraUsage

    var id: String { rawValue }

    /// User-facing name in the Settings picker.
    var displayName: String {
        switch self {
        case .auto:         return "Auto (tightest limit)"
        case .fiveHour:     return "5-hour"
        case .weekly:       return "Weekly"
        case .sonnetWeekly: return "Sonnet weekly"
        case .extraUsage:   return "Extra usage"
        }
    }

    /// The provider `UsageMetric.label` this choice pins to, or `nil` for `auto`.
    var metricLabel: String? {
        switch self {
        case .auto:         return nil
        case .fiveHour:     return "5-hour"
        case .weekly:       return "Weekly"
        case .sonnetWeekly: return "Sonnet weekly"
        case .extraUsage:   return "Extra usage ($)"
        }
    }
}

/// App-wide preferences, persisted to `UserDefaults` and published so the menu
/// bar label and the running `UsageModel` re-mirror them live (ADR-002 scope).
/// Loaded once at launch; every mutation writes through immediately.
@MainActor
final class AppSettings: ObservableObject {
    private enum Keys {
        static let primaryMetric = "houdini.primaryMetric"
        static let refreshInterval = "houdini.refreshIntervalSeconds"
        static let preferCookieAuth = "houdini.preferCookieAuth"
        static let showDesktopWidget = "houdini.showDesktopWidget"
        static let subscription = "houdini.subscription"
    }

    /// Refresh cadences offered in Settings. 60s is the ADR-002 default.
    static let allowedIntervals: [TimeInterval] = [30, 60, 120]
    static let defaultInterval: TimeInterval = 60

    private let defaults: UserDefaults

    @Published var subscription: TrackedSubscription {
        didSet {
            defaults.set(subscription.rawValue, forKey: Keys.subscription)
            if !subscription.metricChoices.contains(primaryMetric) {
                primaryMetric = .auto
            }
        }
    }

    @Published var primaryMetric: PrimaryMetricChoice {
        didSet { defaults.set(primaryMetric.rawValue, forKey: Keys.primaryMetric) }
    }

    @Published var refreshInterval: TimeInterval {
        didSet { defaults.set(refreshInterval, forKey: Keys.refreshInterval) }
    }

    /// Force the claude.ai cookie auth over the Claude Code OAuth token. A testing
    /// escape hatch (PROVIDERS.md fallback); defaults off. When on but no cookie is
    /// present yet, the resolver still falls back to OAuth so data never disappears.
    @Published var preferCookieAuth: Bool {
        didSet { defaults.set(preferCookieAuth, forKey: Keys.preferCookieAuth) }
    }

    /// Whether the floating desktop widget is shown. Opt-in (off by default) so a
    /// fresh install doesn't drop an unexpected panel on the user's desktop; the
    /// `DesktopWidgetController` observes this and shows/hides live.
    @Published var showDesktopWidget: Bool {
        didSet { defaults.set(showDesktopWidget, forKey: Keys.showDesktopWidget) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        subscription = defaults.string(forKey: Keys.subscription)
            .flatMap(TrackedSubscription.init(rawValue:)) ?? .claude

        // New installs default to the 5-hour session window (the figure users
        // glance at most). A previously saved choice is loaded verbatim, so only
        // people who never opened the picker move to the new default.
        let rawMetric = defaults.string(forKey: Keys.primaryMetric)
        primaryMetric = rawMetric.flatMap(PrimaryMetricChoice.init(rawValue:)) ?? .fiveHour

        // `double(forKey:)` returns 0 when unset → fall back to the default; also
        // clamp to a supported value so a stale/hand-edited key can't strand us.
        let stored = defaults.double(forKey: Keys.refreshInterval)
        refreshInterval = Self.allowedIntervals.contains(stored) ? stored : Self.defaultInterval

        preferCookieAuth = defaults.bool(forKey: Keys.preferCookieAuth)
        showDesktopWidget = defaults.bool(forKey: Keys.showDesktopWidget)
        if !subscription.metricChoices.contains(primaryMetric) {
            primaryMetric = .auto
        }
    }
}
