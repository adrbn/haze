import Foundation

/// User preferences plus the current wallpaper/screensaver selections.
/// Persisted as `settings.json` so the screensaver process can read which
/// item the user chose for it.
/// How the main window presents its sections: a left sidebar, or a floating
/// liquid-glass bar.
public enum NavLayout: String, Codable, Sendable, CaseIterable {
    case sidebar, bar
}

/// Which edge the floating liquid-glass nav bar hugs (when `navLayout == .bar`).
public enum BarEdge: String, Codable, Sendable, CaseIterable {
    case top, bottom
}

public struct AppSettings: Codable, Sendable, Equatable {
    public static let currentVersion = 1

    public var version: Int
    public var wallpaperItemID: UUID?
    public var screensaverItemID: UUID?

    // Power / resource behaviour
    public var pauseWhenOccluded: Bool
    public var pauseOnDisplaySleep: Bool
    public var pauseOnBattery: Bool
    public var pauseInLowPowerMode: Bool

    /// Global FPS cap (0 = follow display refresh). Lower = less energy.
    public var globalFPSCap: Int

    public var launchAtLogin: Bool

    /// IDs of bundled gradient presets already added to the library, so new
    /// presets get seeded once on update and deleted ones don't reappear.
    public var seededGradientPresetIDs: [String]

    /// Favourited item IDs (UUID strings).
    public var favoriteItemIDs: [String]

    /// Play audio for video wallpapers (off by default).
    public var videoSoundEnabled: Bool

    /// Main-window navigation presentation.
    public var navLayout: NavLayout
    /// Edge for the floating nav bar (used only when `navLayout == .bar`).
    public var barEdge: BarEdge

    public init(version: Int = AppSettings.currentVersion,
                wallpaperItemID: UUID? = nil,
                screensaverItemID: UUID? = nil,
                pauseWhenOccluded: Bool = true,
                pauseOnDisplaySleep: Bool = true,
                pauseOnBattery: Bool = false,
                pauseInLowPowerMode: Bool = true,
                globalFPSCap: Int = 0,
                launchAtLogin: Bool = false,
                seededGradientPresetIDs: [String] = [],
                favoriteItemIDs: [String] = [],
                videoSoundEnabled: Bool = false,
                navLayout: NavLayout = .sidebar,
                barEdge: BarEdge = .top) {
        self.version = version
        self.wallpaperItemID = wallpaperItemID
        self.screensaverItemID = screensaverItemID
        self.pauseWhenOccluded = pauseWhenOccluded
        self.pauseOnDisplaySleep = pauseOnDisplaySleep
        self.pauseOnBattery = pauseOnBattery
        self.pauseInLowPowerMode = pauseInLowPowerMode
        self.globalFPSCap = globalFPSCap
        self.launchAtLogin = launchAtLogin
        self.seededGradientPresetIDs = seededGradientPresetIDs
        self.favoriteItemIDs = favoriteItemIDs
        self.videoSoundEnabled = videoSoundEnabled
        self.navLayout = navLayout
        self.barEdge = barEdge
    }

    public static let `default` = AppSettings()

    // Forward-compatible decoding: missing keys fall back to defaults.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings.default
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? d.version
        wallpaperItemID = try c.decodeIfPresent(UUID.self, forKey: .wallpaperItemID)
        screensaverItemID = try c.decodeIfPresent(UUID.self, forKey: .screensaverItemID)
        pauseWhenOccluded = try c.decodeIfPresent(Bool.self, forKey: .pauseWhenOccluded) ?? d.pauseWhenOccluded
        pauseOnDisplaySleep = try c.decodeIfPresent(Bool.self, forKey: .pauseOnDisplaySleep) ?? d.pauseOnDisplaySleep
        pauseOnBattery = try c.decodeIfPresent(Bool.self, forKey: .pauseOnBattery) ?? d.pauseOnBattery
        pauseInLowPowerMode = try c.decodeIfPresent(Bool.self, forKey: .pauseInLowPowerMode) ?? d.pauseInLowPowerMode
        globalFPSCap = try c.decodeIfPresent(Int.self, forKey: .globalFPSCap) ?? d.globalFPSCap
        launchAtLogin = try c.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? d.launchAtLogin
        seededGradientPresetIDs = try c.decodeIfPresent([String].self, forKey: .seededGradientPresetIDs) ?? d.seededGradientPresetIDs
        favoriteItemIDs = try c.decodeIfPresent([String].self, forKey: .favoriteItemIDs) ?? d.favoriteItemIDs
        videoSoundEnabled = try c.decodeIfPresent(Bool.self, forKey: .videoSoundEnabled) ?? d.videoSoundEnabled
        navLayout = try c.decodeIfPresent(NavLayout.self, forKey: .navLayout) ?? d.navLayout
        barEdge = try c.decodeIfPresent(BarEdge.self, forKey: .barEdge) ?? d.barEdge
    }
}
