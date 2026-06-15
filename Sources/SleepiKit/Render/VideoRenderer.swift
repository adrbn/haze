import AppKit
import AVFoundation

/// Layer-backed view that hosts an `AVPlayerLayer` and keeps it sized to bounds.
final class PlayerHostView: NSView {
    let playerLayer = AVPlayerLayer()

    init(player: AVPlayer, gravity: AVLayerVideoGravity) {
        super.init(frame: .zero)
        wantsLayer = true
        let root = CALayer()
        root.backgroundColor = NSColor.black.cgColor
        layer = root
        playerLayer.player = player
        playerLayer.videoGravity = gravity
        playerLayer.frame = bounds
        root.addSublayer(playerLayer)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    override func layout() {
        super.layout()
        playerLayer.frame = bounds
    }
}

/// Seamless looping video playback with hardware decode and no audio.
public final class VideoRenderer: NSObject, WallpaperRenderer {
    private let hostView: PlayerHostView
    private let player: AVQueuePlayer
    private let asset: AVURLAsset
    private var looper: AVPlayerLooper?
    private var playbackRate: Float

    public var view: NSView { hostView }

    public init?(url: URL, scaling: Scaling, rate: Double = 1.0) {
        guard FileManager.default.fileExists(atPath: url.path) else {
            Log.render.error("Video file missing: \(url.lastPathComponent, privacy: .public)")
            return nil
        }
        let asset = AVURLAsset(url: url)
        let queue = AVQueuePlayer()
        queue.isMuted = true
        queue.volume = 0
        queue.actionAtItemEnd = .none
        queue.automaticallyWaitsToMinimizeStalling = false
        self.asset = asset
        self.player = queue
        self.playbackRate = max(Float(rate), 0.1)
        self.hostView = PlayerHostView(player: queue, gravity: scaling.videoGravity)
        super.init()
        primeLooperIfNeeded()
    }

    private func primeLooperIfNeeded() {
        guard looper == nil else { return }
        looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(asset: asset))
    }

    public func start() {
        primeLooperIfNeeded()   // tolerate start() after a prior stop()
        player.rate = playbackRate   // setting rate > 0 begins playback at that speed
    }
    public func pause() { player.pause() }
    public func resume() { player.rate = playbackRate }
    public func stop() {
        player.pause()
        player.removeAllItems()
        looper = nil
    }

    public func liveUpdate(_ item: ContentItem) {
        playbackRate = max(Float(item.settings.speed), 0.1)
        if player.rate != 0 { player.rate = playbackRate }   // adjust in place if playing
    }

    deinit { player.pause() }
}
