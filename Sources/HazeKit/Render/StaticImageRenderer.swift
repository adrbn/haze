import AppKit

/// Layer-backed still image with proper aspect-fill support (which plain
/// `NSImageView` lacks).
final class StaticImageView: NSView {
    private let imageLayer = CALayer()

    override init(frame frameRect: NSRect) { super.init(frame: frameRect); commonInit() }
    required init?(coder: NSCoder) { super.init(coder: coder); commonInit() }

    private func commonInit() {
        wantsLayer = true
        let root = CALayer()
        root.backgroundColor = NSColor.black.cgColor
        layer = root
        imageLayer.frame = bounds
        root.addSublayer(imageLayer)
    }

    func set(_ image: CGImage, scaling: Scaling) {
        imageLayer.contents = image
        imageLayer.contentsGravity = scaling.contentsGravity
    }

    override func layout() {
        super.layout()
        imageLayer.frame = bounds
    }
}

public final class StaticImageRenderer: NSObject, WallpaperRenderer {
    private let imageView = StaticImageView()
    public var view: NSView { imageView }

    public init?(url: URL, scaling: Scaling) {
        guard FileManager.default.fileExists(atPath: url.path) else {
            Log.render.error("Image file missing: \(url.lastPathComponent, privacy: .public)")
            return nil
        }
        super.init()
        // Decode off the main thread, then apply on main.
        DispatchQueue.global(qos: .userInitiated).async { [weak imageView] in
            guard let nsImage = NSImage(contentsOf: url),
                  let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                Log.render.error("Failed to decode image: \(url.lastPathComponent, privacy: .public)")
                return
            }
            DispatchQueue.main.async {
                imageView?.set(cgImage, scaling: scaling)
            }
        }
    }

    public func start() {}
    public func pause() {}
    public func resume() {}
    public func stop() {}
}
