#if DEBUG
import AppKit
import SwiftUI

/// A native, offline surface for keyboard/accessibility checks. This mode uses
/// an isolated preference suite and cannot start either real official client.
@MainActor
enum ConnectionPreview {
    static func run() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let defaults = UserDefaults(suiteName: "houdini.connection-preview")!
        defaults.removePersistentDomain(forName: "houdini.connection-preview")
        let settings = AppSettings(defaults: defaults)
        let session = PreviewData.session(settings: settings)
        let model = UsageModel(resolveProvider: {
            StubProvider(metrics: session.selected == .claude
                ? PreviewData.sampleMetrics() : PreviewData.codexMetrics())
        })
        session.onAuthChange = { model.reloadAuth(clearMetrics: true) }
        model.start()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 840, height: 810),
                              styleMask: [.titled, .closable, .resizable, .miniaturizable],
                              backing: .buffered, defer: false)
        window.title = "Houdini — subscription preview (sample data)"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading) {
                Text("Sample data · no provider requests").font(.caption).padding(.horizontal, 22)
                Text("Keyboard navigation: \(app.isFullKeyboardAccessEnabled ? "enabled" : "disabled")")
                    .font(.caption).padding(.horizontal, 22)
                SettingsView(settings: settings, launch: LaunchAtLogin(), session: session, model: model,
                             allowsSystemSettings: false)
            }
            UsagePopover(model: model, session: session, forceReduceTransparency: true)
                .padding(.top, 30)
        }.padding(12))
        window.center()
        window.makeKeyAndOrderFront(nil)
        app.activate(ignoringOtherApps: true)
        app.run()
        withExtendedLifetime((window, model, session)) {}
    }
}
#endif
