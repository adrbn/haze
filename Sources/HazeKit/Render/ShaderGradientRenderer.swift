import AppKit
import MetalKit
import MetalPerformanceShaders
import QuartzCore
import simd

/// CPU mirror of `SGUniforms` in ShaderGradientShaders.metal (identical field
/// order → identical layout).
struct SGUniforms {
    var mvp: simd_float4x4
    var model: simd_float4x4
    var time: Float
    var speed: Float
    var density: Float
    var frequency: Float
    var amplitude: Float
    var strength: Float
    var brightness: Float
    var grain: Float
    var reflection: Float
    var type: Int32
    var cameraPos: SIMD4<Float>
}

/// CPU mirror of CompositeUniforms in CompositeShaders.metal.
struct CompositeUniforms {
    var resolution: SIMD2<Float>
    var grain: Float
    var time: Float
}

/// Renders a shadergradient.co-style 3D surface: a subdivided plane displaced by
/// simplex noise, lit, and viewed through a camera built from the config's
/// spherical angles. Wraps an `MTKView` (display-link driven, pausable).
public final class ShaderGradientRenderer: NSObject, WallpaperRenderer, MTKViewDelegate {
    private let mtkView: MTKView
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private var pipeline: MTLRenderPipelineState?
    private var depthState: MTLDepthStencilState?
    private var vertexBuffer: MTLBuffer?
    private var indexBuffer: MTLBuffer?
    private var indexCount = 0
    private var colorBuffer: MTLBuffer?
    private var config: ShaderGradientConfig
    private var fpsCap: Int
    private var startTime: CFTimeInterval = 0
    private var externallyDriven = false
    private var isStopped = false

    // 4x MSAA scene target, resolved into the drawable (or the blur input). The
    // surface folds over itself where the noise is strong, and those silhouette
    // edges stair-step badly without it — worse once the capped drawable is
    // scaled up to the screen. Memoryless on Apple GPUs: no RAM cost.
    private static let sampleCount = 4
    private var msaaColor: MTLTexture?
    private var msaaDepth: MTLTexture?

    // Gaussian blur post-process (only used when config.blur > 0).
    private var sceneTexture: MTLTexture?
    private var blurredTexture: MTLTexture?
    private var blurKernel: MPSImageGaussianBlur?
    private var blurSigma: Float = -1
    private var compositePipeline: MTLRenderPipelineState?

    public var view: NSView { mtkView }

    public init?(config: ShaderGradientConfig, fpsCap: Int = 0) {
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
        mtkView.depthStencilPixelFormat = .invalid   // depth lives in our MSAA target
        mtkView.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        mtkView.framebufferOnly = true   // MPS writes an offscreen; the drawable is only a render target
        mtkView.wantsLayer = true
        // Non-opaque so the poster behind it shows during Space swipes / Mission
        // Control (Metal can't be captured there). The mesh + clearColor fill the
        // frame opaquely (alpha 1), so live viewing is unchanged.
        mtkView.layer?.isOpaque = false
        mtkView.enableSetNeedsDisplay = false
        mtkView.isPaused = true
        mtkView.preferredFramesPerSecond = effectiveFPS
        mtkView.delegate = self

        buildPipeline()
        buildMesh()
        updateColors()
        updateClearColor()

        if pipeline == nil || vertexBuffer == nil { return nil }
    }

    private var effectiveFPS: Int {
        let desired = config.fps > 0 ? config.fps : 30
        return fpsCap > 0 ? min(desired, fpsCap) : desired
    }

    public func update(config: ShaderGradientConfig) {
        self.config = config
        mtkView.preferredFramesPerSecond = effectiveFPS
        if config.blur <= 0 { releaseBlurResources() }
        updateColors()
        updateClearColor()
    }

    private func releaseBlurResources() {
        sceneTexture = nil
        blurredTexture = nil
        blurKernel = nil
        blurSigma = -1
    }

    public func liveUpdate(_ item: ContentItem) {
        if let config = item.shaderGradient { update(config: config) }
    }

    public func redraw() { autoreleasepool { mtkView.draw() } }

    private func updateClearColor() {
        mtkView.clearColor = SGGeometry.clearColor(for: config)
    }

    public func setFPSCap(_ cap: Int) {
        fpsCap = cap
        mtkView.preferredFramesPerSecond = effectiveFPS
    }

    private func updateColors() {
        let colors = config.resolvedColors
        colorBuffer = device.makeBuffer(bytes: colors,
                                        length: MemoryLayout<SIMD4<Float>>.stride * colors.count,
                                        options: .storageModeShared)
    }

    private func buildPipeline() {
        do {
            let library = try device.makeDefaultLibrary(bundle: Bundle(for: ShaderGradientRenderer.self))
            let desc = MTLRenderPipelineDescriptor()
            desc.vertexFunction = library.makeFunction(name: "sg_vertex")
            desc.fragmentFunction = library.makeFunction(name: "sg_fragment")
            desc.colorAttachments[0].pixelFormat = mtkView.colorPixelFormat
            desc.depthAttachmentPixelFormat = .depth32Float
            desc.rasterSampleCount = Self.sampleCount
            pipeline = try device.makeRenderPipelineState(descriptor: desc)

            let depthDesc = MTLDepthStencilDescriptor()
            depthDesc.depthCompareFunction = .less
            depthDesc.isDepthWriteEnabled = true
            depthState = device.makeDepthStencilState(descriptor: depthDesc)

            let compDesc = MTLRenderPipelineDescriptor()
            compDesc.vertexFunction = library.makeFunction(name: "composite_vertex")
            compDesc.fragmentFunction = library.makeFunction(name: "composite_grain_fragment")
            compDesc.colorAttachments[0].pixelFormat = mtkView.colorPixelFormat
            compositePipeline = try device.makeRenderPipelineState(descriptor: compDesc)
        } catch {
            Log.render.error("ShaderGradient pipeline build failed: \(error.localizedDescription, privacy: .public)")
            pipeline = nil
        }
    }

    private func buildMesh() {
        guard let mesh = SGGeometry.mesh(device: device) else { return }
        vertexBuffer = mesh.vertices
        indexBuffer = mesh.indices
        indexCount = mesh.indexCount
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
        // Authoritative stop: tick() drives draw() manually and ignores isPaused,
        // so a flag is what actually halts an externally-driven (screensaver) frame.
        // Also free the blur textures + MPS kernel instead of only pausing.
        isStopped = true
        mtkView.isPaused = true
        releaseBlurResources()
        msaaColor = nil
        msaaDepth = nil
    }

    public func setExternallyDriven(_ on: Bool) {
        externallyDriven = on
        mtkView.enableSetNeedsDisplay = on
        if on { mtkView.isPaused = true }
    }

    public func tick() {
        guard externallyDriven, !isStopped else { return }
        // Manual draw off a RunLoop timer (display link is paused in externally-driven
        // mode): MTKView only wraps a per-frame autorelease pool when ITS OWN link
        // drives drawing. Without this pool, every frame's CAMetalDrawable / command
        // buffer / encoders pile up on the never-drained RunLoop pool — ~2.6 GB over a
        // multi-day screensaver run, the heat/throttle cause.
        autoreleasepool { mtkView.draw() }
    }

    // MARK: MTKViewDelegate

    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    public func draw(in view: MTKView) {
        guard let pipeline, let depthState, let colorBuffer,
              let vertexBuffer, let indexBuffer,
              let drawable = view.currentDrawable,
              let commandBuffer = commandQueue.makeCommandBuffer() else { return }

        if startTime == 0 { startTime = CACurrentMediaTime() }
        let elapsed = Float(CACurrentMediaTime() - startTime)
        var uniforms = SGGeometry.uniforms(config: config, time: elapsed, drawableSize: view.drawableSize)

        if config.blur > 0,
           let scene = sceneTexture(size: view.drawableSize),
           let blurred = ensureBlurred(size: view.drawableSize),
           let compositePipeline,
           let scenePass = msaaPass(resolvingInto: scene, clearColor: view.clearColor) {
            uniforms.grain = 0   // grain is added OVER the blur in the composite pass

            // Pass 1 — render the gradient (grain-free) into an offscreen texture.
            let sigma = max(Float(config.blur) * 36.0, 0.5)
            guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: scenePass) else {
                commandBuffer.commit(); return
            }
            encodeGradient(encoder, &uniforms, pipeline: pipeline, depthState: depthState,
                           vertexBuffer: vertexBuffer, indexBuffer: indexBuffer, colorBuffer: colorBuffer)

            // Pass 2 — Gaussian-blur scene -> blurred.
            if blurKernel == nil || blurSigma != sigma {
                let kernel = MPSImageGaussianBlur(device: device, sigma: sigma)
                kernel.edgeMode = .clamp
                blurKernel = kernel
                blurSigma = sigma
            }
            blurKernel?.encode(commandBuffer: commandBuffer, sourceTexture: scene, destinationTexture: blurred)

            // Pass 3 — composite blurred -> drawable, adding grain on top.
            let drawPass = MTLRenderPassDescriptor()
            drawPass.colorAttachments[0].texture = drawable.texture
            drawPass.colorAttachments[0].loadAction = .dontCare
            drawPass.colorAttachments[0].storeAction = .store
            guard let comp = commandBuffer.makeRenderCommandEncoder(descriptor: drawPass) else {
                commandBuffer.commit(); return
            }
            var cu = CompositeUniforms(
                resolution: SIMD2<Float>(Float(view.drawableSize.width), Float(view.drawableSize.height)),
                grain: Float(config.grain), time: elapsed)
            comp.setRenderPipelineState(compositePipeline)
            comp.setFragmentBytes(&cu, length: MemoryLayout<CompositeUniforms>.stride, index: 0)
            comp.setFragmentTexture(blurred, index: 0)
            comp.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            comp.endEncoding()
            commandBuffer.present(drawable)
            commandBuffer.commit()
        } else {
            guard let passDescriptor = msaaPass(resolvingInto: drawable.texture, clearColor: view.clearColor),
                  let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDescriptor) else {
                commandBuffer.commit()
                return
            }
            encodeGradient(encoder, &uniforms, pipeline: pipeline, depthState: depthState,
                           vertexBuffer: vertexBuffer, indexBuffer: indexBuffer, colorBuffer: colorBuffer)
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
                                _ uniforms: inout SGUniforms,
                                pipeline: MTLRenderPipelineState,
                                depthState: MTLDepthStencilState,
                                vertexBuffer: MTLBuffer,
                                indexBuffer: MTLBuffer,
                                colorBuffer: MTLBuffer) {
        encoder.setRenderPipelineState(pipeline)
        encoder.setDepthStencilState(depthState)
        encoder.setCullMode(.none)
        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<SGUniforms>.stride, index: 1)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<SGUniforms>.stride, index: 0)
        encoder.setFragmentBuffer(colorBuffer, offset: 0, index: 1)
        encoder.drawIndexedPrimitives(type: .triangle, indexCount: indexCount,
                                      indexType: .uint32, indexBuffer: indexBuffer, indexBufferOffset: 0)
        encoder.endEncoding()
    }

    /// A pass that draws into the 4x MSAA target and resolves into `target`.
    private func msaaPass(resolvingInto target: MTLTexture, clearColor: MTLClearColor) -> MTLRenderPassDescriptor? {
        guard let msaa = msaaTargets(width: target.width, height: target.height) else { return nil }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = msaa.color
        pass.colorAttachments[0].resolveTexture = target
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = clearColor
        pass.colorAttachments[0].storeAction = .multisampleResolve
        pass.depthAttachment.texture = msaa.depth
        pass.depthAttachment.loadAction = .clear
        pass.depthAttachment.clearDepth = 1.0
        pass.depthAttachment.storeAction = .dontCare
        return pass
    }

    /// Multisampled colour + depth (recreated on resize). Never stored, so on
    /// Apple GPUs they live only in tile memory.
    private func msaaTargets(width w: Int, height h: Int) -> (color: MTLTexture, depth: MTLTexture)? {
        guard w > 0, h > 0 else { return nil }
        if let c = msaaColor, let d = msaaDepth, c.width == w, c.height == h { return (c, d) }
        let storage: MTLStorageMode = device.supportsFamily(.apple1) ? .memoryless : .private
        func make(_ format: MTLPixelFormat) -> MTLTexture? {
            let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format, width: w, height: h, mipmapped: false)
            desc.textureType = .type2DMultisample
            desc.sampleCount = Self.sampleCount
            desc.usage = [.renderTarget]
            desc.storageMode = storage
            return device.makeTexture(descriptor: desc)
        }
        guard let c = make(mtkView.colorPixelFormat), let d = make(.depth32Float) else { return nil }
        msaaColor = c
        msaaDepth = d
        return (c, d)
    }

    /// Offscreen colour texture matching the drawable size (recreated on resize):
    /// the MSAA resolve target the blur reads from.
    private func sceneTexture(size: CGSize) -> MTLTexture? {
        let w = Int(size.width), h = Int(size.height)
        guard w > 0, h > 0 else { return nil }
        if let c = sceneTexture, c.width == w, c.height == h { return c }
        let cdesc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: mtkView.colorPixelFormat, width: w, height: h, mipmapped: false)
        cdesc.usage = [.renderTarget, .shaderRead]
        cdesc.storageMode = .private
        sceneTexture = device.makeTexture(descriptor: cdesc)
        return sceneTexture
    }
}
