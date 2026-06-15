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
    private var pauseWork: DispatchWorkItem?

    func configure(settings: AppSettings) {
        let monitor = PowerMonitor(settings: settings)
        monitor.onShouldRenderChange = { [weak self] shouldRender in
            self?.applyRendering(shouldRender)
        }
        power = monitor

        occlusion.onChange = { [weak monitor] occluded in
            monitor?.setOccluded(occluded)
        }
        occlusion.start()
        monitor.setOccluded(occlusion.currentlyOccluded)

        display.setRendering(monitor.policy.shouldRender)
    }

    /// Resume immediately, but only pause after the stop-condition has held for a
    /// short spell. Transient occlusion/activation blips (e.g. clicking through
    /// windows over the desktop) would otherwise stop→start the video every few
    /// seconds, which reads as stutter ("stops/resumes/jumps").
    private func applyRendering(_ shouldRender: Bool) {
        pauseWork?.cancel()
        pauseWork = nil
        if shouldRender {
            display.setRendering(true)
        } else {
            let work = DispatchWorkItem { [weak self] in self?.display.setRendering(false) }
            pauseWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: work)
        }
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

    var isUserPaused: Bool { power?.isUserPaused ?? false }

    func clear() { display.clear() }
}
