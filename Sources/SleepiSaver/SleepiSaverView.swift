import ScreenSaver
import AppKit
import QuartzCore
import SleepiKit

/// The screensaver entry point. Reuses SleepiKit's renderers so the screensaver
/// shows the same kind of content as the live wallpaper. Resolves the chosen
/// item from the shared settings/manifest the app writes.
@objc(SleepiSaverView)
final class SleepiSaverView: ScreenSaverView {
    private var renderer: WallpaperRenderer?
    private var driveTimer: Timer?
    private var lastDrawTime: CFTimeInterval = 0

    override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        animationTimeInterval = 1.0 / 30.0
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        animationTimeInterval = 1.0 / 30.0
        configure()
    }

    deinit { driveTimer?.invalidate() }

    private func configure() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor

        let content = SleepiKit.screensaverContent()
        guard let renderer = RendererFactory.makeRenderer(for: content.item, fpsCap: content.fpsCap) else {
            Log.saver.error("No renderer for screensaver item \(content.item.name, privacy: .public)")
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
        Log.saver.info("SleepiSaver loaded \(content.item.name, privacy: .public) [\(content.item.type.rawValue, privacy: .public)] isPreview=\(self.isPreview, privacy: .public)")
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
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            self?.drive()
        }
        RunLoop.main.add(timer, forMode: .common)
        driveTimer = timer
    }

    /// Throttled to ~30fps so the host timer and our fallback timer don't
    /// double-draw when both fire.
    private func drive() {
        let now = CACurrentMediaTime()
        guard now - lastDrawTime >= 1.0 / 35.0 else { return }
        lastDrawTime = now
        renderer?.tick()
    }
}
