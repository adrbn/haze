import AppKit

/// Owns one `WallpaperWindow` + renderer per screen and keeps them in sync with
/// display configuration changes. Reports aggregate occlusion so the power
/// policy can pause rendering when the desktop is fully covered.
public final class DisplayManager {
    private struct ScreenEntry {
        let window: WallpaperWindow
        let renderer: WallpaperRenderer
    }

    private var entries: [ScreenEntry] = []
    private var currentItem: ContentItem?
    private var fpsCap: Int = 0
    private var rendering = true

    /// Called (on main) with `true` when every wallpaper window is occluded.
    public var onOcclusionChange: ((Bool) -> Void)?

    public init() {
        NotificationCenter.default.addObserver(
            self, selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(occlusionChanged),
            name: NSWindow.didChangeOcclusionStateNotification, object: nil)
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    public var hasContent: Bool { currentItem != nil }

    /// Replace the displayed content on every screen.
    public func apply(item: ContentItem, fpsCap: Int) {
        currentItem = item
        self.fpsCap = fpsCap
        rebuild()
    }

    public func setFPSCap(_ cap: Int) {
        guard fpsCap != cap else { return }
        fpsCap = cap
        // Re-create gradient renderers (others ignore the cap) cheaply by rebuild.
        rebuild()
    }

    /// Pause/resume all renderers without tearing down the windows.
    public func setRendering(_ on: Bool) {
        guard rendering != on else { return }
        rendering = on
        for entry in entries { on ? entry.renderer.resume() : entry.renderer.pause() }
        Log.display.debug("rendering set to \(on, privacy: .public)")
    }

    public func clear() { teardown() }

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
            contentView.frame = window.frame
            contentView.autoresizingMask = [.width, .height]
            window.contentView = contentView
            window.orderFrontRegardless()
            renderer.start()
            if !rendering { renderer.pause() }
            entries.append(ScreenEntry(window: window, renderer: renderer))
        }
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

    @objc private func screenParametersChanged() {
        Log.display.info("Screen parameters changed — rebuilding windows")
        rebuild()
    }

    @objc private func occlusionChanged(_ note: Notification) {
        guard let changed = note.object as? NSWindow,
              entries.contains(where: { $0.window === changed }) else { return }
        let allOccluded = !entries.isEmpty && entries.allSatisfy { !$0.window.occlusionState.contains(.visible) }
        onOcclusionChange?(allOccluded)
    }
}
