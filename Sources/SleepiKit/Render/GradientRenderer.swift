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

    // Gaussian blur post-process (only used when config.blur > 0).
    private var sceneTexture: MTLTexture?
    private var blurKernel: MPSImageGaussianBlur?
    private var blurSigma: Float = -1

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
        self.mtkView = MTKView(frame: .zero, device: device)
        super.init()

        mtkView.colorPixelFormat = .bgra8Unorm
        mtkView.framebufferOnly = config.blur <= 0   // false lets MPS write the drawable
        mtkView.autoResizeDrawable = true
        mtkView.wantsLayer = true
        mtkView.layer?.isOpaque = true
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
        mtkView.framebufferOnly = config.blur <= 0
        if config.blur <= 0 { releaseBlurResources() }
        updateColors()
    }

    private func releaseBlurResources() {
        sceneTexture = nil
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

    public func redraw() { mtkView.draw() }

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
            desc.vertexFunction = library.makeFunction(name: "sleepi_gradient_vertex")
            desc.fragmentFunction = library.makeFunction(name: "sleepi_gradient_fragment")
            desc.colorAttachments[0].pixelFormat = mtkView.colorPixelFormat
            pipeline = try device.makeRenderPipelineState(descriptor: desc)
        } catch {
            Log.render.error("Gradient pipeline build failed: \(error.localizedDescription, privacy: .public)")
            pipeline = nil
        }
    }

    // MARK: WallpaperRenderer

    public func start() {
        startTime = CACurrentMediaTime()
        mtkView.preferredFramesPerSecond = effectiveFPS
        if !externallyDriven { mtkView.isPaused = false }
    }
    public func pause() { mtkView.isPaused = true }
    public func resume() { if !externallyDriven { mtkView.isPaused = false } }
    public func stop() { mtkView.isPaused = true }

    public func setExternallyDriven(_ on: Bool) {
        externallyDriven = on
        mtkView.enableSetNeedsDisplay = on
        if on { mtkView.isPaused = true }
    }

    public func tick() {
        guard externallyDriven else { return }
        mtkView.draw()
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

        if config.blur > 0, let scene = sceneColorTexture(size: size) {
            let sigma = max(Float(config.blur) * 36.0, 0.5)
            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = scene
            pass.colorAttachments[0].loadAction = .clear
            pass.colorAttachments[0].clearColor = view.clearColor
            pass.colorAttachments[0].storeAction = .store
            guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else {
                commandBuffer.commit()
                return
            }
            encodeGradient(encoder, &uniforms, pipeline: pipeline, colorBuffer: colorBuffer)
            if blurKernel == nil || blurSigma != sigma {
                let kernel = MPSImageGaussianBlur(device: device, sigma: sigma)
                kernel.edgeMode = .clamp
                blurKernel = kernel
                blurSigma = sigma
            }
            blurKernel?.encode(commandBuffer: commandBuffer, sourceTexture: scene, destinationTexture: drawable.texture)
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
