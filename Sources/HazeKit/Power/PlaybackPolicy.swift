import Foundation

/// Pure decision function: given the current environment + user preferences,
/// should renderers be drawing frames? Kept free of side effects so it can be
/// exhaustively unit-tested.
public struct PlaybackPolicy: Equatable, Sendable {
    // Environment inputs
    public var userPaused: Bool
    public var occluded: Bool
    public var displayAsleep: Bool
    public var systemAsleep: Bool
    public var screenLocked: Bool
    public var screensaverActive: Bool
    public var onBattery: Bool
    public var lowPowerMode: Bool

    // Preference toggles
    public var pauseWhenOccluded: Bool
    public var pauseOnDisplaySleep: Bool
    public var pauseOnBattery: Bool
    public var pauseInLowPowerMode: Bool

    public init(userPaused: Bool = false,
                occluded: Bool = false,
                displayAsleep: Bool = false,
                systemAsleep: Bool = false,
                screenLocked: Bool = false,
                screensaverActive: Bool = false,
                onBattery: Bool = false,
                lowPowerMode: Bool = false,
                pauseWhenOccluded: Bool = true,
                pauseOnDisplaySleep: Bool = true,
                pauseOnBattery: Bool = false,
                pauseInLowPowerMode: Bool = true) {
        self.userPaused = userPaused
        self.occluded = occluded
        self.displayAsleep = displayAsleep
        self.systemAsleep = systemAsleep
        self.screenLocked = screenLocked
        self.screensaverActive = screensaverActive
        self.onBattery = onBattery
        self.lowPowerMode = lowPowerMode
        self.pauseWhenOccluded = pauseWhenOccluded
        self.pauseOnDisplaySleep = pauseOnDisplaySleep
        self.pauseOnBattery = pauseOnBattery
        self.pauseInLowPowerMode = pauseInLowPowerMode
    }

    /// `true` when renderers should actively draw frames.
    public var shouldRender: Bool {
        if userPaused { return false }
        if systemAsleep { return false }
        if screenLocked { return false }
        if screensaverActive { return false }
        if pauseOnDisplaySleep && displayAsleep { return false }
        if pauseWhenOccluded && occluded { return false }
        if pauseOnBattery && onBattery { return false }
        if pauseInLowPowerMode && lowPowerMode { return false }
        return true
    }

    /// Apply the preference toggles from settings, leaving environment as-is.
    public mutating func applyPreferences(_ settings: AppSettings) {
        pauseWhenOccluded = settings.pauseWhenOccluded
        pauseOnDisplaySleep = settings.pauseOnDisplaySleep
        pauseOnBattery = settings.pauseOnBattery
        pauseInLowPowerMode = settings.pauseInLowPowerMode
    }

    /// Render gate for an externally-driven host (the screensaver) that only knows
    /// two things: whether its view is actually visible, and whether the display is
    /// awake. `legacyScreenSaver` can abandon a saver view without ever calling
    /// `stopAnimation()` (per-Space / per-idle instances accumulate), so the saver
    /// must self-gate — otherwise an orphaned instance renders, and overheats the
    /// Mac, for days. Uses the default pause-when-occluded / pause-on-display-sleep
    /// behaviour, the same the live wallpaper relies on.
    public static func saverShouldDraw(visible: Bool, displayAsleep: Bool) -> Bool {
        PlaybackPolicy(occluded: !visible, displayAsleep: displayAsleep).shouldRender
    }
}
