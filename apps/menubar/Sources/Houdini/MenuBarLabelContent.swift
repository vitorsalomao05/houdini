import SwiftUI
import FetcherCore

/// The content shown in the menu bar itself: primary metric, compact + colored.
/// The metric shown follows `settings.primaryMetric`; changing it in Settings
/// updates the bar live (this view observes `settings`).
struct MenuBarLabelContent: View {
    @ObservedObject var model: UsageModel
    @ObservedObject var settings: AppSettings

    /// Error with a last-good reading cached: the number shown is stale (MB-03).
    private var isStale: Bool { model.state.isError }

    var body: some View {
        if let primary = model.metrics.primary(for: settings.primaryMetric) {
            // Glyph tints with the bar (template, adaptive); only the number
            // carries the threshold color. When the reading is STALE (fetch error,
            // last-good value retained) the cue is never color-only: the number
            // drops its threshold color and dims (75% primary — 6.69:1 light /
            // 7.34:1 dark, still AA) and a small warning triangle appears.
            HStack(spacing: 4) {
                if settings.subscription == .claude {
                    ProviderGlyph()
                } else {
                    Image(systemName: "terminal").accessibilityLabel("ChatGPT · Codex")
                }
                if isStale {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.primary.opacity(0.75))
                }
                Text(Format.barLabel(primary))
                    .foregroundStyle(isStale ? Color.primary.opacity(0.75)
                                             : Thresholds.menuBarColor(primary.pct))
            }
            .font(.system(size: 13, weight: .medium))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(settings.subscription.displayName), " + (isStale
                ? "\(Format.barLabel(primary)), showing last value" : Format.barLabel(primary)))
        } else if model.state.isSignedOut {
            // No Claude credential → invite sign-in from the menu bar.
            HStack(spacing: 4) {
                Image(systemName: "person.crop.circle.badge.questionmark")
                Text("\(settings.subscription.shortName) · Sign in")
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.secondary)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(settings.subscription.displayName), sign in")
        } else {
            // No data yet, or an error before any good reading.
            HStack(spacing: 4) {
                Image(systemName: model.state.isError ? "exclamationmark.triangle.fill"
                                                      : "gauge.with.dots.needle.67percent")
                Text("\(settings.subscription.shortName) \(model.state.isError ? "—" : "…")")
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(model.state.isError ? Color.orange : Color.primary)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(settings.subscription.displayName), \(model.state.isError ? "usage unavailable" : "loading usage")")
        }
    }
}
