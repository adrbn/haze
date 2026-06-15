#include <metal_stdlib>
using namespace metal;

// Layout MUST match SGUniforms in ShaderGradientRenderer.swift.
struct SGUniforms {
    float4x4 mvp;
    float4x4 model;
    float time;
    float speed;
    float density;
    float frequency;
    float amplitude;
    float strength;
    float brightness;
    float grain;
    float reflection;
    int type;          // 0 plane, 1 waterPlane, 2 sphere
    float4 cameraPos;  // xyz used
};

struct SGOut {
    float4 position [[position]];
    float2 uv;
    float disp;
    float3 normal;
    float3 worldPos;
};

// ---- Ashima 3D simplex noise ----
float3 sg_mod289(float3 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
float4 sg_mod289(float4 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
float4 sg_permute(float4 x) { return sg_mod289(((x * 34.0) + 1.0) * x); }
float4 sg_taylorInvSqrt(float4 r) { return 1.79284291400159 - 0.85373472095314 * r; }

float snoise(float3 v) {
    const float2 C = float2(1.0 / 6.0, 1.0 / 3.0);
    const float4 D = float4(0.0, 0.5, 1.0, 2.0);
    float3 i  = floor(v + dot(v, C.yyy));
    float3 x0 = v - i + dot(i, C.xxx);
    float3 g = step(x0.yzx, x0.xyz);
    float3 l = 1.0 - g;
    float3 i1 = min(g.xyz, l.zxy);
    float3 i2 = max(g.xyz, l.zxy);
    float3 x1 = x0 - i1 + C.xxx;
    float3 x2 = x0 - i2 + C.yyy;
    float3 x3 = x0 - D.yyy;
    i = sg_mod289(i);
    float4 p = sg_permute(sg_permute(sg_permute(
        i.z + float4(0.0, i1.z, i2.z, 1.0)) +
        i.y + float4(0.0, i1.y, i2.y, 1.0)) +
        i.x + float4(0.0, i1.x, i2.x, 1.0));
    float n_ = 0.142857142857;
    float3 ns = n_ * D.wyz - D.xzx;
    float4 j = p - 49.0 * floor(p * ns.z * ns.z);
    float4 x_ = floor(j * ns.z);
    float4 y_ = floor(j - 7.0 * x_);
    float4 x = x_ * ns.x + ns.yyyy;
    float4 y = y_ * ns.x + ns.yyyy;
    float4 h = 1.0 - abs(x) - abs(y);
    float4 b0 = float4(x.xy, y.xy);
    float4 b1 = float4(x.zw, y.zw);
    float4 s0 = floor(b0) * 2.0 + 1.0;
    float4 s1 = floor(b1) * 2.0 + 1.0;
    float4 sh = -step(h, float4(0.0));
    float4 a0 = b0.xzyw + s0.xzyw * sh.xxyy;
    float4 a1 = b1.xzyw + s1.xzyw * sh.zzww;
    float3 p0 = float3(a0.xy, h.x);
    float3 p1 = float3(a0.zw, h.y);
    float3 p2 = float3(a1.xy, h.z);
    float3 p3 = float3(a1.zw, h.w);
    float4 norm = sg_taylorInvSqrt(float4(dot(p0, p0), dot(p1, p1), dot(p2, p2), dot(p3, p3)));
    p0 *= norm.x; p1 *= norm.y; p2 *= norm.z; p3 *= norm.w;
    float4 m = max(0.6 - float4(dot(x0, x0), dot(x1, x1), dot(x2, x2), dot(x3, x3)), 0.0);
    m = m * m;
    return 42.0 * dot(m * m, float4(dot(p0, x0), dot(p1, x1), dot(p2, x2), dot(p3, x3)));
}

float sg_hash(float2 p) {
    float3 p3 = fract(float3(p.x, p.y, p.x) * 0.1031);
    p3 += dot(p3, float3(p3.y, p3.z, p3.x) + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

// Surface displacement (along the plane normal / Z in local space).
float sg_displace(float2 p, constant SGUniforms &u) {
    float t = u.time * u.speed;
    float n = snoise(float3(p * u.density + float2(0.0, t * 0.3), t * 0.5));
    float d = n * u.strength * 0.1;
    if (u.type == 1) { // waterPlane ripples
        d += (sin(p.x * u.frequency + t) * 0.5 + cos(p.y * u.frequency * 0.8 - t) * 0.5) * u.amplitude * 0.06;
    }
    return d;
}

vertex SGOut sg_vertex(uint vid [[vertex_id]],
                       const device float2 *positions [[buffer(0)]],
                       constant SGUniforms &u [[buffer(1)]]) {
    float2 p = positions[vid];
    float disp = sg_displace(p, u);
    float3 local = float3(p, disp);

    // Normal via finite differences of the height field.
    float eps = 0.015;
    float dx = sg_displace(p + float2(eps, 0.0), u) - disp;
    float dy = sg_displace(p + float2(0.0, eps), u) - disp;
    float3 n = normalize(float3(-dx, -dy, eps));

    SGOut o;
    o.position = u.mvp * float4(local, 1.0);
    o.uv = p * 0.5 + 0.5;
    o.disp = disp;
    o.normal = normalize((u.model * float4(n, 0.0)).xyz);
    o.worldPos = (u.model * float4(local, 1.0)).xyz;
    return o;
}

fragment float4 sg_fragment(SGOut in [[stage_in]],
                            constant SGUniforms &u [[buffer(0)]],
                            constant float4 *colors [[buffer(1)]]) {
    float3 c1 = colors[0].rgb, c2 = colors[1].rgb, c3 = colors[2].rgb;

    // Three-stop colour across the surface. Expand around the centre so all
    // three colours stay visible through the camera crop, and let the noise
    // displacement marble the colour boundaries (the silky shadergradient feel).
    float marble = in.disp * 1.4;
    float ty = clamp((in.uv.y - 0.5) * 1.5 + 0.5 + marble, 0.0, 1.0);
    float3 col = ty < 0.5 ? mix(c1, c2, smoothstep(0.0, 0.5, ty))
                          : mix(c2, c3, smoothstep(0.5, 1.0, ty));

    // 3D lighting — flip the normal toward the camera (the plane is two-sided).
    float3 V = normalize(u.cameraPos.xyz - in.worldPos);
    float3 N = normalize(in.normal);
    if (dot(N, V) < 0.0) { N = -N; }
    float3 L = normalize(float3(0.35, 0.7, 0.55));
    float diff = clamp(dot(N, L), 0.0, 1.0);
    col *= (0.72 + 0.5 * diff) * u.brightness;

    // Soft reflective rim.
    float fres = pow(1.0 - clamp(dot(N, V), 0.0, 1.0), 3.0);
    col += fres * u.reflection;

    // Film grain.
    if (u.grain > 0.001) {
        float g = sg_hash(in.position.xy + floor(u.time * 24.0) * 17.0) - 0.5;
        col += g * u.grain * 0.16;
    }

    return float4(clamp(col, 0.0, 1.0), 1.0);
}
