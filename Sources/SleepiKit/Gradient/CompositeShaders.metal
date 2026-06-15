#include <metal_stdlib>
using namespace metal;

// Shared by both gradient renderers: samples an already-rendered (and possibly
// blurred) texture and adds film grain ON TOP, so grain stays visible even at
// maximum blur. Layout matches CompositeUniforms in Swift.
struct CompositeUniforms {
    float2 resolution;
    float grain;
    float time;
};

struct CompOut {
    float4 position [[position]];
    float2 uv;
};

vertex CompOut composite_vertex(uint vid [[vertex_id]]) {
    float2 verts[3] = { float2(-1.0, -1.0), float2(3.0, -1.0), float2(-1.0, 3.0) };
    CompOut out;
    float2 p = verts[vid];
    out.position = float4(p, 0.0, 1.0);
    out.uv = p * 0.5 + 0.5;
    return out;
}

float comp_hash13(float3 p3) {
    p3 = fract(p3 * 0.1031);
    p3 += dot(p3, float3(p3.z, p3.y, p3.x) + 31.32);
    return fract((p3.x + p3.y) * p3.z);
}

fragment float4 composite_grain_fragment(CompOut in [[stage_in]],
                                         constant CompositeUniforms &u [[buffer(0)]],
                                         texture2d<float> src [[texture(0)]]) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    float3 col = src.sample(s, in.uv).rgb;
    if (u.grain > 0.001) {
        float g = comp_hash13(float3(in.position.xy, floor(u.time * 24.0))) - 0.5;
        col += g * u.grain * 0.16;
    }
    return float4(clamp(col, 0.0, 1.0), 1.0);
}
