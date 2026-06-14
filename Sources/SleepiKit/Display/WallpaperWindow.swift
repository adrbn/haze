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

        isOpaque = true
        backgroundColor = .black
        hasShadow = false
        ignoresMouseEvents = true
        isMovable = false
        isMovableByWindowBackground = false
        canHide = false
        isExcludedFromWindowsMenu = true
        animationBehavior = .none

        // Sit at the desktop-picture level → below Finder icons, above nothing.
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]

        setFrame(screen.frame, display: false)
    }

    public override var canBecomeKey: Bool { false }
    public override var canBecomeMain: Bool { false }
}
