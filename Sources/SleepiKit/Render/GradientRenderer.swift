import AppKit
import MetalKit
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
        mtkView.framebufferOnly = true
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
        updateColors()
    }

    public func setFPSCap(_ cap: Int) {
        fpsCap = cap
        mtkView.preferredFramesPerSecond = effectiveFPS
    }

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
        mtkView.isPaused = false
    }
    public func pause() { mtkView.isPaused = true }
    public func resume() { mtkView.isPaused = false }
    public func stop() { mtkView.isPaused = true }

    // MARK: MTKViewDelegate

    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    public func draw(in view: MTKView) {
        guard let pipeline,
              let colorBuffer,
              let drawable = view.currentDrawable,
              let passDescriptor = view.currentRenderPassDescriptor,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDescriptor) else { return }

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

        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<GradientUniforms>.stride, index: 0)
        encoder.setFragmentBuffer(colorBuffer, offset: 0, index: 1)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
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
