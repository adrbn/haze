import CoreGraphics
import Foundation
import Metal
import MetalPerformanceShaders
import simd

/// Renders one still frame of a gradient offscreen, through the *same* shaders
/// and matrices the live wallpaper uses.
///
/// This still becomes the macOS desktop picture. macOS reads that picture — not
/// the live wallpaper window — to decide the menu bar's light/dark treatment and
/// whether to draw its pale legibility backdrop across the top of the screen, so
/// a stand-in that only approximates the colours can make it choose a treatment
/// that clashes with what the user is actually looking at.
///
/// Deliberately free of `MTKView`: posters are generated off the main thread,
/// where AppKit views may not be created.
public enum GradientSnapshot {
    /// The frame to render when no better one can be chosen. It is the frame the
    /// renderer itself starts on, so it is never *unlike* the wallpaper — but it
    /// is not automatically a good still; see `bestStillTime`.
    public static let stillTime: Float = 0

    /// Bumped whenever the renderer changes what a given config draws. Posters
    /// are cached under a filename derived from the config alone, so without
    /// this an upgrade would leave the previous image sitting under the name
    /// macOS has already been told to use.
    public static let revision = 3

    /// Names the still a config produces, for use as a poster filename.
    public static func signature(of config: some Encodable) -> String {
        "r\(revision)|" + ContentSignature.of(config)
    }

    private static let format: MTLPixelFormat = .bgra8Unorm

    // MARK: - Shadergradient surface

    /// `time` pins a specific frame; left out, the smoothest of several
    /// candidates is chosen — a frozen fold silhouette is the one thing that
    /// reads as a defect in a poster. See `StillFrame`.
    public static func image(config: ShaderGradientConfig, size: CGSize, time: Float? = nil) -> CGImage? {
        guard let (width, height) = pixelSize(size), let gpu = Context() else { return nil }
        let drawableSize = CGSize(width: width, height: height)
        let time = time ?? bestStillTime(config: config, gpu: gpu)

        guard let mesh = SGGeometry.mesh(device: gpu.device),
              let surface = gpu.pipeline(vertex: "sg_vertex", fragment: "sg_fragment", depth: true),
              let depthState = gpu.depthState(),
              let depth = gpu.texture(.depth32Float, width, height, usage: .renderTarget),
              let target = gpu.texture(format, width, height, usage: [.renderTarget, .shaderRead]),
              let colors = gpu.buffer(config.resolvedColors),
              let commands = gpu.queue.makeCommandBuffer()
        else { return nil }

        var uniforms = SGGeometry.uniforms(config: config, time: time, drawableSize: drawableSize)
        let clear = SGGeometry.clearColor(for: config)

        if config.blur > 0,
           let scene = gpu.texture(format, width, height, usage: [.renderTarget, .shaderRead]),
           let blurred = gpu.texture(format, width, height, usage: [.shaderRead, .shaderWrite]),
           let composite = gpu.pipeline(vertex: "composite_vertex", fragment: "composite_grain_fragment") {
            uniforms.grain = 0   // grain is added OVER the blur, in the composite pass
            encodeSurface(into: scene, depth: depth, clear: clear, commands: commands,
                          pipeline: surface, depthState: depthState, mesh: mesh,
                          colors: colors, uniforms: &uniforms)
            gpu.blur(config.blur, from: scene, to: blurred, commands: commands)
            encodeComposite(into: target, source: blurred, pipeline: composite, commands: commands,
                            size: drawableSize, grain: Float(config.grain), time: time)
        } else {
            encodeSurface(into: target, depth: depth, clear: clear, commands: commands,
                          pipeline: surface, depthState: depthState, mesh: mesh,
                          colors: colors, uniforms: &uniforms)
        }

        return gpu.readBack(target, commands: commands)
    }

    // MARK: - Choosing the frame

    /// Pick which frame of the animation to freeze.
    ///
    /// Renders `StillFrame.candidates` small and keeps the one with the softest
    /// edges. Film grain is turned off for the scoring passes only — it is noise
    /// to the measurement, and the winning time is re-rendered in full with the
    /// config untouched. Deterministic, so a config still names one poster.
    ///
    /// Falls back to `stillTime` if the GPU cannot be set up; `stillTime` is
    /// also among the candidates, so the result is never worse than it.
    private static func bestStillTime(config: ShaderGradientConfig, gpu: Context) -> Float {
        guard let (width, height) = pixelSize(StillFrame.scoringSize),
              let mesh = SGGeometry.mesh(device: gpu.device),
              let pipeline = gpu.pipeline(vertex: "sg_vertex", fragment: "sg_fragment", depth: true),
              let depthState = gpu.depthState(),
              let depth = gpu.texture(.depth32Float, width, height, usage: .renderTarget),
              let target = gpu.texture(format, width, height, usage: [.renderTarget, .shaderRead]),
              let colors = gpu.buffer(config.resolvedColors)
        else { return stillTime }

        let clear = SGGeometry.clearColor(for: config)
        let drawableSize = CGSize(width: width, height: height)
        var best = stillTime
        var bestScore = Float.greatestFiniteMagnitude

        for candidate in StillFrame.candidates {
            guard let commands = gpu.queue.makeCommandBuffer() else { continue }
            var uniforms = SGGeometry.uniforms(config: config, time: candidate, drawableSize: drawableSize)
            uniforms.grain = 0
            encodeSurface(into: target, depth: depth, clear: clear, commands: commands,
                          pipeline: pipeline, depthState: depthState, mesh: mesh,
                          colors: colors, uniforms: &uniforms)
            guard let bytes = gpu.bytes(of: target, commands: commands) else { continue }
            let score = StillFrame.discontinuity(bgra: bytes, width: width, height: height)
            if score < bestScore {
                bestScore = score
                best = candidate
            }
        }
        Log.render.debug("Poster still: t=\(best, privacy: .public) (edge \(bestScore, privacy: .public))")
        return best
    }

    // MARK: - Classic 2D gradient

    public static func image(config: GradientConfig, size: CGSize, time: Float = stillTime) -> CGImage? {
        guard let (width, height) = pixelSize(size), let gpu = Context() else { return nil }
        let resolution = SIMD2<Float>(Float(width), Float(height))
        let resolved = config.resolvedColors

        guard let field = gpu.pipeline(vertex: "haze_gradient_vertex", fragment: "haze_gradient_fragment"),
              let target = gpu.texture(format, width, height, usage: [.renderTarget, .shaderRead]),
              let colors = gpu.buffer(resolved),
              let commands = gpu.queue.makeCommandBuffer()
        else { return nil }

        var uniforms = GradientUniforms(
            resolution: resolution, time: time,
            speed: Float(config.speed), grain: Float(config.grain), warp: Float(config.warp),
            brightness: Float(config.brightness), colorCount: Int32(resolved.count),
            style: Int32(config.style.shaderIndex))

        if config.blur > 0,
           let scene = gpu.texture(format, width, height, usage: [.renderTarget, .shaderRead]),
           let blurred = gpu.texture(format, width, height, usage: [.shaderRead, .shaderWrite]),
           let composite = gpu.pipeline(vertex: "composite_vertex", fragment: "composite_grain_fragment") {
            uniforms.grain = 0
            encodeField(into: scene, commands: commands, pipeline: field, colors: colors, uniforms: &uniforms)
            gpu.blur(config.blur, from: scene, to: blurred, commands: commands)
            encodeComposite(into: target, source: blurred, pipeline: composite, commands: commands,
                            size: CGSize(width: width, height: height),
                            grain: Float(config.grain), time: time)
        } else {
            encodeField(into: target, commands: commands, pipeline: field, colors: colors, uniforms: &uniforms)
        }

        return gpu.readBack(target, commands: commands)
    }

    // MARK: - Passes

    private static func encodeSurface(into target: MTLTexture, depth: MTLTexture, clear: MTLClearColor,
                                      commands: MTLCommandBuffer, pipeline: MTLRenderPipelineState,
                                      depthState: MTLDepthStencilState, mesh: SGGeometry.Mesh,
                                      colors: MTLBuffer, uniforms: inout SGUniforms) {
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = clear
        pass.colorAttachments[0].storeAction = .store
        pass.depthAttachment.texture = depth
        pass.depthAttachment.loadAction = .clear
        pass.depthAttachment.clearDepth = 1.0
        pass.depthAttachment.storeAction = .dontCare
        guard let encoder = commands.makeRenderCommandEncoder(descriptor: pass) else { return }
        encoder.setRenderPipelineState(pipeline)
        encoder.setDepthStencilState(depthState)
        encoder.setCullMode(.none)
        encoder.setVertexBuffer(mesh.vertices, offset: 0, index: 0)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<SGUniforms>.stride, index: 1)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<SGUniforms>.stride, index: 0)
        encoder.setFragmentBuffer(colors, offset: 0, index: 1)
        encoder.drawIndexedPrimitives(type: .triangle, indexCount: mesh.indexCount,
                                      indexType: .uint32, indexBuffer: mesh.indices, indexBufferOffset: 0)
        encoder.endEncoding()
    }

    private static func encodeField(into target: MTLTexture, commands: MTLCommandBuffer,
                                    pipeline: MTLRenderPipelineState, colors: MTLBuffer,
                                    uniforms: inout GradientUniforms) {
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .dontCare
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = commands.makeRenderCommandEncoder(descriptor: pass) else { return }
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<GradientUniforms>.stride, index: 0)
        encoder.setFragmentBuffer(colors, offset: 0, index: 1)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
    }

    private static func encodeComposite(into target: MTLTexture, source: MTLTexture,
                                        pipeline: MTLRenderPipelineState, commands: MTLCommandBuffer,
                                        size: CGSize, grain: Float, time: Float) {
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .dontCare
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = commands.makeRenderCommandEncoder(descriptor: pass) else { return }
        var uniforms = CompositeUniforms(
            resolution: SIMD2<Float>(Float(size.width), Float(size.height)), grain: grain, time: time)
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<CompositeUniforms>.stride, index: 0)
        encoder.setFragmentTexture(source, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
    }

    private static func pixelSize(_ size: CGSize) -> (Int, Int)? {
        let width = Int(size.width.rounded()), height = Int(size.height.rounded())
        guard width > 0, height > 0 else { return nil }
        return (width, height)
    }

    // MARK: - GPU scaffolding

    /// A one-shot Metal context. Poster generation happens a handful of times per
    /// session, so nothing here is worth caching across calls.
    private struct Context {
        let device: MTLDevice
        let queue: MTLCommandQueue
        let library: MTLLibrary

        init?() {
            guard let device = MTLCreateSystemDefaultDevice(),
                  let queue = device.makeCommandQueue(),
                  let library = try? device.makeDefaultLibrary(bundle: Bundle(for: ShaderGradientRenderer.self))
            else {
                Log.render.error("Snapshot: no Metal device / shader library")
                return nil
            }
            self.device = device
            self.queue = queue
            self.library = library
        }

        func pipeline(vertex: String, fragment: String, depth: Bool = false) -> MTLRenderPipelineState? {
            let desc = MTLRenderPipelineDescriptor()
            desc.vertexFunction = library.makeFunction(name: vertex)
            desc.fragmentFunction = library.makeFunction(name: fragment)
            desc.colorAttachments[0].pixelFormat = GradientSnapshot.format
            if depth { desc.depthAttachmentPixelFormat = .depth32Float }
            do {
                return try device.makeRenderPipelineState(descriptor: desc)
            } catch {
                Log.render.error("Snapshot pipeline '\(fragment, privacy: .public)' failed: \(error.localizedDescription, privacy: .public)")
                return nil
            }
        }

        func depthState() -> MTLDepthStencilState? {
            let desc = MTLDepthStencilDescriptor()
            desc.depthCompareFunction = .less
            desc.isDepthWriteEnabled = true
            return device.makeDepthStencilState(descriptor: desc)
        }

        func texture(_ pixelFormat: MTLPixelFormat, _ width: Int, _ height: Int,
                     usage: MTLTextureUsage) -> MTLTexture? {
            let desc = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: pixelFormat, width: width, height: height, mipmapped: false)
            desc.usage = usage
            desc.storageMode = .private
            return device.makeTexture(descriptor: desc)
        }

        func buffer(_ colors: [SIMD4<Float>]) -> MTLBuffer? {
            device.makeBuffer(bytes: colors,
                              length: MemoryLayout<SIMD4<Float>>.stride * colors.count,
                              options: .storageModeShared)
        }

        func blur(_ amount: Double, from source: MTLTexture, to destination: MTLTexture,
                  commands: MTLCommandBuffer) {
            let kernel = MPSImageGaussianBlur(device: device, sigma: max(Float(amount) * 36.0, 0.5))
            kernel.edgeMode = .clamp
            kernel.encode(commandBuffer: commands, sourceTexture: source, destinationTexture: destination)
        }

        /// Commit, wait, and copy the private render target into CPU-visible memory.
        /// The staging copy keeps this correct on discrete GPUs, where a render
        /// target cannot be read directly.
        func bytes(of target: MTLTexture, commands: MTLCommandBuffer) -> [UInt8]? {
            let width = target.width, height = target.height
            let desc = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: target.pixelFormat, width: width, height: height, mipmapped: false)
            desc.usage = .shaderRead
            desc.storageMode = .shared
            guard let staging = device.makeTexture(descriptor: desc),
                  let blit = commands.makeBlitCommandEncoder() else { return nil }
            blit.copy(from: target, sourceSlice: 0, sourceLevel: 0,
                      sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                      sourceSize: MTLSize(width: width, height: height, depth: 1),
                      to: staging, destinationSlice: 0, destinationLevel: 0,
                      destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
            blit.endEncoding()
            commands.commit()
            commands.waitUntilCompleted()

            let bytesPerRow = width * 4
            var bytes = [UInt8](repeating: 0, count: bytesPerRow * height)
            staging.getBytes(&bytes, bytesPerRow: bytesPerRow,
                             from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
            return bytes
        }

        func readBack(_ target: MTLTexture, commands: MTLCommandBuffer) -> CGImage? {
            let width = target.width, height = target.height
            let bytesPerRow = width * 4
            guard let bytes = bytes(of: target, commands: commands) else { return nil }

            // bgra8Unorm little-endian is CoreGraphics' 32-bit-little / alpha-first.
            let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue
                                    | CGBitmapInfo.byteOrder32Little.rawValue)
            guard let provider = CGDataProvider(data: Data(bytes) as CFData),
                  let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
            return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                           bytesPerRow: bytesPerRow, space: space, bitmapInfo: info,
                           provider: provider, decode: nil, shouldInterpolate: false,
                           intent: .defaultIntent)
        }
    }
}
