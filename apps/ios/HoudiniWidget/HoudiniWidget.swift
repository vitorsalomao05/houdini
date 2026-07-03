import WidgetKit
import SwiftUI
import FetcherCore

/// Houdini Home Screen + Lock Screen widget (placeholder, but structurally complete).
///
/// It reads the **cached** `UsageSnapshot` the app wrote to the App Group — it does
/// not try to fake a live gauge. Timeline refresh is `.after(~15 min)`: Apple
/// budgets widget reloads (≈40–70/day) regardless of any interval we'd request, so
/// the copy is always honest ("updated X ago"). This is the iOS twin of ADR-002.
///
/// TODO(xcode): builds only as a WidgetKit extension target in Xcode (see
/// `project.yml`). The App Group + Keychain entitlements must match the app's.

// MARK: - Timeline

struct UsageEntry: TimelineEntry {
    let date: Date
    let snapshot: UsageSnapshot?
}

struct HoudiniProvider: TimelineProvider {
    func placeholder(in context: Context) -> UsageEntry {
        UsageEntry(date: Date(), snapshot: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (UsageEntry) -> Void) {
        completion(UsageEntry(date: Date(), snapshot: SharedSnapshot.read()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<UsageEntry>) -> Void) {
        let entry = UsageEntry(date: Date(), snapshot: SharedSnapshot.read())
        // Ask for ~15 min; Apple decides the real cadence. Honest copy covers the gap.
        let next = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date()
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

// MARK: - Views

/// The single most-constrained window (highest %) — the one number you actually
/// want at a glance, same choice the menu bar app makes.
private func tightest(_ snapshot: UsageSnapshot?) -> UsageMetric? {
    snapshot?.metrics
        .filter { $0.pct != nil }
        .max(by: { ($0.pct ?? 0) < ($1.pct ?? 0) })
}

struct HoudiniWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    var entry: UsageEntry

    var body: some View {
        switch family {
        case .accessoryInline:
            Text(inlineText)
        case .accessoryRectangular:
            rectangularLockScreen
        default:
            homeScreen
        }
    }

    private var metric: UsageMetric? { tightest(entry.snapshot) }

    private var inlineText: String {
        guard let m = metric, let pct = m.pct else { return "Houdini — sign in" }
        return "\(m.label) \(Int(pct.rounded()))%"
    }

    private var rectangularLockScreen: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Claude usage").font(.caption2).foregroundStyle(.secondary)
            if let m = metric, let pct = m.pct {
                Text("\(m.label) · \(Int(pct.rounded()))%").font(.headline)
                Gauge(value: min(max(pct, 0), 100), in: 0...100) { EmptyView() }
                    .gaugeStyle(.accessoryLinearCapacity)
            } else {
                Text("Open Houdini to sign in").font(.caption)
            }
        }
    }

    private var homeScreen: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Houdini").font(.caption).foregroundStyle(Theme.muted)
                Spacer()
                Text(updatedText).font(.caption2).foregroundStyle(Theme.muted)
            }
            if let m = metric, let pct = m.pct {
                Text("\(Int(pct.rounded()))%")
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.color(forPct: pct))
                Text(m.label).font(.subheadline).foregroundStyle(Theme.text)
                ProgressView(value: min(max(pct, 0), 100), total: 100)
                    .tint(Theme.color(forPct: pct))
            } else {
                Spacer()
                Text("Open Houdini to sign in")
                    .font(.subheadline).foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
    }

    /// "updated X ago" — never implies the widget is live.
    private var updatedText: String {
        guard let captured = entry.snapshot?.capturedAt else { return "—" }
        return "updated \(captured.formatted(.relative(presentation: .named)))"
    }
}

// MARK: - Widget

struct HoudiniWidget: Widget {
    let kind = "HoudiniWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: HoudiniProvider()) { entry in
            HoudiniWidgetEntryView(entry: entry)
                .containerBackground(Theme.bg, for: .widget)
        }
        .configurationDisplayName("Claude usage")
        .description("Your tightest Claude limit, updated a few times an hour.")
        .supportedFamilies([
            .systemSmall, .systemMedium,        // Home Screen
            .accessoryRectangular, .accessoryInline, // Lock Screen (iOS 16+)
        ])
    }
}
