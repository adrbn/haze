import AppKit
import AVFoundation
import CoreVideo

/// Layer-backed view whose `layer.contents` is set directly from decoded frames.
final class VideoHostView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        let root = CALayer()
        root.backgroundColor = NSColor.black.cgColor
        layer = root
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }
}

/// Seamless looping video with hardware decode and no audio by default.
///
/// Frames are pulled with `AVPlayerItemVideoOutput` and presented on a display
/// link, instead of letting an `AVPlayerLayer` present itself. macOS throttles a
/// background/desktop `AVPlayerLayer` (it drops a 30fps clip to ~18fps on the
/// desktop even though decode is ~1% CPU); driving presentation off the display
/// link keeps it at full frame rate. In the sandboxed screensaver host — where
/// the view's display link may not fire — `tick()` presents instead.
public final class VideoRenderer: NSObject, WallpaperRenderer {
    private let hostView: VideoHostView
    private let player: AVQueuePlayer
    private let asset: AVURLAsset
    private var looper: AVPlayerLooper?
    private let output: AVPlayerItemVideoOutput
    private var displayLink: CVDisplayLink?
    private var itemObservation: NSKeyValueObservation?
    private weak var outputItem: AVPlayerItem?
    private var playbackRate: Float

    public var view: NSView { hostView }

    public init?(url: URL, scaling: Scaling, rate: Double = 1.0, muted: Bool = true) {
        guard FileManager.default.fileExists(atPath: url.path) else {
            Log.render.error("Video file missing: \(url.lastPathComponent, privacy: .public)")
            return nil
        }
        let asset = AVURLAsset(url: url)
        let queue = AVQueuePlayer()
        queue.isMuted = muted
        queue.volume = muted ? 0 : 1
        queue.actionAtItemEnd = .none
        queue.automaticallyWaitsToMinimizeStalling = false
        self.asset = asset
        self.player = queue
        self.output = AVPlayerItemVideoOutput(pixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
            kCVPixelBufferMetalCompatibilityKey as String: true,
        ])
        self.playbackRate = VideoRenderer.clampRate(rate)
        let host = VideoHostView(frame: .zero)
        host.layer?.contentsGravity = scaling.contentsGravity
        self.hostView = host
        super.init()
        primeLooperIfNeeded()
        attachOutputToCurrentItem()
        // The looper swaps in a fresh item each loop; move our output onto it.
        itemObservation = queue.observe(\.currentItem) { [weak self] _, _ in
            self?.attachOutputToCurrentItem()
        }
    }

    private func primeLooperIfNeeded() {
        guard looper == nil else { return }
        looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(asset: asset))
    }

    private func attachOutputToCurrentItem() {
        guard let item = player.currentItem, item !== outputItem else { return }
        if let previous = outputItem, previous.outputs.contains(output) { previous.remove(output) }
        item.add(output)
        outputItem = item
    }

    // MARK: Presentation

    private func startDisplayLink() {
        guard displayLink == nil else { return }
        // CVDisplayLink (display-tied) fires reliably for desktop-level windows,
        // unlike NSView's CADisplayLink — same mechanism MTKView uses internally.
        var link: CVDisplayLink?
        CVDisplayLinkCreateWithActiveCGDisplays(&link)
        guard let link else { return }
        CVDisplayLinkSetOutputHandler(link) { [weak self] _, _, inOutputTime, _, _ in
            // Map the *upcoming vsync* to an item time and present it on this
            // thread — no hop to main, so frame selection stays synced to the
            // display (clean 2:2 cadence for 30fps on a 60Hz panel).
            guard let self else { return kCVReturnSuccess }
            self.present(forItemTime: self.output.itemTime(for: inOutputTime.pointee))
            return kCVReturnSuccess
        }
        CVDisplayLinkStart(link)
        displayLink = link
    }

    private func stopDisplayLink() {
        if let displayLink { CVDisplayLinkStop(displayLink) }
        displayLink = nil
    }

    /// Copy the decoded frame for `time` into the layer if a new one is ready.
    /// Safe off-main (Core Animation accepts an explicit transaction from any
    /// thread); the layer is only mutated here once playing.
    private func present(forItemTime time: CMTime) {
        guard output.hasNewPixelBuffer(forItemTime: time),
              let buffer = output.copyPixelBuffer(forItemTime: time, itemTimeForDisplay: nil)
        else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        hostView.layer?.contents = buffer
        CATransaction.commit()
    }

    /// Present whatever frame matches "now" — used by start()/tick()/redraw().
    private func presentCurrent() {
        present(forItemTime: output.itemTime(forHostTime: CACurrentMediaTime()))
    }

    // MARK: WallpaperRenderer

    public func start() {
        primeLooperIfNeeded()
        attachOutputToCurrentItem()
        player.rate = playbackRate   // rate > 0 begins playback
        startDisplayLink()
        presentCurrent()
    }

    public func pause() {
        player.pause()
        stopDisplayLink()
    }

    public func resume() {
        player.rate = playbackRate
        startDisplayLink()
    }

    public func stop() {
        stopDisplayLink()
        player.pause()
        player.removeAllItems()
        looper = nil
        outputItem = nil
    }

    /// Screensaver-host fallback (its view's display link may not fire).
    public func tick() { presentCurrent() }
    public func redraw() { presentCurrent() }

    public func liveUpdate(_ item: ContentItem) {
        playbackRate = VideoRenderer.clampRate(item.settings.speed)
        if player.rate != 0 { player.rate = playbackRate }   // adjust in place if playing
    }

    /// Keep playback rate within the UI's range (0.25–2x).
    static func clampRate(_ rate: Double) -> Float {
        min(max(Float(rate), 0.25), 2.0)
    }

    deinit {
        itemObservation?.invalidate()
        if let displayLink { CVDisplayLinkStop(displayLink) }
        player.pause()
    }
}
