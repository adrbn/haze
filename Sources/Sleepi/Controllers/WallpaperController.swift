import AppKit
import SleepiKit

/// Wires the desktop `DisplayManager` to the `PowerMonitor` so wallpapers pause
/// automatically when occluded / asleep / on battery, and exposes a small API
/// for the app model to drive.
@MainActor
final class WallpaperController {
    private let display = DisplayManager()
    private var power: PowerMonitor?

    func configure(settings: AppSettings) {
        let monitor = PowerMonitor(settings: settings)
        monitor.onShouldRenderChange = { [weak self] shouldRender in
            self?.display.setRendering(shouldRender)
        }
        display.onOcclusionChange = { [weak monitor] occluded in
            monitor?.setOccluded(occluded)
        }
        power = monitor
        display.setRendering(monitor.policy.shouldRender)
    }

    func apply(item: ContentItem, settings: AppSettings) {
        display.apply(item: item, fpsCap: settings.globalFPSCap)
    }

    func updateSettings(_ settings: AppSettings) {
        power?.updateSettings(settings)
        display.setFPSCap(settings.globalFPSCap)
    }

    func setUserPaused(_ paused: Bool) {
        power?.setUserPaused(paused)
    }

    var isUserPaused: Bool { power?.isUserPaused ?? false }

    func clear() { display.clear() }
}
