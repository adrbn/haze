import AppKit

/// Owns one `WallpaperWindow` + renderer per screen and keeps them in sync with
/// display configuration changes. Occlusion (whether the desktop is covered) is
/// detected separately by `OcclusionDetector`, because `NSWindow.occlusionState`
/// is unreliable for desktop-level windows.
@MainActor
public final class DisplayManager {
    private struct ScreenEntry {
        let window: WallpaperWindow
        let renderer: WallpaperRenderer
    }

    private var entries: [ScreenEntry] = []
    private var currentItem: ContentItem?
    private var fpsCap: Int = 0
    private var rendering = true
    private var lastScreenConfig: [CGRect] = []
    private var pendingRebuild: DispatchWorkItem?

    public init() {
        NotificationCenter.default.addObserver(
            self, selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    public var hasContent: Bool { currentItem != nil }

    /// Replace the displayed content on every screen.
    public func apply(item: ContentItem, fpsCap: Int) {
        currentItem = item
        self.fpsCap = fpsCap
        rebuild()
    }

    /// Update the FPS cap in place — no teardown, so video keeps playing.
    public func setFPSCap(_ cap: Int) {
        guard fpsCap != cap else { return }
        fpsCap = cap
        for entry in entries { entry.renderer.setFPSCap(cap) }
    }

    /// Pause/resume all renderers without tearing down the windows.
    public func setRendering(_ on: Bool) {
        guard rendering != on else { return }
        rendering = on
        for entry in entries { on ? entry.renderer.resume() : entry.renderer.pause() }
        Log.display.debug("rendering set to \(on, privacy: .public)")
    }

    public func clear() {
        teardown()
        currentItem = nil
    }

    // MARK: Internals

    private func rebuild() {
        teardown()
        guard let item = currentItem else { return }
        for screen in NSScreen.screens {
            guard let renderer = RendererFactory.makeRenderer(for: item, fpsCap: fpsCap) else {
                Log.display.error("No renderer for item \(item.name, privacy: .public)")
                continue
            }
            let window = WallpaperWindow(screen: screen)
            let contentView = renderer.view
            contentView.autoresizingMask = [.width, .height]
            window.contentView = contentView
            window.orderFrontRegardless()
            renderer.start()
            if !rendering { renderer.pause() }
            entries.append(ScreenEntry(window: window, renderer: renderer))
        }
        lastScreenConfig = NSScreen.screens.map(\.frame)
        Log.display.info("Applied '\(item.name, privacy: .public)' to \(self.entries.count, privacy: .public) screen(s)")
    }

    private func teardown() {
        for entry in entries {
            entry.renderer.stop()
            entry.window.contentView = nil
            entry.window.orderOut(nil)
        }
        entries.removeAll()
    }

    /// Display config changes fire for many reasons (resolution, refresh rate,
    /// Night Shift, arrangement). Debounce, and only rebuild if screen geometry
    /// actually changed — otherwise the wallpaper would needlessly restart.
    @objc private func screenParametersChanged() {
        pendingRebuild?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let now = NSScreen.screens.map(\.frame)
            if now != self.lastScreenConfig {
                Log.display.info("Screen geometry changed — rebuilding windows")
                self.rebuild()
            }
        }
        pendingRebuild = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }
}
