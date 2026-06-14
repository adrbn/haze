import AppKit
import ImageIO

/// Plays GIF / APNG via a discrete `CAKeyframeAnimation` over the decoded
/// frames. Frames are decoded on a background queue (capped) and applied on the
/// main thread, so importing/applying a large animation never blocks the UI.
final class AnimatedImageView: NSView {
    private let imageLayer = CALayer()
    private var animation: CAKeyframeAnimation?
    private var playing = false
    private static let maxFrames = 300

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

    /// Validates the source synchronously (cheap) and kicks off background decode.
    func load(url: URL, scaling: Scaling) -> Bool {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetCount(source) > 0 else { return false }
        imageLayer.contentsGravity = scaling.contentsGravity

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let count = min(CGImageSourceGetCount(source), Self.maxFrames)
            var frames: [CGImage] = []
            var delays: [Double] = []
            for i in 0..<count {
                guard let frame = CGImageSourceCreateImageAtIndex(source, i, nil) else { continue }
                frames.append(frame)
                delays.append(Self.frameDelay(source, i))
            }
            guard !frames.isEmpty else { return }

            let total = max(delays.reduce(0, +), 0.05)
            var keyTimes: [NSNumber] = []
            var acc = 0.0
            for d in delays {
                keyTimes.append(NSNumber(value: acc / total))
                acc += d
            }

            let anim = CAKeyframeAnimation(keyPath: "contents")
            anim.values = frames
            anim.keyTimes = keyTimes
            anim.duration = total
            anim.calculationMode = .discrete
            anim.repeatCount = .infinity
            anim.isRemovedOnCompletion = false

            DispatchQueue.main.async {
                guard let self else { return }
                self.imageLayer.contents = frames.first
                self.animation = anim
                if self.playing { self.applyAnimation() }
            }
        }
        return true
    }

    func play() {
        playing = true
        applyAnimation()
    }

    func stopPlaying() {
        playing = false
        imageLayer.removeAnimation(forKey: "frames")
    }

    private func applyAnimation() {
        guard let animation, imageLayer.animation(forKey: "frames") == nil else { return }
        imageLayer.add(animation, forKey: "frames")
    }

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
