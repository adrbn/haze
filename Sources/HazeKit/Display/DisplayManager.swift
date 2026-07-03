import AppKit

/// Owns one `WallpaperWindow` + renderer per screen and keeps them in sync with
/// display configuration changes. Occlusion (whether the desktop is covered) is
/// detected separately by `OcclusionDetector`, because `NSWindow.occlusionState`
/// is unreliable for desktop-level windows.
@MainActor
public final class DisplayManager {
    private struct ScreenEntry {
        let screen: NSScreen
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
    private var pendingSpaceRepair: DispatchWorkItem?
    private var repairPolicy = SpaceRepairPolicy()
    /// Bumped on every teardown/recreation; in-flight repair checks and
    /// post-recreation verifications compare it and no-op when stale, so async
    /// work scheduled against a previous window generation can never touch (or
    /// wrongly judge) windows it didn't create.
    private var repairGeneration = 0
    /// A static still of the current wallpaper, shown *behind* the (non-opaque)
    /// Metal/video view. macOS can't snapshot a Metal/sample-buffer layer for
    /// Space-switch swipes or Mission Control (black there), but it does snapshot
    /// ordinary image layers — so this poster shows through exactly when the live
    /// frame can't be captured, instead of a black gap.
    private var fallbackImageURL: URL?

    public init() {
        NotificationCenter.default.addObserver(
            self, selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
        // Re-assert window Space membership on every Space switch — the live
        // wallpaper was otherwise missing during swipes (esp. to/from full-screen
        // app Spaces) until re-selected. Safe with `.stationary`: the window stays
        // out of Mission Control snapshots, so this won't reintroduce MC-black.
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(reaffirmWindows),
            name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
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

    /// Re-assert every wallpaper window's Space membership — on launch (window
    /// server not settled), on app open, and on every Space switch. Re-asserting
    /// collectionBehavior is not enough when the active Space didn't exist at
    /// window-creation time (`.canJoinAllSpaces` binds only to then-existing
    /// Spaces; full-screen-app Spaces are created lazily) — such a window must be
    /// recreated, exactly what a manual re-pick of the wallpaper does. So this
    /// also schedules a debounced membership check that repairs only the affected
    /// screen(s), guarded by `SpaceRepairPolicy` against rebuild loops.
    @objc public func reaffirmWindows() {
        for entry in entries { entry.window.reaffirmDesktopPresence() }
        scheduleSpaceRepair()
    }

    private func scheduleSpaceRepair() {
        guard currentItem != nil else { return }
        pendingSpaceRepair?.cancel()
        let generation = repairGeneration
        let work = DispatchWorkItem { [weak self] in
            guard let self, generation == self.repairGeneration else { return }
            self.repairSpaceMembership()
        }
        pendingSpaceRepair = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: work)
    }

    private func repairSpaceMembership() {
        guard currentItem != nil else { return }
        // Reversed so a failed recreation (entry removed) can't shift the
        // indices of entries not yet visited.
        for index in entries.indices.reversed() {
            let entry = entries[index]
            let display = Self.displayID(of: entry.screen)
            let onSpace = entry.window.isOnActiveSpace
            Log.display.debug("space check: display \(display, privacy: .public) onActiveSpace=\(onSpace, privacy: .public)")
            guard repairPolicy.verdict(display: display, isOnActiveSpace: onSpace) == .repair else { continue }
            Log.display.info("wallpaper window off-Space on display \(display, privacy: .public) — recreating it (auto re-pick)")
            recreateEntry(at: index)
        }
    }

    /// Tear down and recreate a single screen's window + renderer — the scoped
    /// equivalent of the manual wallpaper re-pick that reliably restores Space
    /// membership. If the fresh window still isn't on the active Space once
    /// settled (display is showing a full-screen Space that refuses desktop
    /// windows), suppress further repairs for that display until it recovers.
    private func recreateEntry(at index: Int) {
        guard let item = currentItem, entries.indices.contains(index) else { return }
        let old = entries[index]
        let display = Self.displayID(of: old.screen)
        // Resolve the screen freshly — NSScreen instances can go stale.
        guard let screen = NSScreen.screens.first(where: { Self.displayID(of: $0) == display }) else { return }

        old.renderer.stop()
        old.window.contentView = nil
        old.window.orderOut(nil)
        guard let fresh = makeEntry(for: screen, item: item) else {
            entries.remove(at: index)
            return
        }
        entries[index] = fresh
        scheduleInitialRedraws(for: [fresh])

        // Tie the verification to THIS recreation: any later teardown/recreation
        // bumps the generation and this closure no-ops instead of judging (and
        // possibly suppressing) a window it didn't create.
        repairGeneration += 1
        let generation = repairGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self, generation == self.repairGeneration else { return }
            guard let current = self.entries.first(where: { Self.displayID(of: $0.screen) == display }),
                  !current.window.isOnActiveSpace else { return }
            self.repairPolicy.repairDidFail(display: display)
            Log.display.info("display \(display, privacy: .public) still off-Space after recreate — suppressing repairs until it recovers")
        }
    }

    private static func displayID(of screen: NSScreen) -> UInt32 {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }

    /// Set the static poster shown behind the live view (so Space swipes / Mission
    /// Control show a still gradient instead of black).
    public func setFallbackImage(_ url: URL?) {
        fallbackImageURL = url
        let image = url.flatMap { NSImage(contentsOf: $0) }
        for entry in entries { entry.backing.image = image }
    }

    // MARK: Internals

    private func rebuild() {
        teardown()
        guard let item = currentItem else { return }
        repairPolicy.reset()
        for screen in NSScreen.screens {
            if let entry = makeEntry(for: screen, item: item) { entries.append(entry) }
        }
        lastScreenConfig = NSScreen.screens.map(\.frame)
        Log.display.info("Applied '\(item.name, privacy: .public)' to \(self.entries.count, privacy: .public) screen(s)")
        scheduleInitialRedraws(for: entries)
    }

    private func makeEntry(for screen: NSScreen, item: ContentItem) -> ScreenEntry? {
        guard let renderer = RendererFactory.makeRenderer(for: item, fpsCap: fpsCap, muted: muted) else {
            Log.display.error("No renderer for item \(item.name, privacy: .public)")
            return nil
        }
        let window = WallpaperWindow(screen: screen)

        // Container: snapshot-able poster behind, live (non-opaque) view on top.
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
        return ScreenEntry(screen: screen, window: window, renderer: renderer, backing: backing)
    }

    // Guarantee an initial frame is presented, even if the renderer was
    // created while paused (launched behind other windows / occluded). Run
    // on the next runloop turns so the view is laid out and the drawable is
    // ready — otherwise a paused wallpaper stays blank until interaction.
    private func scheduleInitialRedraws(for created: [ScreenEntry]) {
        DispatchQueue.main.async { created.forEach { $0.renderer.redraw() } }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { created.forEach { $0.renderer.redraw() } }
    }

    private func teardown() {
        repairGeneration += 1
        pendingSpaceRepair?.cancel()
        pendingSpaceRepair = nil
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
