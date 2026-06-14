import AppKit
import ImageIO

/// Plays GIF / APNG via a discrete `CAKeyframeAnimation` over the decoded
/// frames. Lighter than a per-frame timer and respects each frame's delay.
final class AnimatedImageView: NSView {
    private let imageLayer = CALayer()
    private var animation: CAKeyframeAnimation?

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

    func load(url: URL, scaling: Scaling) -> Bool {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return false }
        let count = CGImageSourceGetCount(source)
        guard count > 0 else { return false }

        var frames: [CGImage] = []
        var delays: [Double] = []
        for i in 0..<count {
            guard let frame = CGImageSourceCreateImageAtIndex(source, i, nil) else { continue }
            frames.append(frame)
            delays.append(Self.frameDelay(source, i))
        }
        guard !frames.isEmpty else { return false }

        let total = max(delays.reduce(0, +), 0.05)
        var keyTimes: [NSNumber] = []
        var acc = 0.0
        for d in delays {
            keyTimes.append(NSNumber(value: acc / total))
            acc += d
        }

        imageLayer.contents = frames.first
        imageLayer.contentsGravity = scaling.contentsGravity

        let anim = CAKeyframeAnimation(keyPath: "contents")
        anim.values = frames
        anim.keyTimes = keyTimes
        anim.duration = total
        anim.calculationMode = .discrete
        anim.repeatCount = .infinity
        anim.isRemovedOnCompletion = false
        animation = anim
        return true
    }

    func play() {
        guard let animation, imageLayer.animation(forKey: "frames") == nil else { return }
        imageLayer.add(animation, forKey: "frames")
    }

    func stopPlaying() { imageLayer.removeAnimation(forKey: "frames") }

    override func layout() {
        super.layout()
        imageLayer.frame = bounds
    }

    static func frameDelay(_ source: CGImageSource, _ index: Int) -> Double {
        guard let props = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any] else { return 0.1 }
        let dict = (props[kCGImagePropertyGIFDictionary] as? [CFString: Any])
            ?? (props[kCGImagePropertyPNGDictionary] as? [CFString: Any])
        let keys: [CFString] = [
            kCGImagePropertyGIFUnclampedDelayTime, kCGImagePropertyGIFDelayTime,
            kCGImagePropertyAPNGUnclampedDelayTime, kCGImagePropertyAPNGDelayTime,
        ]
        for key in keys {
            if let d = dict?[key] as? Double, d > 0 { return d }
        }
        return 0.1
    }
}

public final class AnimatedImageRenderer: NSObject, WallpaperRenderer {
    private let animatedView = AnimatedImageView()
    public var view: NSView { animatedView }

    public init?(url: URL, scaling: Scaling) {
        super.init()
        guard animatedView.load(url: url, scaling: scaling) else {
            Log.render.error("Failed to load animated image: \(url.lastPathComponent, privacy: .public)")
            return nil
        }
    }

    public func start() { animatedView.play() }
    public func pause() { animatedView.stopPlaying() }
    public func resume() { animatedView.play() }
    public func stop() { animatedView.stopPlaying() }
}
