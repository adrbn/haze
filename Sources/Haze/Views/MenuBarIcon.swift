import AppKit

/// The menu-bar glyph, drawn in code as a template image.
///
/// The mark is Haze's orb sinking into layered mist: one path filled with the
/// even-odd rule, so where a streak crosses the orb it punches through it, and
/// where it runs past the orb it reads as a drifting band. Template image →
/// AppKit tints it for light/dark, tinted menu bars and Reduce Transparency, so
/// there is no asset to keep in sync with the system appearance.
enum MenuBarIcon {
    /// Menu-bar glyphs are laid out on an 18pt square; AppKit scales for Retina.
    private static let side: CGFloat = 18

    static let image: NSImage = {
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { _ in
            draw()
            return true
        }
        // Template = "tint me": follows the menu-bar appearance instead of
        // shipping a light and a dark asset.
        image.isTemplate = true
        return image
    }()

    /// Geometry in the 18×18 glyph box, tuned by eye at 2× and 3× (the sizes a
    /// Retina menu bar actually renders). The orb sits high; the three streaks
    /// narrow as they go down and each is offset a little further right, so the
    /// mist reads as receding depth rather than a struck-through circle.
    private static func draw() {
        let orbCenter = NSPoint(x: 9, y: 10.6)
        let orbRadius: CGFloat = 5.0
        let streakHeight: CGFloat = 1.2

        let path = NSBezierPath()
        path.appendOval(in: NSRect(x: orbCenter.x - orbRadius, y: orbCenter.y - orbRadius,
                                   width: orbRadius * 2, height: orbRadius * 2))
        path.append(streak(centerY: 9.0, from: 1.3, to: 16.9, height: streakHeight))
        path.append(streak(centerY: 6.4, from: 2.9, to: 15.7, height: streakHeight))
        path.append(streak(centerY: 3.9, from: 4.9, to: 14.1, height: streakHeight))

        // Even-odd: overlaps cancel, so each streak cuts a gap through the orb
        // while its overhang stays solid.
        path.windingRule = .evenOdd
        NSColor.black.setFill()
        path.fill()
    }

    private static func streak(centerY: CGFloat, from minX: CGFloat, to maxX: CGFloat,
                               height: CGFloat) -> NSBezierPath {
        let rect = NSRect(x: minX, y: centerY - height / 2, width: maxX - minX, height: height)
        return NSBezierPath(roundedRect: rect, xRadius: height / 2, yRadius: height / 2)
    }
}
