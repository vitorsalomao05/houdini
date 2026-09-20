import SwiftUI
import AppKit

/// The Settings panel — reachable from the gear in the popover footer (a
/// `SettingsLink`) or the standard ⌘, shortcut.
///
/// The controls are **native** AppKit-backed SwiftUI primitives (`Picker`,
/// `Toggle`): they carry full keyboard navigation, VoiceOver labels and the
/// system focus ring for free, which matters more than pixel control on a
/// settings screen. Trade-off: `ImageRenderer` draws native controls as an
/// "unsupported" placeholder, so the `settings-*.png` docs screenshots are now
/// placeholders (the popover screenshot — pure shapes — still renders faithfully).
/// We deliberately do **not** reintroduce custom controls just to satisfy the
/// renderer; native UX/accessibility wins.
///
/// Type is Dynamic-Type-ready: every label goes through the shared `scaledFont`
/// (`@ScaledMetric`, see `SharedUI.swift`) instead of a fixed `.font(.system(size:))`,
/// matching the popover and desktop widget, and the panel uses a flexible width
/// (min/ideal/max) so any enlarged type grows the window instead of clipping. The
/// `Settings` scene sizes to content, so height follows automatically. (On macOS the
/// scale factor tracks `dynamicTypeSize`, which the system rarely drives, so the
/// resting size is what most users see — the mechanism is here and correct regardless.)
struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var launch: LaunchAtLogin
    @ObservedObject var session: SubscriptionSession
    @ObservedObject var model: UsageModel
    var allowsSystemSettings = true

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 8) {
                Image(systemName: "gauge.with.dots.needle.67percent").foregroundStyle(.tint)
                Text("Houdini Settings").scaledFont(15, weight: .semibold, relativeTo: .headline)
            }

            section("Subscription") {
                Picker("Subscription", selection: $settings.subscription) {
                    ForEach(TrackedSubscription.allCases) { subscription in
                        Text(subscription.displayName).tag(subscription)
                    }
                }
                .pickerStyle(.segmented)
                accountStatus
                caption(session.connectionContext)
                ConnectionActionsView(session: session)
                if session.selected == .claude {
                    caption("Houdini reads your existing Claude credential; Anthropic's terms restrict third-party use of subscription OAuth; use at your discretion.")
                    if session.claude.hasCookie {
                        Button("Remove saved Claude.ai session") { session.claude.signOut() }
                            .help("Removes only Houdini's saved session. Your Claude Code login stays unchanged.")
                    }
                }
            }

            section("Menu bar") {
                metricPicker
                caption("Which figure shows in the menu bar.")
            }

            section("Desktop widget") {
                desktopWidgetToggle
                caption("A floating panel with the selected subscription’s quota windows.")
            }

            section("Refresh") {
                row("Interval") { intervalPicker }
                caption("Applied live — the running timer reschedules, no restart.")
            }

            section("General") {
                launchToggle
                    .disabled(!allowsSystemSettings)
                if let error = launch.lastError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .scaledFont(11, relativeTo: .caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            section("About") {
                row("Version") {
                    Text(Self.appVersion)
                        .scaledFont(13)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(22)
        // Flexible width (was a hard 360) so enlarged Dynamic Type grows the panel
        // instead of clipping; ideal 360 keeps today's resting size. The Settings
        // scene sizes height to content, so vertical growth is automatic.
        .frame(minWidth: 340, idealWidth: 360, maxWidth: 480)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Subscription status

    private var accountStatus: some View {
        HStack(spacing: 6) {
            Image(systemName: model.state == .ok ? "checkmark.circle.fill" : "info.circle")
                .foregroundStyle(model.state == .ok ? Color.green : Color.secondary)
            Text(connectionStatus).scaledFont(13)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private var connectionStatus: String {
        if session.isSigningIn { return "Complete sign-in in your browser…" }
        switch model.state {
        case .ok: return "Connected · usage updated"
        case .loading: return "Checking usage…"
        case .signedOut: return "Connect to see your quota windows."
        case .error(let message): return message
        }
    }

    // MARK: - Primary metric (native radio group)

    private var metricPicker: some View {
        Picker("Primary metric", selection: $settings.primaryMetric) {
            ForEach(session.selected.metricChoices) { choice in
                Text(choice.displayName).tag(choice)
            }
        }
        .pickerStyle(.radioGroup)
        .labelsHidden()
        .accessibilityLabel("Menu bar metric")
    }

    // MARK: - Desktop widget (native switch)

    private var desktopWidgetToggle: some View {
        Toggle(isOn: $settings.showDesktopWidget) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Show desktop widget").scaledFont(13)
                Text("Drag it anywhere; it remembers its place.")
                    .scaledFont(11, relativeTo: .caption).foregroundStyle(.secondary)
            }
        }
        .toggleStyle(.switch)
        .tint(.brand)
    }

    // MARK: - Refresh interval (native segmented)

    private var intervalPicker: some View {
        Picker("Interval", selection: $settings.refreshInterval) {
            ForEach(AppSettings.allowedIntervals, id: \.self) { iv in
                Text("\(Int(iv))s").tag(iv)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
        .accessibilityLabel("Refresh interval")
    }

    // MARK: - Launch at login (native switch)

    private var launchToggle: some View {
        Toggle(isOn: Binding(
            get: { launch.isEnabled },
            set: { launch.setEnabled($0) }
        )) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Launch at login").scaledFont(13)
                Text(launch.statusText).scaledFont(11, relativeTo: .caption).foregroundStyle(.secondary)
            }
        }
        .toggleStyle(.switch)
        .tint(.green)
    }

    // MARK: - About

    /// Marketing version from the bundle (`CFBundleShortVersionString`, set in
    /// Info.plist and copied into the .app by build.sh). Bare-binary runs (the
    /// smoke-test flags) have no bundle plist, so they read "dev".
    static let appVersion: String =
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"

    // MARK: - Pieces

    @ViewBuilder
    private func section<Content: View>(_ title: String,
                                        @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .scaledFont(10, weight: .semibold, relativeTo: .caption2)
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func row<Trailing: View>(_ label: String,
                                     @ViewBuilder _ trailing: () -> Trailing) -> some View {
        HStack {
            Text(label).scaledFont(13)
            Spacer(minLength: 12)
            trailing()
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text).scaledFont(11, relativeTo: .caption).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
