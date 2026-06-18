import ScreenSaver
import AppKit
import QuartzCore
import HazeKit

/// The screensaver entry point. Reuses HazeKit's renderers so the screensaver
/// shows the same kind of content as the live wallpaper. Resolves the chosen
/// item from the shared settings/manifest the app writes.
@objc(HazeSaverView)
final class HazeSaverView: ScreenSaverView {
    private var renderer: WallpaperRenderer?
    private var driveTimer: Timer?
    private var lastDrawTime: CFTimeInterval = 0

    /// The System Settings thumbnail (isPreview) is tiny and was driving the full
    /// 3D render + 4K gaussian blur at 30fps — ~34% CPU / heat. There it only
    /// needs a slow, blur-free render.
    private var targetFPS: Double { isPreview ? 8 : 30 }

    override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        animationTimeInterval = 1.0 / targetFPS
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        animationTimeInterval = 1.0 / targetFPS
        configure()
    }

    deinit { driveTimer?.invalidate() }

    private func configure() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor

        let content = HazeKit.screensaverContent()
        var item = content.item
        if isPreview {
            // Drop the expensive gaussian-blur pass — invisible at thumbnail size.
            item.gradient?.blur = 0
            item.shaderGradient?.blur = 0
        }
        guard let renderer = RendererFactory.makeRenderer(for: item, fpsCap: isPreview ? Int(targetFPS) : content.fpsCap) else {
            Log.saver.error("No renderer for screensaver item \(item.name, privacy: .public)")
            return
        }
        self.renderer = renderer
        // MTKView's own display link doesn't fire reliably in the screensaver
        // host, so we drive frames ourselves (see drive()).
        renderer.setExternallyDriven(true)
        let view = renderer.view
        view.frame = bounds
        view.autoresizingMask = [.width, .height]
        addSubview(view)

        // Drive immediately + via a fallback timer, so the saver renders even in
        // contexts (e.g. the System Settings thumbnail) that don't call
        // animateOneFrame.
        renderer.start()
        renderer.redraw()
        startDriveTimer()
        Log.saver.info("HazeSaver loaded \(item.name, privacy: .public) [\(item.type.rawValue, privacy: .public)] isPreview=\(self.isPreview, privacy: .public) fps=\(self.targetFPS, privacy: .public)")
    }

    override func startAnimation() {
        super.startAnimation()
        renderer?.start()
        renderer?.redraw()
        startDriveTimer()
    }

    override func stopAnimation() {
        super.stopAnimation()
        driveTimer?.invalidate()
        driveTimer = nil
        renderer?.stop()
    }

    override func animateOneFrame() {
        drive()
    }

    override var hasConfigureSheet: Bool { false }
    override var configureSheet: NSWindow? { nil }

    private func startDriveTimer() {
        driveTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0 / targetFPS, repeats: true) { [weak self] _ in
            self?.drive()
        }
        RunLoop.main.add(timer, forMode: .common)
        driveTimer = timer
    }

    /// Throttled to the target rate so the host's animateOneFrame and our fallback
    /// timer don't double-draw when both fire.
    private func drive() {
        let now = CACurrentMediaTime()
        guard now - lastDrawTime >= (1.0 / targetFPS) * 0.9 else { return }
        lastDrawTime = now
        renderer?.tick()
    }
}
