import simd

/// CPU-side mirror of `Uniforms` in Shaders.metal. Field order is identical and
/// `resolution` (SIMD2) is first, so the two structs have matching memory
/// layout (stride 40) with no manual padding.
struct GradientUniforms {
    var resolution: SIMD2<Float>
    var time: Float
    var speed: Float
    var grain: Float
    var warp: Float
    var brightness: Float
    var colorCount: Int32
    var style: Int32
}
