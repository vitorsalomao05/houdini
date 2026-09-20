import SwiftUI
import FetcherCore

// Components shared by the desktop widget (`DesktopWidgetView`) and the menu bar
// popover (`UsagePopover`) so the two finishes never drift: the brand wordmark,
// the status dot, the needs-auth / error / loading states, the metric row, and the
// threshold-colored progress bar. Glass/material styling lives in `WidgetGlass`;
// gauges in `WidgetRingGauge`; threshold colors + formatting in `Formatting`.

// MARK: - Accessibility helpers (Dynamic Type + contrast)

/// A fixed-point system font that STILL scales with the user's text-size setting.
/// The widget/popover are tuned to specific point sizes, but a bare
/// `.font(.system(size:))` traps them at that size; wrapping through `@ScaledMetric`
/// keeps the exact resting size (scale factor 1.0 at the default) while letting the
/// text grow with Dynamic Type. Diameter-derived hero numerals stay fixed by design.
private struct ScaledSystemFont: ViewModifier {
    private let weight: Font.Weight
    private let design: Font.Design
    @ScaledMetric private var scaled: CGFloat

    init(size: CGFloat, weight: Font.Weight, design: Font.Design, relativeTo: Font.TextStyle) {
        self.weight = weight
        self.design = design
        _scaled = ScaledMetric(wrappedValue: size, relativeTo: relativeTo)
    }

    func body(content: Content) -> some View {
        content.font(.system(size: scaled, weight: weight, design: design))
    }
}

/// Secondary caption / reset / label text on the dark glass cards. Brighter than the
/// system `.secondary` (~55% white) so small 9–12pt type clears WCAG AA over the
/// `#15101F` glass, and lifts further under Increase Contrast — the contrast path
/// now raises TEXT, not just the card border. Both surfaces force `colorScheme:.dark`
/// so a fixed white opacity is always the correct "secondary on dark" tone.
private struct GlassSecondaryText: ViewModifier {
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        content.foregroundStyle(Theme.Colors.secondaryText(increasedContrast: contrast == .increased))
    }
}

extension View {
    /// System font at a tuned point size that scales with Dynamic Type (see `ScaledSystemFont`).
    func scaledFont(_ size: CGFloat, weight: Font.Weight = .regular,
                    design: Font.Design = .default,
                    relativeTo textStyle: Font.TextStyle = .body) -> some View {
        modifier(ScaledSystemFont(size: size, weight: weight, design: design, relativeTo: textStyle))
    }

    /// AA-legible secondary text on the dark glass (see `GlassSecondaryText`).
    func glassSecondaryText() -> some View { modifier(GlassSecondaryText()) }
}

// MARK: - Brand wordmark

/// The "Houdini" wordmark in the violet→magenta brand gradient. Sized by the host
/// (the widget header is compact at 13pt; the popover header is a touch larger).
struct BrandWordmark: View {
    var size: CGFloat = 13

    var body: some View {
        Text("Houdini")
            .scaledFont(size, weight: .semibold, design: .rounded, relativeTo: .headline)
            .foregroundStyle(
                LinearGradient(colors: [Theme.Colors.accent, Theme.Colors.accentMagenta],
                               startPoint: .leading, endPoint: .trailing)
            )
            // A heading, not a control: gives VoiceOver a clear card title in the
            // rotor and stops the gradient text reading as an ambiguous element.
            .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Status dot

/// The header status indicator: a green dot when fresh, a calm gray dot while
/// loading (no spinner), an amber triangle on error, a person glyph when signed
/// out. Shared so the widget and popover read identically.
struct StatusDot: View {
    let state: UsageModel.State

    var body: some View {
        indicator
            // A silent colored glyph is meaningless to VoiceOver — announce the state.
            .accessibilityElement()
            .accessibilityLabel("Status")
            .accessibilityValue(statusText)
    }

    @ViewBuilder
    private var indicator: some View {
        switch state {
        case .ok:
            Circle().fill(.green).frame(width: 7, height: 7)
        case .loading:
            // Lifted off `.secondary`@0.6 (near-invisible on the dark card) to a
            // legible calm gray dot.
            Circle().fill(Theme.Colors.statusLoading).frame(width: 7, height: 7)
        case .error:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10)).foregroundStyle(Theme.Colors.warning)
        case .signedOut:
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: 11)).foregroundStyle(Theme.Colors.statusMutedIcon)
        }
    }

    private var statusText: String {
        switch state {
        case .ok:        return "Up to date"
        case .loading:   return "Loading"
        case .error:     return "Error"
        case .signedOut: return "Signed out"
        }
    }
}

// MARK: - Needs-auth CTA

/// "Connect Claude" empty state: the wand glyph in the brand gradient, a one-line
/// invitation, and the sign-in button (present only with a live session — headless
/// snapshots pass nil). Centered; the caller sizes the surrounding frame.
struct NeedsAuthView: View {
    var session: SubscriptionSession?

    var body: some View {
        VStack(spacing: Theme.Spacing.state) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 26))
                .foregroundStyle(LinearGradient(colors: [Theme.Colors.accent, Theme.Colors.accentMagenta],
                                                startPoint: .top, endPoint: .bottom))
                .accessibilityHidden(true) // decorative — the copy + button carry the meaning
            Text("Connect \(session?.displayName ?? "Claude")")
                .scaledFont(14, weight: .semibold, relativeTo: .headline)
            Text("Sign in to see consumption, quota limits and reset times.")
                .scaledFont(11, relativeTo: .caption).glassSecondaryText()
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let session {
                ConnectionActionsView(session: session)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, Theme.Spacing.state)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Error state

/// Generic "can't read usage" empty state — a real fetch/credential failure (not a
/// sign-in prompt, which is `NeedsAuthView`). Centered; the caller sizes the frame.
struct ErrorStateView: View {
    let message: String

    var body: some View {
        VStack(spacing: Theme.Spacing.state) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 22)).foregroundStyle(Theme.Colors.warning)
                .accessibilityHidden(true) // decorative — the heading + message speak the error
            Text("Can't read usage")
                .scaledFont(13, weight: .medium, relativeTo: .body)
            Text(message)
                .scaledFont(11, relativeTo: .caption).glassSecondaryText()
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, Theme.Spacing.state)
        .frame(maxWidth: .infinity)
        // Read the whole state as one phrase: "Can't read usage, <reason>".
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Loading skeleton

/// The shared loading skeleton: two track-only ring gauges over a placeholder bar,
/// with a calm pulse (disabled under Reduce Motion). No spinner — the widget and
/// popover both use this so loading reads the same everywhere. The caller frames it.
struct RingPairSkeleton: View {
    var diameter: CGFloat = 92

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: Theme.Spacing.ringStack) {
            HStack(spacing: Theme.Spacing.ringGap) {
                WidgetRingGauge(title: "5h", pct: nil, resetText: nil,
                                diameter: diameter, isPlaceholder: true)
                WidgetRingGauge(title: "Weekly", pct: nil, resetText: nil,
                                diameter: diameter, isPlaceholder: true)
            }
            RoundedRectangle(cornerRadius: Theme.Radius.bar)
                .fill(Theme.Colors.skeleton)
                .frame(height: 22)
        }
        .frame(maxWidth: .infinity)
        .modifier(SkeletonPulse(enabled: !reduceMotion))
        // One calm "Loading" announcement instead of two placeholder gauges reading
        // "no reading" apiece.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading usage")
    }
}

/// Calm loading pulse (opacity), disabled under Reduce Motion. Shared by every
/// skeleton so the cadence matches across surfaces.
struct SkeletonPulse: ViewModifier {
    let enabled: Bool
    @State private var dim = false

    func body(content: Content) -> some View {
        content
            .opacity(enabled ? (dim ? 0.55 : 1.0) : 1.0)
            .animation(enabled ? .easeInOut(duration: Theme.Motion.pulse).repeatForever(autoreverses: true) : nil,
                       value: dim)
            .onAppear { if enabled { dim = true } }
    }
}

// MARK: - Metric row

/// A compact metric line — label, threshold-colored value, a thin progress bar, and
/// the relative reset. Uses the same threshold scale + `numericText` transition as
/// the widget's gauges so the popover and widget never drift. Used by the popover
/// for the windows not promoted to hero rings (e.g. Sonnet/Opus weekly, Extra $).
struct MetricRow: View {
    let metric: UsageMetric

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let isDollar = metric.dollars != nil
        let amount = metric.used ?? metric.dollars
        let label = isDollar ? "Extra usage" : metric.label
        let value = isDollar
            ? (metric.limit.map { "\(Format.dollars(amount)) / \(Format.dollars($0))" }
                ?? Format.dollars(amount))
            : Format.pctText(metric.pct)
        // The bar represents a limit being filled — hide it when there's nothing to
        // fill (a dollar overage with no known budget), exactly like the widget's
        // spend bar (`DesktopWidgetView.spendBlock`), rather than drawing an empty
        // track that reads as "no spend".
        let barPct: Double? = {
            if isDollar {
                guard let limit = metric.limit, limit > 0, let used = amount else { return nil }
                return min(100, used / limit * 100)
            }
            return metric.pct
        }()

        return VStack(alignment: .leading, spacing: Theme.Spacing.rowInternal) {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .scaledFont(12, weight: .medium, relativeTo: .callout)
                    .glassSecondaryText()
                Spacer(minLength: 8)
                Text(value)
                    .scaledFont(12, weight: .semibold, relativeTo: .callout)
                    .monospacedDigit()
                    .foregroundStyle(Thresholds.labelColor(metric.pct))
                    .contentTransition(reduceMotion ? .identity : .numericText())
                    .animation(reduceMotion ? nil : .easeOut(duration: Theme.Motion.value), value: value)
            }
            if let barPct {
                ProgressBar(pct: barPct, color: Thresholds.barColor(metric.pct))
                    .frame(height: 4)
            }
            if let reset = Format.resetString(metric.resetAt) {
                Text(reset).scaledFont(10, relativeTo: .caption2).glassSecondaryText()
            }
        }
        // One phrase per limit — "Sonnet weekly usage, 61 percent, resets in 5d 3h"
        // or "Extra usage, 93 dollars of 100 dollars" — not label/number as separate
        // swipes with a naked bar in between.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isDollar ? "Extra usage" : A11y.percentLabel(metric.label))
        .accessibilityValue(isDollar
            ? A11y.dollarValue(used: amount, limit: metric.limit)
            : A11y.percentValue(pct: metric.pct, resetAt: metric.resetAt))
    }
}

// MARK: - Progress bar

/// Threshold-colored progress bar (`ProgressView`'s tint can't vary per value
/// cleanly). Shared by the popover rows and the widget's spend bar.
struct ProgressBar: View {
    let pct: Double
    let color: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.Colors.track)
                Capsule()
                    .fill(color)
                    .frame(width: max(0, min(1, pct / 100)) * geo.size.width)
            }
        }
        .frame(height: 6)
        // Decorative: the percentage/dollars are always announced by the enclosing
        // row/spend element, so the bar is noise to VoiceOver.
        .accessibilityHidden(true)
    }
}

// MARK: - Footer hover

/// Subtle affordance for the popover footer icons: the glyph brightens from
/// secondary to full and a faint rounded highlight fades in on pointer HOVER or
/// keyboard FOCUS, and a visible focus ring is drawn while focused. `.buttonStyle(.plain)`
/// otherwise suppresses the system ring, leaving keyboard users no visible focus —
/// so the enclosing control passes its `.focused` state in and this reuses the same
/// hover look. Motion is gated by Reduce Motion (the state still flips, without the
/// transition); the focus ring appears instantly, which is motion-safe.
struct FooterHover: ViewModifier {
    /// Keyboard focus, owned by the enclosing button's `.focused` binding.
    var focused: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false

    func body(content: Content) -> some View {
        let active = hovering || focused
        return content
            .foregroundStyle(.primary)
            .opacity(active ? 1.0 : 0.6)
            .padding(5)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                    .fill(active ? Theme.Colors.highlight : .clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                    .strokeBorder(Color.accentColor, lineWidth: focused ? 2 : 0)
            )
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
            .onHover { h in
                if reduceMotion { hovering = h }
                else { withAnimation(.easeOut(duration: Theme.Motion.hover)) { hovering = h } }
            }
    }
}

extension View {
    /// Apply the shared popover-footer affordance to an icon button's label. Pass the
    /// enclosing control's keyboard-focus state so focus shows a visible ring.
    func footerHover(focused: Bool = false) -> some View { modifier(FooterHover(focused: focused)) }
}
