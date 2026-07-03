import SwiftUI
import AppKit
import FetcherCore

/// Headless `--snapshot <dir>` mode: render the real SwiftUI views (popover,
/// settings, menu bar label) to PNGs via `ImageRenderer`, in BOTH light and dark
/// appearances. Deterministic — no clicking/timing — and uses the same views the
/// running app does. Tries live usage first; if that fails (e.g. no Claude token
/// on this machine) it falls back to `PreviewData` so the populated UI is shown.
///
/// Note: `SettingsView` now uses native `Picker`/`Toggle` controls, which
/// `ImageRenderer` cannot draw — `settings-*.png` are therefore placeholders. The
/// popover (pure shapes) still renders faithfully. See `SettingsView` for why we
/// chose native controls over render fidelity.
enum Snapshotter {
    static func run(outputDir: String) {
        _ = NSApplication.shared // initialise AppKit so text/graphics render

        // HOUDINI_SNAPSHOT_SAMPLE=1 forces the curated PreviewData (deterministic
        // marketing shots that don't leak the operator's real account numbers).
        let forceSample = ProcessInfo.processInfo.environment["HOUDINI_SNAPSHOT_SAMPLE"] == "1"
        let metrics: [UsageMetric]
        if forceSample {
            FileHandle.standardError.write(Data("HOUDINI_SNAPSHOT_SAMPLE=1 — using sample data\n".utf8))
            metrics = PreviewData.sampleMetrics()
        } else {
            switch fetchSync() {
            case .success(let m) where !m.isEmpty:
                metrics = m
            default:
                FileHandle.standardError.write(Data("live fetch unavailable — using sample data\n".utf8))
                metrics = PreviewData.sampleMetrics()
            }
        }

        MainActor.assumeIsolated {
            render(metrics: metrics, dir: outputDir)
        }
        exit(0)
    }

    /// Bridge the async fetch into this synchronous CLI path. URLSession callbacks
    /// run off the main thread, so blocking here won't deadlock.
    private static func fetchSync() -> Result<[UsageMetric], Error> {
        let semaphore = DispatchSemaphore(value: 0)
        var out: Result<[UsageMetric], Error> = .success([])
        Task.detached {
            do { out = .success(try await ClaudeOAuthProvider().fetch()) }
            catch { out = .failure(error) }
            semaphore.signal()
        }
        semaphore.wait()
        return out
    }

    @MainActor
    private static func render(metrics: [UsageMetric], dir: String) {
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

        // Isolated defaults so a snapshot run never clobbers the user's real prefs.
        let settings = AppSettings(defaults: UserDefaults(suiteName: "houdini.snapshot") ?? .standard)
        settings.primaryMetric = .fiveHour // mirror the shipped default (out-of-the-box bar)
        settings.refreshInterval = 60
        let launch = LaunchAtLogin()
        let session = ClaudeSession(settings: settings)

        for scheme in [ColorScheme.light, .dark] {
            let suffix = scheme == .dark ? "dark" : "light"
            let model = UsageModel(previewResult: .success(metrics))
            // Error-with-cache: the bar must show a stale cue (dim + glyph), not
            // the frozen number in its normal threshold color (MB-03).
            let stale = UsageModel(previewState: .error("Network error: request timed out"),
                                   metrics: metrics)

            // The popover is now forced-dark glass (rendered once, all states, below).
            writePNG(SettingsView(settings: settings, launch: launch, session: session),
                     to: "\(dir)/settings-\(suffix).png", scheme: scheme)
            writePNG(MenuBarPreview(model: model, settings: settings, scheme: scheme),
                     to: "\(dir)/menubar-\(suffix).png", scheme: scheme)
            writePNG(MenuBarPreview(model: stale, settings: settings, scheme: scheme),
                     to: "\(dir)/menubar-stale-\(suffix).png", scheme: scheme)
        }

        renderPopover(metrics: metrics, session: session, dir: dir)
        renderWidget(metrics: metrics, session: session, dir: dir)
        FileHandle.standardError.write(Data("snapshots (light+dark) written to \(dir)\n".utf8))
    }

    /// Popover snapshots: the forced-dark glass card in every state (data / loading
    /// skeleton / needs-auth / error / stale), rendered over a faux desktop so the
    /// rounded card + hairline read. The live MenuBarExtra window material can't be
    /// captured offscreen, so `widgetRenderMode = .snapshot` draws the same opaque
    /// dark-glass approximation the widget uses — an approximation for review.
    @MainActor
    private static func renderPopover(metrics: [UsageMetric], session: ClaudeSession, dir: String) {
        let states: [(String, UsageModel)] = [
            ("ok",         UsageModel(previewResult: .success(metrics))),
            ("loading",    UsageModel()),                                   // .loading, no data → skeleton
            ("needs-auth", UsageModel(previewState: .signedOut)),
            ("error",      UsageModel(previewState: .error("Claude token expired — run `claude` to refresh your token."))),
            ("stale",      UsageModel(previewState: .error("Network error: request timed out"), metrics: metrics)),
        ]
        for (name, model) in states {
            let view = UsagePopover(model: model, session: session)
                .environment(\.widgetRenderMode, .snapshot)
                .padding(28)
                .background(WidgetBackdrop())
            writePNG(view, to: "\(dir)/popover-\(name).png", scheme: .dark)
        }

        // Accessibility: Reduce Transparency → solid #15101F card (same as the widget).
        let solid = UsagePopover(model: UsageModel(previewResult: .success(metrics)),
                                 session: session, forceReduceTransparency: true)
            .environment(\.widgetRenderMode, .snapshot)
            .padding(28)
            .background(WidgetBackdrop())
        writePNG(solid, to: "\(dir)/popover-reduce-transparency.png", scheme: .dark)

        // Legibility check: the LIVE ink-scrim path (not the snapshot approximation)
        // over a light "wallpaper", to confirm the forced-dark card holds AA contrast
        // when the system material is light.
        let lightCheck = UsagePopover(model: UsageModel(previewResult: .success(metrics)), session: session)
            .padding(28)
            .background(WidgetBackdrop(light: true))
        writePNG(lightCheck, to: "\(dir)/popover-light-backdrop.png", scheme: .dark)
    }

    /// Desktop-widget snapshots: both breakpoints (compact/regular), all states
    /// (data / loading / needs-auth / error), light + dark, plus the
    /// Reduce-Transparency solid fallback. Rendered over a faux desktop so the
    /// floating card + shadow read; the live behind-window blur can't be captured
    /// offscreen, so `widgetRenderMode = .snapshot` draws a translucent stand-in.
    @MainActor
    private static func render(_ model: UsageModel, _ session: ClaudeSession,
                              size: NSSize, lightBackdrop: Bool,
                              reduceTransparency: Bool, to path: String) {
        let view = ZStack {
            WidgetBackdrop(light: lightBackdrop)
            DesktopWidgetView(model: model, session: session,
                              forceReduceTransparency: reduceTransparency)
                .environment(\.widgetRenderMode, .snapshot)
        }
        .frame(width: size.width, height: size.height)
        // The card forces its own dark scheme internally; the outer scheme only sets
        // the backdrop's NSColor resolution, so .dark is fine for both backdrops.
        writePNG(view, to: path, scheme: .dark)
    }

    @MainActor
    private static func renderWidget(metrics: [UsageMetric], session: ClaudeSession, dir: String) {
        let regular = NSSize(width: 312, height: 232)  // card 280×200 + shadow margin
        let compact = NSSize(width: 252, height: 182)  // card 220×150 + shadow margin

        // Data, both sizes. The widget is a dark glass card in either appearance, so
        // "dark"/"light" here show it over a DARK vs a LIGHT wallpaper — the real
        // accessibility question (does the text hold AA over a light desktop?).
        for (suffix, light) in [("dark", false), ("light", true)] {
            render(UsageModel(previewResult: .success(metrics)), session,
                   size: regular, lightBackdrop: light, reduceTransparency: false,
                   to: "\(dir)/widget-regular-\(suffix).png")
            render(UsageModel(previewResult: .success(metrics)), session,
                   size: compact, lightBackdrop: light, reduceTransparency: false,
                   to: "\(dir)/widget-compact-\(suffix).png")
        }

        // States (over the dark wallpaper).
        render(UsageModel(), session, size: regular, lightBackdrop: false,
               reduceTransparency: false, to: "\(dir)/widget-loading-dark.png")
        render(UsageModel(previewState: .signedOut), session, size: regular, lightBackdrop: false,
               reduceTransparency: false, to: "\(dir)/widget-needs-auth-dark.png")
        render(UsageModel(previewState: .error("Network error: request timed out"), metrics: metrics),
               session, size: regular, lightBackdrop: false,
               reduceTransparency: false, to: "\(dir)/widget-error-dark.png")

        // Accessibility: Reduce Transparency → solid #15101F card.
        render(UsageModel(previewResult: .success(metrics)), session, size: regular, lightBackdrop: false,
               reduceTransparency: true, to: "\(dir)/widget-reduce-transparency-dark.png")

        // Marketing two-up (busy + healthy) over the wallpaper — the site asset.
        renderMarketing(session: session, to: "\(dir)/widget-marketing.png")
    }

    /// Two widget cards side by side (a busy account + a healthy one) over the
    /// wallpaper — replaces the site's `desktop-widget.png` with the native look.
    @MainActor
    private static func renderMarketing(session: ClaudeSession, to path: String) {
        let busy = UsageModel(previewResult: .success(PreviewData.sampleMetrics()))
        let healthy = UsageModel(previewResult: .success(PreviewData.healthyMetrics()))
        let card = NSSize(width: 312, height: 232)
        let view = ZStack {
            WidgetBackdrop()
            HStack(spacing: 4) {
                DesktopWidgetView(model: busy, session: session)
                    .environment(\.widgetRenderMode, .snapshot)
                    .frame(width: card.width, height: card.height)
                DesktopWidgetView(model: healthy, session: session)
                    .environment(\.widgetRenderMode, .snapshot)
                    .frame(width: card.width, height: card.height)
            }
            .padding(.horizontal, 8)
        }
        .frame(width: card.width * 2 + 24, height: card.height + 16)
        writePNG(view, to: path, scheme: .dark)
    }

    @MainActor
    private static func writePNG(_ view: some View, to path: String, scheme: ColorScheme) {
        // Drive both layers: NSAppearance so dynamic NSColors resolve correctly,
        // and the SwiftUI colorScheme environment so semantic colors flip.
        NSApp.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        let renderer = ImageRenderer(content: view.environment(\.colorScheme, scheme).tint(.brand))
        renderer.scale = 2
        guard let nsImage = renderer.nsImage,
              let tiff = nsImage.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let data = rep.representation(using: .png, properties: [:]) else {
            FileHandle.standardError.write(Data("failed to render \(path)\n".utf8))
            return
        }
        try? data.write(to: URL(fileURLWithPath: path))
    }
}

/// A faux desktop wallpaper behind the widget snapshots so the floating card and
/// its shadow read (the real panel sits over the user's wallpaper). A warm-to-cool
/// gradient with a soft highlight — not a flat color — so the glass edge shows.
private struct WidgetBackdrop: View {
    /// A light/bright wallpaper instead of the dark one, to verify the dark card's
    /// text holds AA contrast over a pale desktop.
    var light: Bool = false

    var body: some View {
        ZStack {
            if light {
                LinearGradient(
                    colors: [Color(hex: 0xE9D5FF), Color(hex: 0xF8FAFC), Color(hex: 0xBAE6FD)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
            } else {
                LinearGradient(
                    colors: [Color(hex: 0x2B1840), Color(hex: 0x10131F), Color(hex: 0x1B2A3A)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
                RadialGradient(
                    colors: [Color(hex: 0xE879F9, alpha: 0.22), .clear],
                    center: .topTrailing, startRadius: 0, endRadius: 260
                )
            }
        }
    }
}

/// A representative menu bar strip for the snapshot image (the live app uses
/// `MenuBarLabelContent` directly inside the system menu bar). The strip tone
/// follows the appearance so the colored label reads correctly in both modes.
private struct MenuBarPreview: View {
    @ObservedObject var model: UsageModel
    @ObservedObject var settings: AppSettings
    let scheme: ColorScheme

    var body: some View {
        HStack(spacing: 0) {
            Spacer()
            MenuBarLabelContent(model: model, settings: settings).padding(.horizontal, 10)
        }
        .frame(width: 240, height: 24, alignment: .trailing)
        .padding(.vertical, 3)
        .background(scheme == .dark ? Color(white: 0.13) : Color(white: 0.92))
    }
}
