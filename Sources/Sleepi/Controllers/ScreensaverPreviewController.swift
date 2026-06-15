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

            // Drive via timer (robust), like the screensaver host.
            renderer.setExternallyDriven(true)
            renderer.start()
            renderer.redraw()

            windows.append(window)
            renderers.append(renderer)
        }

        guard !windows.isEmpty else { return }
        NSApp.activate(ignoringOtherApps: true)
        startedAt = CACurrentMediaTime()
        NSCursor.setHiddenUntilMouseMoves(true)

        let driveTimer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            self?.renderers.forEach { $0.tick() }
        }
        RunLoop.main.add(driveTimer, forMode: .common)
        timer = driveTimer

        let mask: NSEvent.EventTypeMask = [
            .mouseMoved, .leftMouseDown, .rightMouseDown, .otherMouseDown,
            .keyDown, .scrollWheel, .flagsChanged,
        ]
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            let wasRunning = self?.isRunning == true
            self?.dismissIfPastGrace()
            return wasRunning ? nil : event   // swallow events (incl. the dismiss trigger) during preview
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in
            self?.dismissIfPastGrace()
        }
    }

    /// Ignore events for a short grace period so the click/movement that opened
    /// the preview doesn't instantly dismiss it.
    private func dismissIfPastGrace() {
        guard CACurrentMediaTime() - startedAt > 0.6 else { return }
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
