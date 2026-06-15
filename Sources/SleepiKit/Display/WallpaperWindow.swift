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

        // Non-opaque with a clear background: the live Metal content is opaque so
        // normal viewing is unaffected, but Mission Control / the Spaces switcher
        // can't snapshot a Metal drawable and would otherwise show this window's
        // black backing. Clear lets the matching system "poster" picture show
        // through there instead of black.
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
        // No `.stationary`: it pins the window to its origin Space and stops
        // `.canJoinAllSpaces` from extending the (snapshot-able) poster backing to
        // other Spaces — leaving them black in Mission Control. Without it the
        // window genuinely joins every Space, so each Space's preview can show the
        // poster instead of black.
        collectionBehavior = [.canJoinAllSpaces, .ignoresCycle]

        setFrame(screen.frame, display: false)
    }

    public override var canBecomeKey: Bool { false }
    public override var canBecomeMain: Bool { false }
}
