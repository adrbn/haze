import AppKit
import QuartzCore
import SleepiKit

/// Runs the screensaver content full-screen, in-app, exactly as it would appear
/// — same renderer, same chosen content — dismissed by any mouse move / key /
/// click (like a real screensaver). Doesn't depend on the saver being installed
/// or selected in System Settings.
@MainActor
final class ScreensaverPreviewController {
    static let shared = ScreensaverPreviewController()

    private var windows: [NSWindow] = []
    private var renderers: [WallpaperRenderer] = []
    private var timer: Timer?
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var startedAt: CFTimeInterval = 0
    private var startLocation: NSPoint = .zero

    /// Ignore all input briefly so the click that opened the preview (and any
    /// settling cursor jitter) doesn't instantly dismiss it.
    private let dismissGrace: CFTimeInterval = 1.0
    /// A mouse *move* must travel at least this far to dismiss — tiny jitter from
    /// resting a hand on the trackpad shouldn't kill the preview. Clicks, keys
    /// and scrolls still dismiss immediately (after the grace period).
    private let moveThreshold: CGFloat = 45

    private init() {}

    var isRunning: Bool { !windows.isEmpty }

    func start() {
        stop()
        let content = SleepiKit.screensaverContent()

        for screen in NSScreen.screens {
            guard let renderer = RendererFactory.makeRenderer(for: content.item, fpsCap: content.fpsCap) else { continue }
            let window = NSWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.level = .screenSaver
            window.isOpaque = true
            window.backgroundColor = .black
            window.hasShadow = false
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
            window.acceptsMouseMovedEvents = true
            let view = renderer.view
            view.autoresizingMask = [.width, .height]
            window.contentView = view
            window.setFrame(screen.frame, display: true)
            window.orderFrontRegardless()

            // Self-drive via the MTKView's display link (smooth) — unlike the
            // sandboxed .saver host, a normal app window's display link fires, so
            // a 30fps Timer here only adds jitter/lag.
            renderer.start()
            renderer.redraw()

            windows.append(window)
            renderers.append(renderer)
        }

        guard !windows.isEmpty else { return }
        NSApp.activate(ignoringOtherApps: true)
        startedAt = CACurrentMediaTime()
        startLocation = NSEvent.mouseLocation
        NSCursor.setHiddenUntilMouseMoves(true)

        let mask: NSEvent.EventTypeMask = [
            .mouseMoved, .leftMouseDown, .rightMouseDown, .otherMouseDown,
            .keyDown, .scrollWheel, .flagsChanged,
        ]
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            let wasRunning = self?.isRunning == true
            self?.handleDismissEvent(event)
            return wasRunning ? nil : event   // swallow events (incl. the dismiss trigger) during preview
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handleDismissEvent(event)
        }
    }

    /// Decide whether an input event should dismiss the preview: never during the
    /// grace period; for a mouse *move*, only once the cursor has travelled a
    /// meaningful distance; for clicks/keys/scrolls, immediately after grace.
    private func handleDismissEvent(_ event: NSEvent) {
        guard CACurrentMediaTime() - startedAt > dismissGrace else { return }
        if event.type == .mouseMoved {
            let loc = NSEvent.mouseLocation
            let dist = hypot(loc.x - startLocation.x, loc.y - startLocation.y)
            guard dist > moveThreshold else { return }
        }
        stop()
    }

    func stop() {
        timer?.invalidate(); timer = nil
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        localMonitor = nil
        globalMonitor = nil
        renderers.forEach { $0.stop() }
        renderers.removeAll()
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
    }
}
