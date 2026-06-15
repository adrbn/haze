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
    private var occludeWork: DispatchWorkItem?

    func configure(settings: AppSettings) {
        let monitor = PowerMonitor(settings: settings)
        // Render toggles (user pause, sleep, battery…) apply immediately so the
        // play/pause button is responsive.
        monitor.onShouldRenderChange = { [weak self] shouldRender in
            self?.display.setRendering(shouldRender)
        }
        power = monitor

        // Only the *occlusion* signal is debounced: reveal resumes instantly, but
        // "covered" must hold for a moment before we pause — otherwise transient
        // window/activation blips stop→start the wallpaper every few seconds
        // (reads as stutter). This keeps the manual pause button instant.
        occlusion.onChange = { [weak self, weak monitor] occluded in
            guard let self else { return }
            self.occludeWork?.cancel()
            self.occludeWork = nil
            if !occluded {
                monitor?.setOccluded(false)
            } else {
                let work = DispatchWorkItem { monitor?.setOccluded(true) }
                self.occludeWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: work)
            }
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

    /// Re-assert the wallpaper windows' Space membership after launch settles.
    func reaffirm() { display.reaffirmWindows() }

    var isUserPaused: Bool { power?.isUserPaused ?? false }

    func clear() { display.clear() }
}
