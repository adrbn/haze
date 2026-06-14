import CoreGraphics

/// Pure geometry for occlusion detection — kept separate from window-server
/// access so it can be unit tested. All rects are in the same coordinate space.
public enum ScreenCoverage {
    /// `true` only when *every* screen is fully covered by at least one window.
    /// We pause rendering only when nothing is visible anywhere.
    public static func allScreensCovered(screens: [CGRect],
                                         windows: [CGRect],
                                         tolerance: CGFloat = 2) -> Bool {
        guard !screens.isEmpty else { return false }
        return screens.allSatisfy { screen in
            windows.contains { covers(window: $0, screen: screen, tolerance: tolerance) }
        }
    }

    /// A window covers a screen if (slightly expanded for rounding) it fully
    /// contains the screen rect.
    static func covers(window: CGRect, screen: CGRect, tolerance: CGFloat) -> Bool {
        window.insetBy(dx: -tolerance, dy: -tolerance).contains(screen)
    }
}
