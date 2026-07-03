import Foundation

/// Loop-guard for the per-screen "auto re-pick": `.canJoinAllSpaces` only binds
/// a window to Spaces that exist when the window is created, so a Space created
/// later (macOS makes full-screen-app Spaces lazily) never shows the wallpaper —
/// the only reliable rebind is recreating the window. But a display currently
/// showing a full-screen Space may refuse desktop-level windows entirely; blindly
/// recreating on every Space change there would restart the renderer on each
/// swipe, forever. This policy allows one repair attempt per display (with a
/// cooldown), and stands down after a failed attempt until the display reports
/// healthy again.
public struct SpaceRepairPolicy {
    public enum Verdict: Equatable {
        /// Window is on the active Space — nothing to do.
        case healthy
        /// Window is off-Space but repairing is suppressed or cooling down.
        case skip
        /// Recreate this display's window now.
        case repair
    }

    private var suppressed: Set<UInt32> = []
    private var lastAttempt: [UInt32: Date] = [:]
    private let cooldown: TimeInterval

    public init(cooldown: TimeInterval = 3) {
        self.cooldown = cooldown
    }

    public mutating func verdict(display: UInt32, isOnActiveSpace: Bool, now: Date = Date()) -> Verdict {
        if isOnActiveSpace {
            suppressed.remove(display)
            return .healthy
        }
        if suppressed.contains(display) { return .skip }
        if let last = lastAttempt[display], now.timeIntervalSince(last) < cooldown { return .skip }
        lastAttempt[display] = now
        return .repair
    }

    /// The recreated window still isn't on the active Space — the display is
    /// showing a Space that won't host desktop windows. Stop repairing it until
    /// `verdict` sees it healthy again.
    public mutating func repairDidFail(display: UInt32) {
        suppressed.insert(display)
    }

    public mutating func reset() {
        suppressed.removeAll()
        lastAttempt.removeAll()
    }
}
