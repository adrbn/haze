#include <metal_stdlib>
using namespace metal;

// Layout MUST match GradientUniforms in GradientUniforms.swift.
// resolution (float2) is first so neither side inserts padding.
struct Uniforms {
    float2 resolution;
    float time;
    float speed;
    float grain;
    float warp;
    float brightness;
    int colorCount;
    int style;        // 0 aurora, 1 liquid, 2 halo
};

struct VSOut {
    float4 position [[position]];
    float2 uv;
};

// Fullscreen triangle — no vertex buffer needed.
vertex VSOut sleepi_gradient_vertex(uint vid [[vertex_id]]) {
    float2 verts[3] = { float2(-1.0, -1.0), float2(3.0, -1.0), float2(-1.0, 3.0) };
    VSOut out;
    float2 p = verts[vid];
    out.position = float4(p, 0.0, 1.0);
    out.uv = p * 0.5 + 0.5;
    return out;
}

float hash21(float2 p) {
    p = fract(p * float2(123.34, 345.45));
    p += dot(p, p + 34.345);
    return fract(p.x * p.y);
}

// High-quality hash (Dave Hoskins) — even distribution with no banding,
// stable for large pixel coordinates. Used for film grain.
float hash12(float2 p) {
    float3 p3 = fract(float3(p.x, p.y, p.x) * 0.1031);
    p3 += dot(p3, float3(p3.y, p3.z, p3.x) + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

float vnoise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    float a = hash21(i);
    float b = hash21(i + float2(1.0, 0.0));
    float c = hash21(i + float2(0.0, 1.0));
    float d = hash21(i + float2(1.0, 1.0));
    float2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm(float2 p) {
    float v = 0.0;
    float amp = 0.5;
    float2x2 rot = float2x2(0.80, -0.60, 0.60, 0.80);
    for (int i = 0; i < 5; i++) {
        v += amp * vnoise(p);
        p = rot * p * 2.0;
        amp *= 0.5;
    }
    return v;
}

float3 paletteColor(float t, constant float4 *colors, int count) {
    t = clamp(t, 0.0, 1.0);
    float scaled = t * float(count - 1);
    int idx = int(floor(scaled));
    idx = clamp(idx, 0, count - 2);
    float f = smoothstep(0.0, 1.0, scaled - float(idx));
    return mix(colors[idx].rgb, colors[idx + 1].rgb, f);
}

fragment float4 sleepi_gradient_fragment(VSOut in [[stage_in]],
                                         constant Uniforms &u [[buffer(0)]],
                                         constant float4 *colors [[buffer(1)]]) {
    float aspect = u.resolution.x / max(u.resolution.y, 1.0);
    float2 p = in.uv;
    p.x *= aspect;
    float t = u.time * max(u.speed, 0.0);

    // Domain warp for organic flow.
    float2 q = float2(fbm(p * 2.0 + float2(0.0, t * 0.20)),
                      fbm(p * 2.0 + float2(5.2, 1.3) - t * 0.15));
    float2 warped = p + (q - 0.5) * u.warp;

    float field;
    if (u.style == 2) {                 // halo
        float2 center = float2(0.5 * aspect + 0.18 * sin(t * 0.6),
                               0.5 + 0.16 * cos(t * 0.5));
        float r = distance(warped, center);
        field = fbm(warped * 3.0 + t * 0.1) * 0.55 + (1.0 - smoothstep(0.0, 0.95, r)) * 0.6;
    } else if (u.style == 1) {          // liquid
        float n = fbm(warped * 3.5 + float2(t * 0.25, -t * 0.18));
        field = n + 0.22 * sin(warped.x * 6.0 + t);
    } else {                            // aurora
        float n = fbm(warped * 2.5 + float2(t * 0.12, t * 0.08));
        field = n + 0.18 * sin((warped.y + n) * 4.0 + t * 0.5);
    }
    field = clamp(field, 0.0, 1.0);

    float3 col = paletteColor(field, colors, max(u.colorCount, 2));
    col *= u.brightness;

    // Film grain — high-quality hash, stepped ~24x/sec so it doesn't crawl
    // per frame. Scaled by luminance so highlights stay clean.
    float2 grainCoord = in.position.xy + floor(u.time * 24.0) * 17.0;
    float g = hash12(grainCoord) - 0.5;
    col += g * u.grain;

    return float4(clamp(col, 0.0, 1.0), 1.0);
}
