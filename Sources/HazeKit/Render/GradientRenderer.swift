import AppKit
import MetalKit
import MetalPerformanceShaders
import QuartzCore
import simd

/// Renders an animated gradient with Metal at a capped frame rate. Wraps an
/// `MTKView`, which provides the internal display-link driving and `isPaused`
/// support used for occlusion/sleep pausing.
public final class GradientRenderer: NSObject, WallpaperRenderer, MTKViewDelegate {
    private let mtkView: MTKView
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private var pipeline: MTLRenderPipelineState?
    private var colorBuffer: MTLBuffer?
    private var resolvedColorCount: Int32 = 2
    private var config: GradientConfig
    private var fpsCap: Int
    private var startTime: CFTimeInterval = 0
    private var externallyDriven = false
    private var isStopped = false

    // Gaussian blur post-process (only used when config.blur > 0).
    private var sceneTexture: MTLTexture?
    private var blurredTexture: MTLTexture?
    private var blurKernel: MPSImageGaussianBlur?
    private var blurSigma: Float = -1
    private var compositePipeline: MTLRenderPipelineState?

    public var view: NSView { mtkView }

    public init?(config: GradientConfig, fpsCap: Int = 0) {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue() else {
            Log.render.error("No Metal device / command queue available")
            return nil
        }
        self.device = device
        self.commandQueue = queue
        self.config = config
        self.fpsCap = fpsCap
        self.mtkView = CappedMTKView(frame: .zero, device: device)   // caps render res → less GPU/heat
        super.init()

        mtkView.colorPixelFormat = .bgra8Unorm
        mtkView.framebufferOnly = true   // MPS writes an offscreen; the drawable is only a render target
        mtkView.wantsLayer = true
        // Non-opaque so the poster behind it shows during Space swipes / Mission
        // Control (where Metal can't be captured). Frames are opaque, so live
        // viewing is unchanged.
        mtkView.layer?.isOpaque = false
        mtkView.enableSetNeedsDisplay = false
        mtkView.isPaused = true
        mtkView.preferredFramesPerSecond = effectiveFPS
        mtkView.delegate = self

        buildPipeline()
        updateColors()

        if pipeline == nil { return nil }
    }

    private var effectiveFPS: Int {
        let desired = config.fps > 0 ? config.fps : 30
        return fpsCap > 0 ? min(desired, fpsCap) : desired
    }

    /// Live-update the gradient (used by the editor preview).
    public func update(config: GradientConfig) {
        self.config = config
        mtkView.preferredFramesPerSecond = effectiveFPS
        if config.blur <= 0 { releaseBlurResources() }
        updateColors()
    }

    private func releaseBlurResources() {
        sceneTexture = nil
        blurredTexture = nil
        blurKernel = nil
        blurSigma = -1
    }

    public func setFPSCap(_ cap: Int) {
        fpsCap = cap
        mtkView.preferredFramesPerSecond = effectiveFPS
    }

    public func liveUpdate(_ item: ContentItem) {
        if let config = item.gradient { update(config: config) }
    }

    public func redraw() { autoreleasepool { mtkView.draw() } }

    private func updateColors() {
        let colors = config.resolvedColors
        resolvedColorCount = Int32(colors.count)
        colorBuffer = device.makeBuffer(bytes: colors,
                                        length: MemoryLayout<SIMD4<Float>>.stride * colors.count,
                                        options: .storageModeShared)
    }

    private func buildPipeline() {
        do {
            let library = try device.makeDefaultLibrary(bundle: Bundle(for: GradientRenderer.self))
            let desc = MTLRenderPipelineDescriptor()
            desc.vertexFunction = library.makeFunction(name: "haze_gradient_vertex")
            desc.fragmentFunction = library.makeFunction(name: "haze_gradient_fragment")
            desc.colorAttachments[0].pixelFormat = mtkView.colorPixelFormat
            pipeline = try device.makeRenderPipelineState(descriptor: desc)

            let compDesc = MTLRenderPipelineDescriptor()
            compDesc.vertexFunction = library.makeFunction(name: "composite_vertex")
            compDesc.fragmentFunction = library.makeFunction(name: "composite_grain_fragment")
            compDesc.colorAttachments[0].pixelFormat = mtkView.colorPixelFormat
            compositePipeline = try device.makeRenderPipelineState(descriptor: compDesc)
        } catch {
            Log.render.error("Gradient pipeline build failed: \(error.localizedDescription, privacy: .public)")
            pipeline = nil
        }
    }

    // MARK: WallpaperRenderer

    public func start() {
        isStopped = false
        startTime = CACurrentMediaTime()
        mtkView.preferredFramesPerSecond = effectiveFPS
        if !externallyDriven { mtkView.isPaused = false }
    }
    public func pause() { mtkView.isPaused = true }
    public func resume() { if !externallyDriven { mtkView.isPaused = false } }
    public func stop() {
        // tick() drives draw() manually and ignores isPaused, so a flag is what
        // actually halts an externally-driven (screensaver) frame. Free the blur
        // textures + MPS kernel too, instead of only pausing.
        isStopped = true
        mtkView.isPaused = true
        releaseBlurResources()
    }

    public func setExternallyDriven(_ on: Bool) {
        externallyDriven = on
        mtkView.enableSetNeedsDisplay = on
        if on { mtkView.isPaused = true }
    }

    public func tick() {
        guard externallyDriven, !isStopped else { return }
        // Wrap the manual draw in an autorelease pool: with the display link paused
        // (externally-driven), MTKView doesn't provide its per-frame pool, so each
        // frame's drawable/command buffer/encoders would pile up undrained on the
        // RunLoop pool — multi-GB over a long screensaver run.
        autoreleasepool { mtkView.draw() }
    }

    // MARK: MTKViewDelegate

    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    public func draw(in view: MTKView) {
        guard let pipeline, let colorBuffer,
              let drawable = view.currentDrawable,
              let commandBuffer = commandQueue.makeCommandBuffer() else { return }

        if startTime == 0 { startTime = CACurrentMediaTime() }
        let elapsed = Float(CACurrentMediaTime() - startTime)
        let size = view.drawableSize
        var uniforms = GradientUniforms(
            resolution: SIMD2<Float>(Float(size.width), Float(max(size.height, 1))),
            time: elapsed,
            speed: Float(config.speed),
            grain: Float(config.grain),
            warp: Float(config.warp),
            brightness: Float(config.brightness),
            colorCount: resolvedColorCount,
            style: Int32(config.style.shaderIndex))

        if config.blur > 0,
           let scene = sceneColorTexture(size: size),
           let blurred = ensureBlurred(size: size),
           let compositePipeline {
            uniforms.grain = 0   // grain added OVER the blur in the composite pass
            let sigma = max(Float(config.blur) * 36.0, 0.5)

            // Pass 1 — gradient (grain-free) -> offscreen.
            let scenePass = MTLRenderPassDescriptor()
            scenePass.colorAttachments[0].texture = scene
            scenePass.colorAttachments[0].loadAction = .clear
            scenePass.colorAttachments[0].clearColor = view.clearColor
            scenePass.colorAttachments[0].storeAction = .store
            guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: scenePass) else {
                commandBuffer.commit(); return
            }
            encodeGradient(encoder, &uniforms, pipeline: pipeline, colorBuffer: colorBuffer)

            // Pass 2 — blur.
            if blurKernel == nil || blurSigma != sigma {
                let kernel = MPSImageGaussianBlur(device: device, sigma: sigma)
                kernel.edgeMode = .clamp
                blurKernel = kernel
                blurSigma = sigma
            }
            blurKernel?.encode(commandBuffer: commandBuffer, sourceTexture: scene, destinationTexture: blurred)

            // Pass 3 — composite + grain -> drawable.
            let drawPass = MTLRenderPassDescriptor()
            drawPass.colorAttachments[0].texture = drawable.texture
            drawPass.colorAttachments[0].loadAction = .dontCare
            drawPass.colorAttachments[0].storeAction = .store
            guard let comp = commandBuffer.makeRenderCommandEncoder(descriptor: drawPass) else {
                commandBuffer.commit(); return
            }
            var cu = CompositeUniforms(
                resolution: SIMD2<Float>(Float(size.width), Float(size.height)),
                grain: Float(config.grain), time: elapsed)
            comp.setRenderPipelineState(compositePipeline)
            comp.setFragmentBytes(&cu, length: MemoryLayout<CompositeUniforms>.stride, index: 0)
            comp.setFragmentTexture(blurred, index: 0)
            comp.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            comp.endEncoding()
            commandBuffer.present(drawable)
            commandBuffer.commit()
        } else {
            guard let passDescriptor = view.currentRenderPassDescriptor,
                  let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDescriptor) else {
                commandBuffer.commit()
                return
            }
            encodeGradient(encoder, &uniforms, pipeline: pipeline, colorBuffer: colorBuffer)
            commandBuffer.present(drawable)
            commandBuffer.commit()
        }
    }

    /// Offscreen target for the blurred result (MPS writes it, composite reads it).
    private func ensureBlurred(size: CGSize) -> MTLTexture? {
        let w = Int(size.width), h = Int(size.height)
        guard w > 0, h > 0 else { return nil }
        if let t = blurredTexture, t.width == w, t.height == h { return t }
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: mtkView.colorPixelFormat, width: w, height: h, mipmapped: false)
        desc.usage = [.shaderRead, .shaderWrite]
        desc.storageMode = .private
        blurredTexture = device.makeTexture(descriptor: desc)
        return blurredTexture
    }

    private func encodeGradient(_ encoder: MTLRenderCommandEncoder,
                                _ uniforms: inout GradientUniforms,
                                pipeline: MTLRenderPipelineState,
                                colorBuffer: MTLBuffer) {
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<GradientUniforms>.stride, index: 0)
        encoder.setFragmentBuffer(colorBuffer, offset: 0, index: 1)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
    }

    private func sceneColorTexture(size: CGSize) -> MTLTexture? {
        let w = Int(size.width), h = Int(size.height)
        guard w > 0, h > 0 else { return nil }
        if let t = sceneTexture, t.width == w, t.height == h { return t }
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: mtkView.colorPixelFormat, width: w, height: h, mipmapped: false)
        desc.usage = [.renderTarget, .shaderRead]
        desc.storageMode = .private
        sceneTexture = device.makeTexture(descriptor: desc)
        return sceneTexture
    }
}

extension GradientStyle {
    var shaderIndex: Int {
        switch self {
        case .aurora: return 0
        case .liquid: return 1
        case .halo: return 2
        }
    }
}
