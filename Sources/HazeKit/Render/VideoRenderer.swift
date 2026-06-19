import AppKit
import AVFoundation
import CoreMedia

/// Layer-backed view hosting an `AVSampleBufferDisplayLayer`.
final class SampleBufferHostView: NSView {
    let displayLayer = AVSampleBufferDisplayLayer()

    init(gravity: AVLayerVideoGravity) {
        super.init(frame: .zero)
        wantsLayer = true
        // Clear/non-opaque so the poster behind it shows during Space swipes /
        // Mission Control (the sample-buffer layer, like Metal, can't be captured
        // there). Live frames are opaque, so normal playback is unchanged.
        let root = CALayer()
        root.isOpaque = false
        layer = root
        displayLayer.videoGravity = gravity
        root.addSublayer(displayLayer)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)   // no reflow animation on resize
        displayLayer.frame = bounds
        CATransaction.commit()
    }
}

/// Smooth, seamless looping video for the desktop wallpaper.
///
/// Uses `AVSampleBufferDisplayLayer` driven by its own `CMTimebase`, fed by an
/// `AVAssetReader`. Unlike `AVPlayerLayer` (whose internal display link macOS
/// throttles for a non-key / desktop-level window — the "stops/resumes/jumps"
/// stutter) this presents enqueued frames against the layer's own clock,
/// independent of window focus. Looping is gapless: each pass's sample PTS is
/// shifted by a running offset so the stream stays monotonic (no flush, no
/// AVPlayerLooper reload hitch).
public final class VideoRenderer: NSObject, WallpaperRenderer {
    private let host: SampleBufferHostView
    private let asset: AVURLAsset
    private var timebase: CMTimebase!
    private var playbackRate: Float
    private var wantPlaying = false
    private var primed = false   // timebase synced to the first enqueued frame

    private let serial = DispatchQueue(label: "com.adrbn.haze.video.decode", qos: .userInitiated)
    private var track: AVAssetTrack?
    private var reader: AVAssetReader?
    private var trackOutput: AVAssetReaderTrackOutput?
    private var loopDuration: CMTime = .zero
    private var ptsOffset: CMTime = .zero
    private var ready = false

    public var view: NSView { host }

    public init?(url: URL, scaling: Scaling, rate: Double = 1.0, muted: Bool = true) {
        guard FileManager.default.fileExists(atPath: url.path) else {
            Log.render.error("Video file missing: \(url.lastPathComponent, privacy: .public)")
            return nil
        }
        self.asset = AVURLAsset(url: url)
        self.playbackRate = VideoRenderer.clampRate(rate)
        self.host = SampleBufferHostView(gravity: scaling.videoGravity)
        super.init()

        var tb: CMTimebase?
        CMTimebaseCreateWithSourceClock(allocator: kCFAllocatorDefault,
                                        sourceClock: CMClockGetHostTimeClock(),
                                        timebaseOut: &tb)
        timebase = tb
        CMTimebaseSetTime(timebase, time: .zero)
        CMTimebaseSetRate(timebase, rate: 0)
        host.displayLayer.controlTimebase = timebase

        Task { [weak self] in await self?.prepare() }
    }

    private func prepare() async {
        do {
            let tracks = try await asset.loadTracks(withMediaType: .video)
            guard let track = tracks.first else { return }
            self.loopDuration = try await asset.load(.duration)
            self.track = track
            serial.async { [weak self] in self?.beginFeeding() }
        } catch {
            Log.render.error("Video prepare failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: Decode → enqueue (serial queue)

    private func makeReader() {
        guard let track else { return }
        reader?.cancelReading()
        guard let r = try? AVAssetReader(asset: asset) else { return }
        let out = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange),
        ])
        out.alwaysCopiesSampleData = false
        guard r.canAdd(out) else { return }
        r.add(out)
        r.startReading()
        reader = r
        trackOutput = out
    }

    private func beginFeeding() {
        ready = true
        makeReader()
        // Capture ONLY `self`, weakly — never the layer. `requestMediaDataWhenReady`
        // makes the layer own this block; capturing `displayLayer` strongly here too
        // forms a layer↔block retain cycle that survives until `stopRequestingMediaData()`,
        // leaking the layer and every decoded frame still queued in it, while the
        // orphaned decode callback keeps running. The wallpaper keeps one renderer for
        // its whole lifetime so it never surfaced; the screensaver host creates and drops
        // a view per Space/idle, so leaked decoders piled up to GBs and pegged a core.
        // Reach the layer through `self` so the only retained reference is the weak self.
        host.displayLayer.requestMediaDataWhenReady(on: serial) { [weak self] in
            guard let self else { return }
            let layer = self.host.displayLayer
            while layer.isReadyForMoreMediaData {
                guard let sample = self.trackOutput?.copyNextSampleBuffer() else {
                    // End of pass → advance offset, rebuild reader, keep going (gapless).
                    self.ptsOffset = CMTimeAdd(self.ptsOffset, self.loopDuration)
                    self.makeReader()
                    if self.trackOutput == nil { break }
                    continue
                }
                guard let shifted = Self.offsetTiming(sample, by: self.ptsOffset) else { continue }
                layer.enqueue(shifted)
                if !self.primed {
                    // Sync the timebase to the first frame so it doesn't run ahead
                    // of the content (which would leave the layer holding frame 0).
                    let firstPTS = CMSampleBufferGetPresentationTimeStamp(shifted)
                    DispatchQueue.main.async { [weak self] in self?.prime(at: firstPTS) }
                }
            }
        }
    }

    private func prime(at pts: CMTime) {
        guard !primed else { return }
        primed = true
        CMTimebaseSetTime(timebase, time: pts.isValid ? pts : .zero)
        applyRate()
    }

    private static func offsetTiming(_ sb: CMSampleBuffer, by offset: CMTime) -> CMSampleBuffer? {
        guard CMTimeCompare(offset, .zero) != 0 else { return sb }
        var count = 0
        CMSampleBufferGetSampleTimingInfoArray(sb, entryCount: 0, arrayToFill: nil, entriesNeededOut: &count)
        guard count > 0 else { return sb }
        var timings = [CMSampleTimingInfo](repeating: CMSampleTimingInfo(), count: count)
        CMSampleBufferGetSampleTimingInfoArray(sb, entryCount: count, arrayToFill: &timings, entriesNeededOut: &count)
        for i in 0..<count {
            if timings[i].presentationTimeStamp.isValid {
                timings[i].presentationTimeStamp = CMTimeAdd(timings[i].presentationTimeStamp, offset)
            }
            if timings[i].decodeTimeStamp.isValid {
                timings[i].decodeTimeStamp = CMTimeAdd(timings[i].decodeTimeStamp, offset)
            }
        }
        var out: CMSampleBuffer?
        CMSampleBufferCreateCopyWithNewTiming(allocator: kCFAllocatorDefault, sampleBuffer: sb,
                                              sampleTimingEntryCount: count, sampleTimingArray: &timings,
                                              sampleBufferOut: &out)
        return out
    }

    // MARK: Timebase / lifecycle (main)

    private func applyRate() {
        CMTimebaseSetRate(timebase, rate: (wantPlaying && primed) ? Double(playbackRate) : 0)
    }

    public func start() {
        wantPlaying = true
        applyRate()
    }

    public func pause() {
        wantPlaying = false
        CMTimebaseSetRate(timebase, rate: 0)
    }

    public func resume() {
        wantPlaying = true
        applyRate()
    }

    public func stop() {
        wantPlaying = false
        CMTimebaseSetRate(timebase, rate: 0)
        host.displayLayer.stopRequestingMediaData()
        serial.async { [weak self] in
            self?.reader?.cancelReading()
            self?.reader = nil
            self?.trackOutput = nil
        }
        host.displayLayer.flushAndRemoveImage()
    }

    public func liveUpdate(_ item: ContentItem) {
        playbackRate = VideoRenderer.clampRate(item.settings.speed)
        applyRate()
    }

    static func clampRate(_ rate: Double) -> Float { min(max(Float(rate), 0.25), 2.0) }

    deinit {
        // Break the layer↔callback link so the layer and its queued frames are
        // released even if `stop()` was never called (the screensaver host can drop
        // the view without ever invoking stopAnimation).
        host.displayLayer.stopRequestingMediaData()
        reader?.cancelReading()
        CMTimebaseSetRate(timebase, rate: 0)
    }
}
