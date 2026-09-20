import AppKit
import FetcherCore

/// Headless validation of the desktop widget's window behavior — invoked via
/// `Houdini --widgettest`. Proves, without UI scripting, the persistence and
/// recovery contract: the frame + displayID round-trip through UserDefaults, a
/// fresh controller restores them, an off-screen frame is clamped back onto a
/// visible screen, and the resize limits are wired. Exits non-zero on any failure.
@MainActor
enum WidgetTest {
    static func run() {
        _ = NSApplication.shared
        var pass = 0, fail = 0
        func check(_ name: String, _ cond: Bool) {
            if cond { pass += 1; print("  ✓ \(name)") } else { fail += 1; print("  ✗ \(name)") }
        }
        func approx(_ a: NSRect, _ b: NSRect, _ tol: CGFloat = 1.0) -> Bool {
            abs(a.minX - b.minX) <= tol && abs(a.minY - b.minY) <= tol
                && abs(a.width - b.width) <= tol && abs(a.height - b.height) <= tol
        }

        print("== widgettest ==")
        guard let screen = NSScreen.main else {
            print("no display available — skipping (run on a Mac with a screen).")
            exit(0)
        }
        let vf = screen.visibleFrame

        let suiteName = "houdini.widgettest"
        let suite = UserDefaults(suiteName: suiteName)!
        suite.removePersistentDomain(forName: suiteName)

        let settings = AppSettings(defaults: UserDefaults(suiteName: "houdini.widgettest.settings")!)
        settings.showDesktopWidget = true
        let session = PreviewData.session(settings: settings)
        func makeController() -> DesktopWidgetController {
            DesktopWidgetController(
                model: UsageModel(previewResult: .success(PreviewData.sampleMetrics())),
                session: session, settings: settings, defaults: suite)
        }

        // 1. First show → deterministic placement on a visible screen.
        let c1 = makeController(); c1.show()
        check("panel shows with a frame", c1.currentFrame != nil)
        if let f = c1.currentFrame {
            check("default placement lands on a visible screen",
                  NSScreen.screens.contains { $0.frame.intersects(f) })
        }
        if let lim = c1.contentLimits {
            check("min content size is card-min + shadow margin (252×182)",
                  lim.min == NSSize(width: 252, height: 182))
            check("max content size is card-max + shadow margin (512×392)",
                  lim.max == NSSize(width: 512, height: 392))
        }

        // 2. Drag → persists frame + displayID.
        let target = NSRect(x: vf.minX + 60, y: vf.minY + 80, width: 312, height: 232)
        c1.moveForTesting(to: target)
        let savedStr = suite.string(forKey: "houdini.widget.frame")
        check("frame persisted to UserDefaults after move", savedStr != nil)
        if let s = savedStr { check("persisted frame matches the move", approx(NSRectFromString(s), target)) }
        check("displayID persisted after move", suite.integer(forKey: "houdini.widget.displayID") != 0)
        c1.hide()

        // 3. A fresh controller restores the saved frame.
        let c2 = makeController(); c2.show()
        if let f = c2.currentFrame { check("new controller restores the saved frame", approx(f, target)) }
        else { check("restored frame present", false) }
        c2.hide()

        // 4. An off-screen saved frame (e.g. a monitor that vanished) is clamped back.
        let offscreen = NSRect(x: vf.maxX + 5000, y: vf.maxY + 5000, width: 312, height: 232)
        suite.set(NSStringFromRect(offscreen), forKey: "houdini.widget.frame")
        suite.set(0, forKey: "houdini.widget.displayID") // simulate the display being gone
        let c3 = makeController(); c3.show()
        if let f = c3.currentFrame {
            check("off-screen frame is clamped back onto a visible screen",
                  NSScreen.screens.contains { $0.visibleFrame.intersects(f) })
        } else { check("clamped frame present", false) }
        c3.hide()

        // 5. Regression: hidden widget whose monitor vanishes must be pulled back
        //    on-screen by a screen-change and by the next show() (was a QA finding).
        let c4 = makeController(); c4.show()
        c4.moveForTesting(to: NSRect(x: vf.minX + 40, y: vf.minY + 40, width: 312, height: 232))
        c4.hide()
        c4.moveForTesting(to: NSRect(x: vf.maxX + 4000, y: vf.maxY + 4000, width: 312, height: 232))
        c4.simulateScreenChangeForTesting()
        if let f = c4.currentFrame {
            check("hidden widget recovers on-screen after a screen change",
                  NSScreen.screens.contains { $0.visibleFrame.intersects(f) })
        } else { check("recovered frame present", false) }
        c4.show()
        if let f = c4.currentFrame {
            check("re-shown widget lands on a visible screen",
                  NSScreen.screens.contains { $0.visibleFrame.intersects(f) })
        } else { check("re-shown frame present", false) }
        c4.hide()

        suite.removePersistentDomain(forName: suiteName)
        print("widgettest: \(pass) passed, \(fail) failed")
        exit(fail == 0 ? 0 : 1)
    }
}
