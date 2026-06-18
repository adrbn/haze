import AppKit

/// A borderless window pinned at desktop level on a single screen: behind the
/// icons, on every Space, click-through, and never key/main. This is the canvas
/// the live wallpaper renders into.
public final class WallpaperWindow: NSWindow {
    public init(screen: NSScreen) {
        super.init(contentRect: screen.frame,
                   styleMask: [.borderless],
                   backing: .buffered,
                   defer: false)

        // Non-opaque with a clear background: the live Metal/video content is opaque
        // so normal viewing is unchanged, but during Space-switch swipes (and Mission
        // Control) macOS can't capture that layer — so instead of a black backing it
        // shows the snapshot-able poster placed behind it (see DisplayManager).
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        isMovable = false
        isMovableByWindowBackground = false
        canHide = false
        isExcludedFromWindowsMenu = true
        animationBehavior = .none

        // Sit at the desktop-picture level → below Finder icons, above nothing.
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
        collectionBehavior = Self.desktopBehavior

        setFrame(screen.frame, display: false)
    }

    /// The full set production wallpaper apps use. Crucially `.fullScreenAuxiliary`:
    /// without it the wallpaper vanishes on / during swipes to-from full-screen
    /// app Spaces (its absence is why the live wallpaper disappeared during swipes
    /// until re-selected). `.stationary` still keeps it out of Mission Control
    /// snapshots, so MC shows the system poster, not a black capture.
    static let desktopBehavior: NSWindow.CollectionBehavior =
        [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]

    /// Re-assert Space membership after the window server settles (collectionBehavior
    /// set only in `init()` may not take on every Space right at launch).
    public func reaffirmDesktopPresence() {
        collectionBehavior = Self.desktopBehavior
        orderFrontRegardless()
    }

    public override var canBecomeKey: Bool { false }
    public override var canBecomeMain: Bool { false }
}
