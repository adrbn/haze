import AppKit
import HazeKit

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
        // Every wallpaper-window build — first apply, user pick, display
        // reconfiguration, session resume — runs inside the `.regular`
        // activation context the WindowServer requires (see below).
        display.rebuildContext = { build in Self.withRegularActivationPolicy(build) }

        let monitor = PowerMonitor(settings: settings)

        // A screen lock / system sleep revokes the windows' live-through-slide
        // treatment even though the windows themselves survive. Re-acquire it
        // once the session is back, so the user never has to re-pick by hand.
        monitor.onSessionResumed = { [weak self] in
            self?.display.rebuildForSessionResume()
        }

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

    // MARK: Activation context

    /// How long `.regular` is held after the build. The window server applies
    /// the compositing treatment when it processes the newly created windows,
    /// not when `orderFrontRegardless()` returns.
    private static let regularPolicyHold: TimeInterval = 0.6

    /// Run `build` with the app promoted to a `.regular` app, then drop back to
    /// the `.accessory` menu-bar agent it normally is.
    ///
    /// Wallpaper windows only composite live through Space-slide transitions
    /// when they are created while the owning app is `.regular` — windows built
    /// by the background accessory agent get snapshot-frozen for the duration of
    /// the slide (user-verified: that is exactly why re-picking a preset from
    /// the settings window, which promotes the app, has always fixed it). The
    /// window keeps the treatment afterwards, so `.accessory` is restored right
    /// away. No `activate()`: the policy alone is enough, so focus is never
    /// stolen — only a brief Dock-icon blip remains.
    private static func withRegularActivationPolicy(_ build: () -> Void) {
        let wasAccessory = NSApp.activationPolicy() == .accessory
        if wasAccessory { NSApp.setActivationPolicy(.regular) }
        build()
        guard wasAccessory else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + regularPolicyHold) {
            if !hasVisibleUserWindow { NSApp.setActivationPolicy(.accessory) }
        }
    }

    /// True while a real Haze UI window is on screen (main window, gradient
    /// editor, Sparkle update dialog) — demoting to `.accessory` under one of
    /// those would pull it out of the Dock and app switcher mid-use. The desktop
    /// wallpaper windows are borderless and the menu-bar panel is an untitled
    /// panel, so neither of them keeps the app promoted.
    private static var hasVisibleUserWindow: Bool {
        NSApp.windows.contains { $0.isVisible && $0.styleMask.contains(.titled) }
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

    /// The static poster shown behind the live view (for Space swipes / Mission
    /// Control, where the live layer can't be snapshotted).
    func setFallbackImage(_ url: URL?) { display.setFallbackImage(url) }

    var isUserPaused: Bool { power?.isUserPaused ?? false }

    func clear() { display.clear() }
}
