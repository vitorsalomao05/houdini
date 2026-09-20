import SwiftUI
import AppKit
import FetcherCore

/// The desktop widget card. A squircle glass panel that mirrors the menu bar's
/// data (same `UsageModel`, same 60s refresh) as draggable, resizable desktop
/// furniture. Two responsive breakpoints reflow the content:
///
/// • **regular** (≥260pt wide) — two ¾-ring gauges side by side + a spend block.
/// • **compact** (<260pt wide) — one hero ring + spend + a one-line secondary.
///
/// States: loading skeleton (no spinner), needs-auth CTA (no fake 0%), error,
/// last-value (stale data kept on error), and a subtle hover. Accessibility is
/// handled in `GlassCardBackground` (Reduce Transparency → solid, Increase
/// Contrast → border) and per-view (`accessibilityReduceMotion` gates animation).
struct DesktopWidgetView: View {
    @ObservedObject var model: UsageModel
    /// Present in the live app (drives the "Connect Claude" CTA); nil in headless
    /// snapshots without an auth session.
    var session: SubscriptionSession?
    /// Force the opaque Reduce-Transparency card (snapshots only — the live flag is
    /// read from the environment).
    var forceReduceTransparency: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false

    /// Transparent margin around the squircle so the drop shadow has room to render
    /// (the card itself stays opaque; the panel window is clear).
    private let shadowInset: CGFloat = 16

    var body: some View {
        GeometryReader { geo in
            let cardWidth = max(0, geo.size.width - shadowInset * 2)
            let compact = cardWidth < 260
            let corner: CGFloat = compact ? Theme.Radius.card : Theme.Radius.cardLarge

            card(compact: compact, size: CGSize(width: cardWidth,
                                                height: max(0, geo.size.height - shadowInset * 2)),
                 corner: corner)
                .frame(width: cardWidth, height: max(0, geo.size.height - shadowInset * 2))
                .frame(width: geo.size.width, height: geo.size.height) // center within window
        }
    }

    // MARK: - Card shell

    private func card(compact: Bool, size: CGSize, corner: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)
        return content(compact: compact, size: size)
            .padding(compact ? Theme.Spacing.cardPadding : Theme.Spacing.cardPaddingLarge)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(GlassCardBackground(cornerRadius: corner, forceSolid: forceReduceTransparency))
            .overlay {
                // Subtle hover lift — a faint top highlight, never animating shadow.
                if hovering {
                    shape.fill(Theme.Colors.hover)
                }
            }
            .clipShape(shape)
            .compositingGroup()
            // Two stacked shadows: a deep soft one + a tight contact one (static).
            // Tuned to fall within the 16pt transparent margin without clipping.
            .shadow(color: .black.opacity(0.45), radius: 12, x: 0, y: 8)
            .shadow(color: .black.opacity(0.22), radius: 3, x: 0, y: 1)
            .contentShape(Rectangle())
            .onHover { h in
                if reduceMotion { hovering = h }
                else { withAnimation(.easeOut(duration: Theme.Motion.hover)) { hovering = h } }
            }
            // The glass card is dark in both appearances, so its content is always
            // light — this keeps text at AA contrast even over a light wallpaper.
            .environment(\.colorScheme, .dark)
    }

    // MARK: - Content router

    @ViewBuilder
    private func content(compact: Bool, size: CGSize) -> some View {
        VStack(alignment: .leading, spacing: compact ? Theme.Spacing.sectionCompact : Theme.Spacing.section) {
            header
            if model.metrics.isEmpty {
                emptyState
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                if compact {
                    compactBody(size: size)
                } else {
                    regularBody(size: size)
                }
                Spacer(minLength: 0)
                footer
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: Theme.Spacing.header) {
            BrandWordmark(size: 13)
            Text(session?.displayName ?? "Claude")
                .scaledFont(9, relativeTo: .caption2).glassSecondaryText()
                .lineLimit(1)
            Spacer()
            StatusDot(state: model.state)
        }
    }

    // MARK: - Regular body (two rings + spend)

    private func regularBody(size: CGSize) -> some View {
        let rings = Array(ringMetrics.prefix(2))
        let ringD = min((size.width - 36 - 16) / max(1, CGFloat(rings.count)),
                        size.height * 0.46)
            .clamped(to: 60...150)
        return VStack(alignment: .leading, spacing: Theme.Spacing.ringStack) {
            HStack(spacing: Theme.Spacing.ringGap) {
                ForEach(Array(rings.enumerated()), id: \.offset) { _, m in
                    WidgetRingGauge(title: Format.shortLabel(m.label), pct: m.pct,
                                    resetText: Format.resetString(m.resetAt), diameter: ringD,
                                    accessibilityTitle: m.label)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(maxWidth: .infinity)
            if let dollar = dollarMetric { spendBlock(dollar, compact: false) }
        }
    }

    // MARK: - Compact body (one ring + spend + secondary line)

    private func compactBody(size: CGSize) -> some View {
        let primary = ringMetrics.first
        let ringD = min(size.width - 28, size.height * 0.50).clamped(to: 68...150)
        return VStack(alignment: .leading, spacing: 8) {
            if let primary {
                WidgetRingGauge(title: Format.shortLabel(primary.label), pct: primary.pct,
                                resetText: Format.resetString(primary.resetAt), diameter: ringD,
                                accessibilityTitle: primary.label)
                    .frame(maxWidth: .infinity)
            }
            if let dollar = dollarMetric { spendBlock(dollar, compact: true) }
            if let secondary = secondaryLine {
                Text(secondary).scaledFont(10, relativeTo: .caption2).glassSecondaryText()
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
        }
    }

    // MARK: - Spend block ($ hero + optional budget bar)

    private func spendBlock(_ m: UsageMetric, compact: Bool) -> some View {
        let amount = m.used ?? m.dollars
        let label = Format.shortLabel(m.label) == "Extra" ? "Extra usage" : m.label
        return VStack(alignment: .leading, spacing: Theme.Spacing.rowInternal) {
            if compact {
                // Compact: label as a tiny caption above; the hero on its own line so
                // the dollar figure is never clipped.
                Text(label.uppercased())
                    .scaledFont(9, weight: .semibold, relativeTo: .caption2).tracking(Theme.Typography.microTracking)
                    .glassSecondaryText()
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    spendHero(amount, m: m, size: 22)
                    if let limit = m.limit {
                        Text("/ \(Format.dollars(limit))")
                            .scaledFont(11, relativeTo: .caption).glassSecondaryText()
                            .monospacedDigit().fixedSize()
                    }
                    Spacer(minLength: 0)
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    spendHero(amount, m: m, size: 26)
                    if let limit = m.limit {
                        Text("/ \(Format.dollars(limit))")
                            .scaledFont(12, relativeTo: .callout).glassSecondaryText()
                            .monospacedDigit().fixedSize()
                    }
                    Spacer(minLength: 8)
                    Text(label)
                        .scaledFont(10, weight: .medium, relativeTo: .caption2).glassSecondaryText()
                        .lineLimit(1).minimumScaleFactor(0.6)
                }
            }
            if let limit = m.limit, limit > 0, let used = amount {
                // Thin budget bar — only when a real budget exists.
                ProgressBar(pct: min(100, used / limit * 100), color: Thresholds.barColor(m.pct))
                    .frame(height: 4)
            }
        }
        // One phrase — "Extra usage, 93 dollars of 100 dollars" — not a scattered
        // label, hero, "/ $100" and a naked bar.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(A11y.window(m.label))
        .accessibilityValue(A11y.dollarValue(used: amount, limit: m.limit))
    }

    /// The spend hero numeral — `fixedSize` so it is never truncated, whatever the
    /// breakpoint or trailing label width.
    private func spendHero(_ amount: Double?, m: UsageMetric, size: CGFloat) -> some View {
        Text(Format.dollars(amount))
            .font(.system(size: size, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(Thresholds.labelColor(m.pct))
            .lineLimit(1).fixedSize()
            .contentTransition(reduceMotion ? .identity : .numericText())
            .animation(reduceMotion ? nil : .easeOut(duration: Theme.Motion.value), value: amount)
    }

    // MARK: - Footer (last-updated)

    @ViewBuilder
    private var footer: some View {
        if isStale {
            staleChip
        } else if let updated = model.lastUpdated {
            (Text("Updated ") + Text(updated, style: .relative))
                .scaledFont(9, relativeTo: .caption2)
                .glassSecondaryText()
        }
    }

    private var staleChip: some View {
        HStack(spacing: 4) {
            Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 9))
                .accessibilityHidden(true) // decorative — the text carries it
            Text("Showing last value").scaledFont(9, relativeTo: .caption2)
        }
        .glassSecondaryText()
        .accessibilityElement(children: .combine)
    }

    // MARK: - Empty states (loading / needs-auth / error)

    @ViewBuilder
    private var emptyState: some View {
        switch model.state {
        case .loading:
            RingPairSkeleton(diameter: 92)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .signedOut:
            NeedsAuthView(session: session)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .error(let message):
            if model.needsLogin {
                NeedsAuthView(session: session)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ErrorStateView(message: message)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        case .ok:
            Text("No usage metrics available.")
                .scaledFont(12, relativeTo: .callout).glassSecondaryText()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Metric selection (shared with the popover via `[UsageMetric]`)

    /// Percentage windows ordered 5-hour → Weekly → the rest, so the two prominent
    /// rings are the figures users glance at. Shared so the popover picks the same.
    private var ringMetrics: [UsageMetric] { model.metrics.rankedRingWindows }

    private var dollarMetric: UsageMetric? { model.metrics.dollarOverage }

    /// Compact mode's one-line summary of the windows not shown as the hero ring.
    private var secondaryLine: String? {
        let rest = ringMetrics.dropFirst()
        guard !rest.isEmpty else { return nil }
        return rest.map { "\(Format.shortLabel($0.label)) \(Int(($0.pct ?? 0).rounded()))%" }
            .joined(separator: " · ")
    }

    private var isStale: Bool {
        if case .error = model.state { return !model.metrics.isEmpty }
        return false
    }
}

extension Comparable {
    /// Clamp a value into a closed range.
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
