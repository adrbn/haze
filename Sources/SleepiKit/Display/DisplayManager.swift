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
        let backing: NSImageView
    }

    private var entries: [ScreenEntry] = []
    private var currentItem: ContentItem?
    private var fpsCap: Int = 0
    private var muted = true
    private var rendering = true
    private var lastScreenConfig: [CGRect] = []
    private var pendingRebuild: DispatchWorkItem?
    /// A static still of the current wallpaper, shown *behind* the Metal view.
    /// macOS can't snapshot a Metal layer for Space transitions / Mission Control
    /// (it renders black there), but it does snapshot ordinary image layers — so
    /// this poster shows through the non-opaque Metal view exactly when the live
    /// frame can't be captured, instead of black.
    private var fallbackImageURL: URL?

    public init() {
        NotificationCenter.default.addObserver(
            self, selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)

        // The macOS desktop-picture window sits at the same level as ours and can
        // be raised above it (e.g. when the Wallpaper settings pane opens, after a
        // Space switch, or on wake), which makes our live wallpaper "disappear"
        // behind the system one. Re-assert our windows to the front on those
        // events so the live wallpaper stays visible.
        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(self, selector: #selector(reassertWindows),
                       name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        ws.addObserver(self, selector: #selector(reassertWindows),
                       name: NSWorkspace.didWakeNotification, object: nil)
        ws.addObserver(self, selector: #selector(reassertWindows),
                       name: NSWorkspace.didActivateApplicationNotification, object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    public var hasContent: Bool { currentItem != nil }

    /// Replace the displayed content on every screen.
    public func apply(item: ContentItem, fpsCap: Int, muted: Bool = true) {
        currentItem = item
        self.fpsCap = fpsCap
        self.muted = muted
        rebuild()
    }

    /// Update the FPS cap in place — no teardown, so video keeps playing.
    public func setFPSCap(_ cap: Int) {
        guard fpsCap != cap else { return }
        fpsCap = cap
        for entry in entries { entry.renderer.setFPSCap(cap) }
    }

    /// Push a config change to the live renderers in place (no rebuild) — used
    /// to tweak the currently-playing wallpaper in real time.
    public func liveUpdate(_ item: ContentItem) {
        guard currentItem?.id == item.id else { return }
        currentItem = item
        for entry in entries { entry.renderer.liveUpdate(item) }
    }

    /// Pause/resume all renderers without tearing down the windows.
    public func setRendering(_ on: Bool) {
        guard rendering != on else { return }
        rendering = on
        for entry in entries {
            if on {
                entry.renderer.resume()
                entry.renderer.redraw()   // show the revealed frame immediately
            } else {
                entry.renderer.pause()
            }
        }
        Log.display.debug("rendering set to \(on, privacy: .public)")
    }

    public func clear() {
        teardown()
        currentItem = nil
    }

    /// Set the static poster shown behind the live Metal view (so Space
    /// transitions / Mission Control show it instead of black).
    public func setFallbackImage(_ url: URL?) {
        fallbackImageURL = url
        let image = url.flatMap { NSImage(contentsOf: $0) }
        for entry in entries { entry.backing.image = image }
    }

    /// Re-pin every wallpaper window to the desktop level and bring it to the
    /// front of that level, so the system desktop picture can't sit on top.
    @objc public func reassertWindows() {
        guard !entries.isEmpty else { return }
        let level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
        for entry in entries {
            entry.window.level = level
            entry.window.orderFrontRegardless()
            if rendering { entry.renderer.redraw() }   // refresh in case it went stale/black
        }
    }

    // MARK: Internals

    private func rebuild() {
        teardown()
        guard let item = currentItem else { return }
        for screen in NSScreen.screens {
            guard let renderer = RendererFactory.makeRenderer(for: item, fpsCap: fpsCap, muted: muted) else {
                Log.display.error("No renderer for item \(item.name, privacy: .public)")
                continue
            }
            let window = WallpaperWindow(screen: screen)

            // Container: poster image behind, live Metal view on top.
            let container = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
            container.wantsLayer = true
            container.autoresizingMask = [.width, .height]

            let backing = NSImageView(frame: container.bounds)
            backing.imageScaling = .scaleAxesIndependently
            backing.autoresizingMask = [.width, .height]
            backing.image = fallbackImageURL.flatMap { NSImage(contentsOf: $0) }
            container.addSubview(backing)

            let contentView = renderer.view
            contentView.frame = container.bounds
            contentView.autoresizingMask = [.width, .height]
            container.addSubview(contentView)

            window.contentView = container
            window.orderFrontRegardless()
            renderer.start()
            if !rendering { renderer.pause() }
            entries.append(ScreenEntry(window: window, renderer: renderer, backing: backing))
        }
        lastScreenConfig = NSScreen.screens.map(\.frame)
        Log.display.info("Applied '\(item.name, privacy: .public)' to \(self.entries.count, privacy: .public) screen(s)")

        // Guarantee an initial frame is presented, even if the renderer was
        // created while paused (launched behind other windows / occluded). Run
        // on the next runloop turns so the view is laid out and the drawable is
        // ready — otherwise a paused wallpaper stays blank until interaction.
        let created = entries
        DispatchQueue.main.async { created.forEach { $0.renderer.redraw() } }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { created.forEach { $0.renderer.redraw() } }
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
