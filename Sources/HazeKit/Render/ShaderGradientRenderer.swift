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

    // Gaussian blur post-process (only used when config.blur > 0).
    private var sceneTexture: MTLTexture?
    private var sceneDepth: MTLTexture?
    private var blurredTexture: MTLTexture?
    private var blurKernel: MPSImageGaussianBlur?
    private var blurSigma: Float = -1
    private var compositePipeline: MTLRenderPipelineState?

    private static let grid = 110   // plane subdivisions (smooth enough; ~2.1x fewer verts than 160 → lighter GPU)

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
        mtkView.depthStencilPixelFormat = .depth32Float
        mtkView.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        mtkView.clearDepth = 1.0
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
        sceneDepth = nil
        blurredTexture = nil
        blurKernel = nil
        blurSigma = -1
    }

    public func liveUpdate(_ item: ContentItem) {
        if let config = item.shaderGradient { update(config: config) }
    }

    public func redraw() { mtkView.draw() }

    /// Clear to a blend of the gradient's own colours so any uncovered edge
    /// reads as part of the gradient instead of black.
    private func updateClearColor() {
        let cs = config.resolvedColors
        let r = (cs[0].x + cs[1].x + cs[2].x) / 3
        let g = (cs[0].y + cs[1].y + cs[2].y) / 3
        let b = (cs[0].z + cs[1].z + cs[2].z) / 3
        mtkView.clearColor = MTLClearColor(red: Double(r), green: Double(g), blue: Double(b), alpha: 1)
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
            desc.depthAttachmentPixelFormat = mtkView.depthStencilPixelFormat
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
        let n = Self.grid
        var verts: [SIMD2<Float>] = []
        verts.reserveCapacity((n + 1) * (n + 1))
        for j in 0...n {
            for i in 0...n {
                let x = Float(i) / Float(n) * 2 - 1
                let y = Float(j) / Float(n) * 2 - 1
                verts.append(SIMD2<Float>(x, y))
            }
        }
        var indices: [UInt32] = []
        indices.reserveCapacity(n * n * 6)
        for j in 0..<n {
            for i in 0..<n {
                let a = UInt32(j * (n + 1) + i)
                let b = a + 1
                let c = a + UInt32(n + 1)
                let d = c + 1
                indices.append(contentsOf: [a, c, b, b, c, d])
            }
        }
        indexCount = indices.count
        vertexBuffer = device.makeBuffer(bytes: verts, length: MemoryLayout<SIMD2<Float>>.stride * verts.count, options: .storageModeShared)
        indexBuffer = device.makeBuffer(bytes: indices, length: MemoryLayout<UInt32>.stride * indices.count, options: .storageModeShared)
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
        guard let pipeline, let depthState, let colorBuffer,
              let vertexBuffer, let indexBuffer,
              let drawable = view.currentDrawable,
              let commandBuffer = commandQueue.makeCommandBuffer() else { return }

        if startTime == 0 { startTime = CACurrentMediaTime() }
        let elapsed = Float(CACurrentMediaTime() - startTime)
        var uniforms = makeUniforms(time: elapsed, drawableSize: view.drawableSize)

        if config.blur > 0,
           let scene = sceneTextures(size: view.drawableSize),
           let blurred = ensureBlurred(size: view.drawableSize),
           let compositePipeline {
            uniforms.grain = 0   // grain is added OVER the blur in the composite pass

            // Pass 1 — render the gradient (grain-free) into an offscreen texture.
            let sigma = max(Float(config.blur) * 36.0, 0.5)
            let scenePass = MTLRenderPassDescriptor()
            scenePass.colorAttachments[0].texture = scene.color
            scenePass.colorAttachments[0].loadAction = .clear
            scenePass.colorAttachments[0].clearColor = view.clearColor
            scenePass.colorAttachments[0].storeAction = .store
            scenePass.depthAttachment.texture = scene.depth
            scenePass.depthAttachment.loadAction = .clear
            scenePass.depthAttachment.clearDepth = 1.0
            scenePass.depthAttachment.storeAction = .dontCare
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
            blurKernel?.encode(commandBuffer: commandBuffer, sourceTexture: scene.color, destinationTexture: blurred)

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
            guard let passDescriptor = view.currentRenderPassDescriptor,
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

    /// Offscreen colour + depth textures matching the drawable size (recreated on resize).
    private func sceneTextures(size: CGSize) -> (color: MTLTexture, depth: MTLTexture)? {
        let w = Int(size.width), h = Int(size.height)
        guard w > 0, h > 0 else { return nil }
        if let c = sceneTexture, let d = sceneDepth, c.width == w, c.height == h { return (c, d) }
        let cdesc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: mtkView.colorPixelFormat, width: w, height: h, mipmapped: false)
        cdesc.usage = [.renderTarget, .shaderRead]
        cdesc.storageMode = .private
        let ddesc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .depth32Float, width: w, height: h, mipmapped: false)
        ddesc.usage = [.renderTarget]
        ddesc.storageMode = .private
        guard let c = device.makeTexture(descriptor: cdesc), let d = device.makeTexture(descriptor: ddesc) else { return nil }
        sceneTexture = c
        sceneDepth = d
        return (c, d)
    }

    private func makeUniforms(time: Float, drawableSize: CGSize) -> SGUniforms {
        let aspect = Float(max(drawableSize.width, 1) / max(drawableSize.height, 1))
        let fovy = radians(Float(config.fov))
        let dist = Float(config.cDistance)

        // Camera from spherical coordinates (three.js convention).
        let pol = radians(Float(config.cPolarAngle))
        let az = radians(Float(config.cAzimuthAngle))
        let eye = SIMD3<Float>(dist * sin(pol) * sin(az),
                               dist * cos(pol),
                               dist * sin(pol) * cos(az))
        let view = lookAt(eye: eye, center: .zero, up: SIMD3<Float>(0, 1, 0))
        let proj = perspective(fovy: fovy, aspect: aspect, near: 0.1, far: max(dist * 6, 100))

        // Plane scaled to cover the viewport with just enough margin for the
        // 50° roll. Position is damped so the full colour range stays in frame.
        let visHalfH = dist * tan(fovy * 0.5)
        let visHalfW = visHalfH * aspect
        let coverScale = max(visHalfW, visHalfH) * 1.6
            + Float(abs(config.positionX)) * 0.25 + Float(abs(config.positionY)) * 0.25

        let model =
            translation(Float(config.positionX) * 0.3, Float(config.positionY) * 0.3, Float(config.positionZ))
            * rotationZ(radians(Float(config.rotationZ)))
            * rotationY(radians(Float(config.rotationY)))
            * rotationX(radians(Float(config.rotationX)))
            * scale(coverScale)

        let mvp = proj * view * model

        return SGUniforms(
            mvp: mvp,
            model: model,
            time: time,
            speed: Float(config.speed),
            density: Float(config.density),
            frequency: Float(config.frequency),
            amplitude: Float(config.amplitude),
            strength: Float(config.strength),
            brightness: Float(config.brightness),
            grain: Float(config.grain),
            reflection: Float(config.reflection),
            type: config.type.shaderIndex,
            cameraPos: SIMD4<Float>(eye, 1))
    }
}

// MARK: - Matrix helpers

private func radians(_ deg: Float) -> Float { deg * .pi / 180 }

private func translation(_ x: Float, _ y: Float, _ z: Float) -> simd_float4x4 {
    simd_float4x4(columns: (
        SIMD4<Float>(1, 0, 0, 0),
        SIMD4<Float>(0, 1, 0, 0),
        SIMD4<Float>(0, 0, 1, 0),
        SIMD4<Float>(x, y, z, 1)))
}

private func scale(_ s: Float) -> simd_float4x4 {
    simd_float4x4(diagonal: SIMD4<Float>(s, s, s, 1))
}

private func rotationX(_ a: Float) -> simd_float4x4 {
    let c = cos(a), s = sin(a)
    return simd_float4x4(columns: (
        SIMD4<Float>(1, 0, 0, 0),
        SIMD4<Float>(0, c, s, 0),
        SIMD4<Float>(0, -s, c, 0),
        SIMD4<Float>(0, 0, 0, 1)))
}

private func rotationY(_ a: Float) -> simd_float4x4 {
    let c = cos(a), s = sin(a)
    return simd_float4x4(columns: (
        SIMD4<Float>(c, 0, -s, 0),
        SIMD4<Float>(0, 1, 0, 0),
        SIMD4<Float>(s, 0, c, 0),
        SIMD4<Float>(0, 0, 0, 1)))
}

private func rotationZ(_ a: Float) -> simd_float4x4 {
    let c = cos(a), s = sin(a)
    return simd_float4x4(columns: (
        SIMD4<Float>(c, s, 0, 0),
        SIMD4<Float>(-s, c, 0, 0),
        SIMD4<Float>(0, 0, 1, 0),
        SIMD4<Float>(0, 0, 0, 1)))
}

private func perspective(fovy: Float, aspect: Float, near: Float, far: Float) -> simd_float4x4 {
    let ys = 1 / tan(fovy * 0.5)
    let xs = ys / aspect
    let zs = far / (near - far)
    return simd_float4x4(columns: (
        SIMD4<Float>(xs, 0, 0, 0),
        SIMD4<Float>(0, ys, 0, 0),
        SIMD4<Float>(0, 0, zs, -1),
        SIMD4<Float>(0, 0, zs * near, 0)))
}

private func lookAt(eye: SIMD3<Float>, center: SIMD3<Float>, up: SIMD3<Float>) -> simd_float4x4 {
    let z = simd_normalize(eye - center)
    let x = simd_normalize(simd_cross(up, z))
    let y = simd_cross(z, x)
    return simd_float4x4(columns: (
        SIMD4<Float>(x.x, y.x, z.x, 0),
        SIMD4<Float>(x.y, y.y, z.y, 0),
        SIMD4<Float>(x.z, y.z, z.z, 0),
        SIMD4<Float>(-simd_dot(x, eye), -simd_dot(y, eye), -simd_dot(z, eye), 1)))
}
