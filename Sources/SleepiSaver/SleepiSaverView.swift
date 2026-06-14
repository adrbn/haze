import ScreenSaver
import AppKit
import SleepiKit

/// The screensaver entry point. Reuses SleepiKit's renderers so the screensaver
/// shows the same kind of content as the live wallpaper. Resolves the chosen
/// item from the shared settings/manifest the app writes.
@objc(SleepiSaverView)
final class SleepiSaverView: ScreenSaverView {
    private var renderer: WallpaperRenderer?

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

    private func configure() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor

        let item = SleepiKit.screensaverItem()
        let cap = SleepiKit.globalFPSCap()
        guard let renderer = RendererFactory.makeRenderer(for: item, fpsCap: cap) else {
            Log.saver.error("No renderer for screensaver item")
            return
        }
        self.renderer = renderer
        let view = renderer.view
        view.frame = bounds
        view.autoresizingMask = [.width, .height]
        addSubview(view)
    }

    override func startAnimation() {
        super.startAnimation()
        renderer?.start()
    }

    override func stopAnimation() {
        super.stopAnimation()
        renderer?.stop()
    }

    // Renderers self-drive (AVPlayer / MTKView), so no per-frame work is needed.
    override func animateOneFrame() {}

    override var hasConfigureSheet: Bool { false }
    override var configureSheet: NSWindow? { nil }
}
