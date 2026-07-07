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
/// Type scales with the user's text-size setting: every label goes through the
/// shared `scaledFont` (see `SharedUI.swift`) rather than a fixed
/// `.font(.system(size:))`, and the panel uses a flexible width (min/ideal/max)
/// so enlarged text grows the window instead of clipping. The `Settings` scene
/// sizes to content, so height follows automatically.
struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var launch: LaunchAtLogin
    @ObservedObject var session: ClaudeSession

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 8) {
                Image(systemName: "gauge.with.dots.needle.67percent").foregroundStyle(.tint)
                Text("Houdini Settings").scaledFont(15, weight: .semibold, relativeTo: .headline)
            }

            section("Claude account") {
                accountStatus
                accountButtons
                preferCookieToggle
                if let error = session.lastError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .scaledFont(11, relativeTo: .caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            section("Menu bar") {
                metricPicker
                caption("Which figure shows in the menu bar.")
            }

            section("Desktop widget") {
                desktopWidgetToggle
                caption("A floating glass panel on your desktop with the same usage and spend.")
            }

            section("Refresh") {
                row("Interval") { intervalPicker }
                caption("Applied live — the running timer reschedules, no restart.")
            }

            section("General") {
                launchToggle
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

    // MARK: - Claude account

    /// Active auth indicator: "Claude Code token" | "Claude.ai login" | "Not signed in".
    private var accountStatus: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: authIcon).foregroundStyle(authColor)
                // Two runs (label + bold value) as sibling Texts rather than a
                // Text(+)Text concatenation, so each can carry the scaledFont
                // modifier (a View modifier, not composable with Text's `+`).
                HStack(spacing: 0) {
                    Text("Active: ").scaledFont(13)
                    Text(session.activeAuthLabel).scaledFont(13, weight: .semibold)
                }
            }
            caption(accountContext)
            caption("Houdini reads your existing Claude credential; Anthropic's terms restrict third-party use of subscription OAuth; use at your discretion.")
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var authIcon: String {
        switch session.activeAuth {
        case .oauth:  return "key.fill"
        case .cookie: return "globe"
        case .none:   return "person.crop.circle.badge.questionmark"
        }
    }

    private var authColor: Color {
        switch session.activeAuth {
        case .oauth, .cookie: return .green
        case .none:           return .orange
        }
    }

    /// One line of context about what's available and why.
    private var accountContext: String {
        switch session.activeAuth {
        case .oauth:
            return session.hasCookie
                ? "Using your Claude Code token. A claude.ai login is also saved."
                : "Reusing the Claude Code OAuth token — no separate login needed."
        case .cookie:
            return session.hasOAuthToken
                ? "Using your claude.ai login (preferred over the Claude Code token)."
                : "Using your claude.ai login."
        case .none:
            return "Sign in to claude.ai, or run Claude Code, to show your usage."
        }
    }

    private var accountButtons: some View {
        HStack(spacing: 8) {
            Button(session.hasCookie ? "Re-sign in to Claude.ai…" : "Sign in to Claude.ai…") {
                session.signIn()
            }
            if session.hasCookie {
                Button("Sign out") { session.signOut() }
            }
        }
    }

    /// Escape hatch (requirement C): force the cookie path for testing.
    private var preferCookieToggle: some View {
        Toggle(isOn: $settings.preferCookieAuth) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Prefer Claude.ai login").scaledFont(13)
                Text("Use the cookie even when a Claude Code token exists.")
                    .scaledFont(11, relativeTo: .caption).foregroundStyle(.secondary)
            }
        }
        .toggleStyle(.switch)
    }

    // MARK: - Primary metric (native radio group)

    private var metricPicker: some View {
        Picker("Primary metric", selection: $settings.primaryMetric) {
            ForEach(PrimaryMetricChoice.allCases) { choice in
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
    }
}
