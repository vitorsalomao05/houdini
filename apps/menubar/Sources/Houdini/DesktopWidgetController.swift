import AppKit
import SwiftUI
import Combine

/// Hosts `DesktopWidgetView` in a desktop-level `NSPanel`. The panel is a
/// non-activating, borderless, resizable squircle that behaves like desktop
/// furniture: it sits behind ordinary app windows, never steals focus, is dragged
/// by its background, and remembers where it was (frame + which display) across
/// relaunch and reboot.
///
/// Geometry contract (the visible *card*, per spec): default 280×200, min
/// 220×150, max 480×360. The window is the card plus a transparent margin so the
/// drop shadow has room to render, so the window's min/max are the card limits +
/// `2 × shadowInset`.
@MainActor
final class DesktopWidgetController: NSObject, NSWindowDelegate {
    private let model: UsageModel
    private let session: SubscriptionSession
    private let settings: AppSettings
    /// Where the frame + displayID are persisted. Injectable so `--widgettest` can
    /// exercise save/restore against an isolated suite.
    private let defaults: UserDefaults
    private var panel: NSPanel?
    private var cancellables = Set<AnyCancellable>()

    // Card size limits (the visible squircle).
    private static let cardDefault = NSSize(width: 280, height: 200)
    private static let cardMin = NSSize(width: 220, height: 150)
    private static let cardMax = NSSize(width: 480, height: 360)
    /// Transparent shadow margin baked into the SwiftUI card; must match
    /// `DesktopWidgetView.shadowInset`.
    private static let shadowInset: CGFloat = 16

    private enum Keys {
        static let frame = "houdini.widget.frame"
        static let displayID = "houdini.widget.displayID"
    }

    init(model: UsageModel, session: SubscriptionSession, settings: AppSettings,
         defaults: UserDefaults = .standard) {
        self.model = model
        self.session = session
        self.settings = settings
        self.defaults = defaults
        super.init()

        // Mirror the Settings toggle live (show/hide without a relaunch).
        settings.$showDesktopWidget
            .removeDuplicates()
            .sink { [weak self] show in self?.setVisible(show) }
            .store(in: &cancellables)

        // If a display is unplugged or the resolution changes, pull the widget back
        // onto a visible screen.
        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil
        )
    }

    // MARK: - Visibility

    func setVisible(_ visible: Bool) {
        if visible { show() } else { hide() }
    }

    func show() {
        let panel = panel ?? makePanel()
        self.panel = panel
        // A display may have been unplugged while the panel was hidden (and
        // `screensChanged` corrects a hidden panel too, but guard against any gap):
        // re-clamp onto a visible screen before showing so it never appears off-screen.
        recoverOntoVisibleScreen()
        panel.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    // MARK: - Panel construction

    private func makePanel() -> NSPanel {
        let windowMin = NSSize(width: Self.cardMin.width + Self.shadowInset * 2,
                               height: Self.cardMin.height + Self.shadowInset * 2)
        let windowMax = NSSize(width: Self.cardMax.width + Self.shadowInset * 2,
                               height: Self.cardMax.height + Self.shadowInset * 2)

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: NSSize(
                width: Self.cardDefault.width + Self.shadowInset * 2,
                height: Self.cardDefault.height + Self.shadowInset * 2)),
            styleMask: [.nonactivatingPanel, .titled, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        // Desktop-widget chrome: borderless look, draggable background, no focus theft.
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false                 // the card draws its own shadows
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = false           // stay visible when app deactivates
        panel.becomesKeyOnlyIfNeeded = true
        panel.animationBehavior = .none

        // Sit above the wallpaper/icons but behind normal app windows; ride along
        // to every Space and stay out of Cmd-` cycling and Exposé shuffling.
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]

        panel.contentMinSize = windowMin
        panel.contentMaxSize = windowMax

        let host = NSHostingView(rootView:
            DesktopWidgetView(model: model, session: session)
                .environment(\.widgetRenderMode, .live)
                .tint(.brand)
        )
        host.autoresizingMask = [.width, .height]
        panel.contentView = host
        panel.delegate = self

        restoreFrame(into: panel)
        return panel
    }

    // MARK: - Persistence

    private func restoreFrame(into panel: NSPanel) {
        if let saved = defaults.string(forKey: Keys.frame) {
            let rect = NSRectFromString(saved)
            if rect.width > 0, rect.height > 0 {
                let targetScreen = savedScreen() ?? NSScreen.main
                if let screen = targetScreen, rect.intersects(screen.frame) {
                    panel.setFrame(clamp(rect, into: screen.visibleFrame), display: false)
                    return
                }
                // Saved display is gone → reposition gracefully on the main screen.
                if let main = NSScreen.main {
                    panel.setFrame(clamp(rect, into: main.visibleFrame), display: false)
                    return
                }
            }
        }
        placeDefault(panel)
    }

    /// First-run placement: tucked into the top-right of the main screen.
    private func placeDefault(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let vf = screen.visibleFrame
        let size = panel.frame.size
        let margin: CGFloat = 24
        let origin = NSPoint(x: vf.maxX - size.width - margin,
                             y: vf.maxY - size.height - margin)
        panel.setFrame(NSRect(origin: origin, size: size), display: false)
    }

    private func persistFrame() {
        guard let panel else { return }
        defaults.set(NSStringFromRect(panel.frame), forKey: Keys.frame)
        // Record the display that actually holds most of the frame, not whatever
        // `panel.screen` reports at this instant (which can be transient/nil mid
        // screen-change), so the saved frame and displayID never disagree.
        if let id = bestScreen(for: panel.frame)?.displayID {
            defaults.set(Int(id), forKey: Keys.displayID)
        }
    }

    private func savedScreen() -> NSScreen? {
        let id = defaults.integer(forKey: Keys.displayID)
        guard id != 0 else { return nil }
        return NSScreen.screens.first { $0.displayID == CGDirectDisplayID(id) }
    }

    /// Keep a frame fully inside a screen's usable area: shrink to fit (respecting
    /// the window minimum) then nudge the origin so nothing spills off-screen.
    private func clamp(_ rect: NSRect, into area: NSRect) -> NSRect {
        var r = rect
        r.size.width = min(r.size.width, area.width)
        r.size.height = min(r.size.height, area.height)
        r.origin.x = min(max(r.origin.x, area.minX), area.maxX - r.size.width)
        r.origin.y = min(max(r.origin.y, area.minY), area.maxY - r.size.height)
        return r
    }

    // MARK: - Window delegate (persist + multi-monitor recovery)

    func windowDidMove(_ notification: Notification) { persistFrame() }
    func windowDidEndLiveResize(_ notification: Notification) { persistFrame() }

    @objc private func screensChanged() {
        // Correct a hidden panel too: if its monitor is unplugged while the widget
        // is toggled off, a later `show()` must not surface it off-screen.
        recoverOntoVisibleScreen()
    }

    /// Pull the panel fully onto a currently-visible screen. No-op if it already
    /// fits. Falls back to the main screen if its frame lands on a gone monitor.
    private func recoverOntoVisibleScreen() {
        guard let panel else { return }
        guard let screen = bestScreen(for: panel.frame) else { return }
        let clamped = clamp(panel.frame, into: screen.visibleFrame)
        if clamped != panel.frame {
            panel.setFrame(clamped, display: panel.isVisible)
            persistFrame()
        }
    }

    /// The live screen holding the largest area of `frame`; the main screen if the
    /// frame overlaps none (e.g. its monitor was removed).
    private func bestScreen(for frame: NSRect) -> NSScreen? {
        let overlapping = NSScreen.screens.filter { $0.frame.intersects(frame) }
        let best = overlapping.max { a, b in
            a.frame.intersection(frame).area < b.frame.intersection(frame).area
        }
        return best ?? NSScreen.main
    }

    // MARK: - Testing hooks (--widgettest)

    /// The live panel frame (nil before `show()`), for the headless persistence test.
    var currentFrame: NSRect? { panel?.frame }
    var contentLimits: (min: NSSize, max: NSSize)? {
        panel.map { ($0.contentMinSize, $0.contentMaxSize) }
    }

    /// Move the panel and run the same persistence path a real drag triggers.
    func moveForTesting(to frame: NSRect) {
        panel?.setFrame(frame, display: false)
        windowDidMove(Notification(name: NSWindow.didMoveNotification))
    }

    /// Drive the display-change recovery path (a monitor being unplugged).
    func simulateScreenChangeForTesting() { screensChanged() }
}

private extension NSRect {
    /// Area in points — used to pick the screen holding the most of a frame.
    var area: CGFloat { width * height }
}

extension NSScreen {
    /// The `CGDirectDisplayID` backing this screen, used to remember which monitor
    /// the widget lived on across relaunch/reboot.
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)
            .map { CGDirectDisplayID($0.uint32Value) }
    }
}
