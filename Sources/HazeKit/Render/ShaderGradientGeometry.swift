import Metal
import simd

/// The view-free half of the shadergradient surface: the subdivided plane and the
/// camera/model matrices fed to `sg_vertex`.
///
/// Shared by the live renderer and the offscreen poster snapshot, so a still can
/// never drift from what the wallpaper actually draws.
enum SGGeometry {
    /// Plane subdivisions. Fold silhouettes follow the mesh edges, so too coarse a
    /// grid shows them as polylines. Vertex work is negligible next to fill.
    static let grid = 192

    struct Mesh {
        let vertices: MTLBuffer
        let indices: MTLBuffer
        let indexCount: Int
    }

    /// A unit plane in [-1, 1]², triangulated. Displacement happens in the shader.
    static func mesh(device: MTLDevice) -> Mesh? {
        let n = grid
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
        guard let vertexBuffer = device.makeBuffer(bytes: verts,
                                                   length: MemoryLayout<SIMD2<Float>>.stride * verts.count,
                                                   options: .storageModeShared),
              let indexBuffer = device.makeBuffer(bytes: indices,
                                                  length: MemoryLayout<UInt32>.stride * indices.count,
                                                  options: .storageModeShared)
        else { return nil }
        return Mesh(vertices: vertexBuffer, indices: indexBuffer, indexCount: indices.count)
    }

    static func uniforms(config: ShaderGradientConfig, time: Float, drawableSize: CGSize) -> SGUniforms {
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

        return SGUniforms(
            mvp: proj * view * model,
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

    /// Clear to a blend of the gradient's own colours, so any uncovered edge reads
    /// as part of the gradient instead of black.
    static func clearColor(for config: ShaderGradientConfig) -> MTLClearColor {
        let cs = config.resolvedColors
        return MTLClearColor(red: Double((cs[0].x + cs[1].x + cs[2].x) / 3),
                             green: Double((cs[0].y + cs[1].y + cs[2].y) / 3),
                             blue: Double((cs[0].z + cs[1].z + cs[2].z) / 3),
                             alpha: 1)
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
