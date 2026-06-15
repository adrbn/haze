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

        let content = SleepiKit.screensaverContent()
        guard let renderer = RendererFactory.makeRenderer(for: content.item, fpsCap: content.fpsCap) else {
            Log.saver.error("No renderer for screensaver item \(content.item.name, privacy: .public)")
            return
        }
        self.renderer = renderer
        // Drive Metal rendering from animateOneFrame — MTKView's own display link
        // does not fire reliably inside the legacyScreenSaver host.
        renderer.setExternallyDriven(true)
        let view = renderer.view
        view.frame = bounds
        view.autoresizingMask = [.width, .height]
        addSubview(view)
        Log.saver.info("SleepiSaver loaded \(content.item.name, privacy: .public) [\(content.item.type.rawValue, privacy: .public)] isPreview=\(self.isPreview, privacy: .public)")
    }

    override func startAnimation() {
        super.startAnimation()
        renderer?.start()
    }

    override func stopAnimation() {
        super.stopAnimation()
        renderer?.stop()
    }

    // Host timer drives each frame (see setExternallyDriven above).
    override func animateOneFrame() {
        renderer?.tick()
    }

    override var hasConfigureSheet: Bool { false }
    override var configureSheet: NSWindow? { nil }
}
