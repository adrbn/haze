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
        queue.automaticallyWaitsToMinimizeStalling = false   // play immediately, no startup buffer wait
        self.asset = asset
        self.player = queue
        self.playbackRate = VideoRenderer.clampRate(rate)
        self.hostView = PlayerHostView(player: queue, gravity: scaling.videoGravity)
        super.init()
        primeLooperIfNeeded()
    }

    private func primeLooperIfNeeded() {
        guard looper == nil else { return }
        // Warm the asset's timing/track metadata so the first loop transition
        // doesn't hitch (AVPlayerLooper otherwise stalls until they load).
        asset.loadValuesAsynchronously(forKeys: ["duration", "tracks", "playable"])
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
        playbackRate = VideoRenderer.clampRate(item.settings.speed)
        if player.rate != 0 { player.rate = playbackRate }   // adjust in place if playing
    }

    /// Keep playback rate within the UI's range (0.25–2x).
    static func clampRate(_ rate: Double) -> Float {
        min(max(Float(rate), 0.25), 2.0)
    }

    deinit { player.pause() }
}
