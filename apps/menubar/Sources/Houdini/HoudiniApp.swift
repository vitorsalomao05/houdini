import SwiftUI
import AppKit
import FetcherCore

/// Owns the app-scoped `UsageModel` and starts its 60s timer at launch.
///
/// The refresh timer lives HERE (app/model scope), never inside the menu/popover
/// view — a timer hosted inside the MenuBarExtra content stalls (known macOS bug,
/// see ARCHITECTURE.md "Menu bar app"). This is the only surface that hits a true
/// 60s cadence (ADR-002).
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Preferences (primary metric + refresh interval), persisted to UserDefaults.
    let settings = AppSettings()
    /// Launch-at-login state via SMAppService.
    let launch = LaunchAtLogin()
    /// Claude auth state (Claude Code token → claude.ai cookie → signed out).
    lazy var session = ClaudeSession(settings: settings)
    /// The model reads its interval from `settings` and reads its provider from `session`
    /// on every fetch, so auth changes apply without a restart. While signed-out / in an
    /// error state it also asks `session` to re-read the Keychain (`reresolveAuth`), so a
    /// credential that appears (or expires) after launch is picked up without a relaunch.
    lazy var model = UsageModel(
        settings: settings,
        resolveProvider: { [weak self] in self?.session.currentProvider },
        reresolveAuth: { [weak self] in self?.session.refresh() }
    )
    /// Floating desktop widget (NSPanel). Shares the model/session, so it tracks the
    /// same 60s refresh and auth state as the menu bar. Observes `showDesktopWidget`.
    lazy var desktopWidget = DesktopWidgetController(model: model, session: session, settings: settings)

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Agent app — no Dock icon. Also set via LSUIElement in Info.plist; this
        // covers running the bare binary outside the bundle.
        NSApp.setActivationPolicy(.accessory)
        launch.refresh()
        // Re-fetch immediately whenever the active Claude credential changes.
        session.onAuthChange = { [weak self] in self?.model.reloadAuth() }
        model.start()
        // Instantiate the widget controller: its `showDesktopWidget` subscription
        // fires with the current value, showing the panel if the user enabled it.
        _ = desktopWidget
    }
}

struct HoudiniMenuBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            UsagePopover(model: appDelegate.model, session: appDelegate.session)
                .tint(.brand)
        } label: {
            MenuBarLabelContent(model: appDelegate.model, settings: appDelegate.settings)
        }
        // .window gives us a real popover we can lay out freely (ARCHITECTURE.md).
        .menuBarExtraStyle(.window)

        // Standard Settings scene → ⌘, and the popover's gear (SettingsLink).
        Settings {
            SettingsView(settings: appDelegate.settings,
                         launch: appDelegate.launch,
                         session: appDelegate.session)
                .tint(.brand)
        }
    }
}
