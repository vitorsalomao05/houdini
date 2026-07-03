import SwiftUI
import AppKit
import FetcherCore

/// Threshold colors: <60% normal, 60–85% amber, >85% red.
enum Thresholds {
    static func barColor(_ pct: Double?) -> Color {
        guard let p = pct else { return .gray }
        switch p {
        case ..<60: return .green
        case ..<85: return .orange
        default:    return .red
        }
    }

    /// Numeric-label color (popover rows) — "normal" stays adaptive (primary) so
    /// it doesn't shout when usage is low; amber/red kick in as the limit tightens.
    static func labelColor(_ pct: Double?) -> Color {
        guard let p = pct else { return .primary }
        switch p {
        case ..<60: return .primary
        case ..<85: return .orange
        default:    return .red
        }
    }

    /// Menu bar label color — full green/amber/red threshold scale (matches the
    /// popover gauges) so the at-a-glance number reads "comfortable" when low.
    /// Stays adaptive (primary) only when there's no percentage to color.
    static func menuBarColor(_ pct: Double?) -> Color {
        guard let p = pct else { return .primary }
        switch p {
        case ..<60: return menuBarGreen
        case ..<85: return menuBarAmber
        default:    return menuBarRed
        }
    }

    // MARK: Menu bar text pairs (WCAG 2.1 AA — MB-04)

    /// The system green/orange/red fail AA as 13pt TEXT on a light menu bar
    /// (measured: systemGreen #28CD41 → 2.12:1, systemOrange #FF9500 → 2.20:1,
    /// systemRed #FF3B30 → 3.55:1 vs #FFFFFF; worse vs an #EBEBEB bar). The bar
    /// label therefore uses explicit light/dark pairs — darker AA hues in light
    /// mode (#177239 → 6.00:1, #9A4E00 → 6.06:1, #B91C1C → 6.47:1 vs #FFFFFF;
    /// 5.03 / 5.09 / 5.43 vs #EBEBEB) and the system dark variants in dark mode
    /// (#32D74B → 8.40:1, #FF9F0A → 7.83:1, #FF453A → 4.73:1 vs #212121). Gauge
    /// fills and popover rows keep the system colors — those surfaces are
    /// forced-dark glass, where the dark variants already clear AA.
    private static let menuBarGreen = paired(light: 0x177239, dark: 0x32D74B)
    private static let menuBarAmber = paired(light: 0x9A4E00, dark: 0xFF9F0A)
    private static let menuBarRed   = paired(light: 0xB91C1C, dark: 0xFF453A)

    /// A color that resolves per-appearance at draw time (the menu bar's own
    /// appearance, not the app's) via a dynamic `NSColor` provider — the same
    /// mechanism the snapshotter already drives with `NSApp.appearance`.
    private static func paired(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                           green: CGFloat((hex >> 8) & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255,
                           alpha: 1)
        })
    }
}

extension Array where Element == UsageMetric {
    /// The "tightest limit" — the metric with the highest utilization %.
    var tightest: UsageMetric? {
        self.max { ($0.pct ?? -1) < ($1.pct ?? -1) }
    }

    /// The tightest *percentage* window — excludes the dollar overage so a missing
    /// pinned window falls back to a real "%" limit rather than the "$" figure.
    var tightestPercentage: UsageMetric? {
        filter { $0.dollars == nil }.tightest
    }

    /// Back-compat alias for the auto/tightest pick.
    var primary: UsageMetric? { tightest }

    /// Percentage windows (no dollar overage) ordered 5-hour → Weekly → the rest by
    /// tightness, so the prominent hero rings are the figures users glance at. Shared
    /// by the desktop widget and the popover so the two pick the SAME rings.
    var rankedRingWindows: [UsageMetric] {
        let priority: [String: Int] = ["5-hour": 0, "Weekly": 1]
        return filter { $0.dollars == nil }.sorted { a, b in
            let pa = priority[a.label] ?? 9, pb = priority[b.label] ?? 9
            if pa != pb { return pa < pb }
            return (a.pct ?? -1) > (b.pct ?? -1)
        }
    }

    /// The dollar-overage metric (e.g. "Extra usage ($)"), if present.
    var dollarOverage: UsageMetric? { first { $0.dollars != nil } }

    /// The metric to surface in the menu bar for the user's chosen mode.
    /// • `auto` → the tightest limit (may be the dollar overage — that's its job).
    /// • a pinned window → that exact window; if it isn't on the account (rare,
    ///   e.g. no 5-hour reading yet) fall back to the tightest *percentage* window
    ///   so the bar stays a clean "<window> N%", only resorting to the dollar
    ///   overage when there's no percentage window at all.
    func primary(for choice: PrimaryMetricChoice) -> UsageMetric? {
        guard let label = choice.metricLabel else { return tightest }
        if let exact = first(where: { $0.label == label }) { return exact }
        return tightestPercentage ?? tightest
    }
}

enum Format {
    static func shortLabel(_ label: String) -> String {
        switch label {
        case "5-hour":          return "5h"
        case "Weekly":          return "Weekly"
        case "Opus weekly":     return "Opus"
        case "Sonnet weekly":   return "Sonnet"
        case "Extra usage ($)": return "Extra"
        default:                return label
        }
    }

    /// Compact menu bar text. For the dollar overage we show used/limit, e.g.
    /// "$93/100" (or "$93" if no limit is known); percent windows stay
    /// "<short> <pct>%", e.g. "Weekly 8%".
    static func compactPrimary(_ m: UsageMetric) -> String {
        if let dollars = m.dollars {
            let used = Int((m.used ?? dollars).rounded())
            if let limit = m.limit {
                return "$\(used)/\(Int(limit.rounded()))"
            }
            return "$\(used)"
        }
        let pct = Int((m.pct ?? 0).rounded())
        return "\(shortLabel(m.label)) \(pct)%"
    }

    /// Menu bar text: percent-only for "%" windows ("6%"), used/limit for the
    /// dollar overage ("$93/100"). The metric name is intentionally dropped — the
    /// bar shows just the number; the popover keeps the full labels.
    static func barLabel(_ m: UsageMetric) -> String {
        if let dollars = m.dollars {
            let used = Int((m.used ?? dollars).rounded())
            if let limit = m.limit {
                return "$\(used)/\(Int(limit.rounded()))"
            }
            return "$\(used)"
        }
        return "\(Int((m.pct ?? 0).rounded()))%"
    }

    static func pctText(_ pct: Double?) -> String {
        guard let p = pct else { return "—" }
        return p == p.rounded() ? "\(Int(p))%" : String(format: "%.1f%%", p)
    }

    static func dollars(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "$%.2f", value)
    }

    /// Relative reset, e.g. "resets in 2h 14m" / "resets in 14m" / "resets in 5d 3h".
    static func resetString(_ date: Date?, now: Date = Date()) -> String? {
        guard let date else { return nil }
        let total = Int(date.timeIntervalSince(now))
        if total <= 0 { return "resets now" }
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours >= 24 {
            let days = hours / 24
            return "resets in \(days)d \(hours % 24)h"
        }
        if hours > 0 { return "resets in \(hours)h \(minutes)m" }
        return "resets in \(minutes)m"
    }
}

/// Spoken (VoiceOver) strings for the usage surfaces. Centralized in one place so
/// the ring gauge, the popover metric row, and the desktop spend block all announce
/// a limit as ONE meaningful phrase — e.g. "5-hour usage, 42 percent, resets in
/// 2h 10m" or "Extra usage, 93 dollars of 100 dollars" — instead of the visible,
/// abbreviated glyphs ("5h", "$93 / $100") that read as scattered fragments.
enum A11y {
    /// The window name spelled out for speech; visible labels abbreviate ("5h").
    /// The dollar overage's raw label ("Extra usage ($)") drops the "($)".
    static func window(_ label: String) -> String {
        label == "Extra usage ($)" ? "Extra usage" : label
    }

    /// The a11y LABEL for a percentage window — "<window> usage" (e.g. "Weekly usage").
    static func percentLabel(_ label: String) -> String { "\(window(label)) usage" }

    /// The a11y VALUE for a percentage window — "42 percent, resets in 2h 10m"
    /// (or "no reading" when the percentage is absent).
    static func percentValue(pct: Double?, resetAt: Date?, now: Date = Date()) -> String {
        guard let pct else { return "no reading" }
        let base = "\(Int(pct.rounded())) percent"
        if let reset = Format.resetString(resetAt, now: now) { return "\(base), \(reset)" }
        return base
    }

    /// The a11y VALUE for the dollar overage — "93 dollars of 100 dollars"
    /// (or "93 dollars" with no known budget).
    static func dollarValue(used: Double?, limit: Double?) -> String {
        let u = spoken(dollars: used)
        if let limit { return "\(u) of \(spoken(dollars: limit))" }
        return u
    }

    /// "$93.00" → "93 dollars"; keeps cents only when non-zero so VoiceOver doesn't
    /// spell out ".00" on every figure.
    private static func spoken(dollars: Double?) -> String {
        guard let d = dollars else { return "no reading" }
        let cents = Int((d * 100).rounded())
        if cents % 100 == 0 { return "\(cents / 100) dollars" }
        return String(format: "%.2f dollars", d)
    }
}
