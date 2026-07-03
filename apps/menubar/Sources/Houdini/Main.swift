import Foundation

// Custom entry point so we can support a headless `--snapshot <dir>` mode (renders
// the real SwiftUI views to PNGs with live data) in addition to the GUI app.
@main
enum Main {
    static func main() {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--snapshot"), args.count > i + 1 {
            Snapshotter.run(outputDir: args[i + 1])
            return
        }
        if let i = args.firstIndex(of: "--selftest") {
            let interval = (args.count > i + 1 ? Double(args[i + 1]) : nil) ?? 3
            let duration = (args.count > i + 2 ? Double(args[i + 2]) : nil) ?? 8
            SelfTest.run(interval: interval, duration: duration)
            return
        }
        if args.contains("--metrictest") {
            SelfTest.metricTest()
            return
        }
        if args.contains("--widgettest") {
            MainActor.assumeIsolated { WidgetTest.run() }
            return
        }
        if args.contains("--launchtest") {
            SelfTest.launchTest()
            return
        }
        if args.contains("--authtest") {
            AuthTest.run()
            return
        }
        // Headless login-item toggles used by install.sh (offer at install,
        // cleanup at uninstall) — same SMAppService path as the Settings toggle.
        if args.contains("--register-login-item") {
            SelfTest.setLoginItem(true)
            return
        }
        if args.contains("--unregister-login-item") {
            SelfTest.setLoginItem(false)
            return
        }
        HoudiniMenuBarApp.main()
    }
}
