import AppKit
import SleepiKit

/// Wires the desktop `DisplayManager` to the `PowerMonitor` + `OcclusionDetector`
/// so wallpapers pause automatically when occluded / asleep / on battery, and
/// exposes a small API for the app model to drive.
@MainActor
final class WallpaperController {
    private let display = DisplayManager()
    private let occlusion = OcclusionDetector()
    private var power: PowerMonitor?

    func configure(settings: AppSettings) {
        let monitor = PowerMonitor(settings: settings)
        monitor.onShouldRenderChange = { [weak self] shouldRender in
            self?.display.setRendering(shouldRender)
        }
        power = monitor

        occlusion.onChange = { [weak monitor] occluded in
            monitor?.setOccluded(occluded)
        }
        occlusion.start()
        monitor.setOccluded(occlusion.currentlyOccluded)

        display.setRendering(monitor.policy.shouldRender)
    }

    func apply(item: ContentItem, settings: AppSettings) {
        display.apply(item: item, fpsCap: settings.globalFPSCap, muted: !settings.videoSoundEnabled)
        occlusion.evaluate()
    }

    /// Update the playing wallpaper's config in real time (no rebuild).
    func liveUpdate(item: ContentItem) {
        display.liveUpdate(item)
    }

    func updateSettings(_ settings: AppSettings) {
        power?.updateSettings(settings)
        display.setFPSCap(settings.globalFPSCap)
    }

    func setUserPaused(_ paused: Bool) {
        power?.setUserPaused(paused)
    }

    /// Re-raise the live wallpaper windows above the system desktop picture —
    /// needed right after we change the macOS desktop image, which macOS layers
    /// on top of our desktop-level windows.
    func reassert() { display.reassertWindows() }

    var isUserPaused: Bool { power?.isUserPaused ?? false }

    func clear() { display.clear() }
}
