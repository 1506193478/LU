//
//  LuGlassRefraction.metal
//  LU
//
//  液态玻璃的逐像素折射。iOS 16 没有 SwiftUI `layerEffect`（iOS 17+），
//  所以把玻璃背后的内容截成纹理，喂给这个 fragment shader：
//
//  1. 圆角矩形 SDF 切形状（抗锯齿、外部直接丢弃）
//  2. 用 SDF 的法线做边缘位移 —— 这才是「折射」而不是「模糊」
//  3. RGB 三通道用不同的位移倍率采样 —— 色散（chromatic aberration）
//  4. 位移后再做一次 5 tap 模糊 —— 磨砂层
//  5. 法线·光照做镜面高光，边缘 1px 提亮做玻璃壁
//

#include <metal_stdlib>
using namespace metal;

struct GlassUniforms {
    float2 size;          // 视图像素尺寸
    float  cornerRadius;  // 圆角半径（像素）
    float  refraction;    // 边缘位移强度（像素）
    float  aberration;    // 色散强度 0…1
    float  frost;         // 磨砂 0…1
    float  specular;      // 高光强度
    float  border;        // 玻璃壁宽度（像素）
    float  saturation;    // 饱和度（1 = 原样）
    float4 tint;          // 着色（alpha 为混合比例）
};

struct VertexOut {
    float4 position [[position]];
    float2 uv;
};

vertex VertexOut glass_vertex(uint vid [[vertex_id]]) {
    const float2 quad[4] = {
        float2(-1.0, -1.0), float2(1.0, -1.0),
        float2(-1.0,  1.0), float2(1.0,  1.0)
    };
    VertexOut out;
    out.position = float4(quad[vid], 0.0, 1.0);
    out.uv = float2((quad[vid].x + 1.0) * 0.5, (1.0 - quad[vid].y) * 0.5);
    return out;
}

static inline float roundedBoxSDF(float2 p, float2 halfSize, float radius) {
    float2 q = abs(p) - (halfSize - radius);
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius;
}

static inline float2 sdfNormal(float2 p, float2 halfSize, float radius) {
    const float e = 0.75;
    float dx = roundedBoxSDF(p + float2(e, 0.0), halfSize, radius)
             - roundedBoxSDF(p - float2(e, 0.0), halfSize, radius);
    float dy = roundedBoxSDF(p + float2(0.0, e), halfSize, radius)
             - roundedBoxSDF(p - float2(0.0, e), halfSize, radius);
    float2 n = float2(dx, dy);
    float len = max(length(n), 0.0001);
    return n / len;
}

fragment float4 glass_fragment(VertexOut in [[stage_in]],
                               texture2d<float> src [[texture(0)]],
                               constant GlassUniforms &u [[buffer(0)]]) {
    constexpr sampler linearSampler(coord::normalized,
                                    filter::linear,
                                    address::clamp_to_edge);

    float2 p = in.uv * u.size;
    float2 halfSize = u.size * 0.5;
    float radius = min(u.cornerRadius, min(halfSize.x, halfSize.y));
    float d = roundedBoxSDF(p - halfSize, halfSize - 0.5, radius);

    // 1px 抗锯齿：外部丢弃，边缘渐隐
    if (d > 1.0) discard_fragment();
    float alpha = saturate(1.0 - d);

    // 边缘权重：贴着轮廓最强，往内迅速衰减
    float edge = saturate(1.0 - (-d) / max(u.border * 2.5, 1.0));
    float bend = edge * edge;

    float2 n = sdfNormal(p - halfSize, halfSize - 0.5, radius);
    float2 disp = n * bend * u.refraction / max(u.size, float2(1.0));

    // 2 + 3 位移采样，RGB 分开算色散
    float rScale = 1.0 + u.aberration * 0.55;
    float bScale = 1.0 - u.aberration * 0.55;
    float3 color;
    color.r = src.sample(linearSampler, in.uv + disp * rScale).r;
    color.g = src.sample(linearSampler, in.uv + disp).g;
    color.b = src.sample(linearSampler, in.uv + disp * bScale).b;

    // 4 磨砂：5 tap 十字模糊，随 frost 加大半径
    if (u.frost > 0.01) {
        float2 stepSize = u.frost * 5.0 / max(u.size, float2(1.0));
        float3 acc = color * 2.0;
        acc += src.sample(linearSampler, in.uv + disp + float2(stepSize.x, 0.0)).rgb;
        acc += src.sample(linearSampler, in.uv + disp - float2(stepSize.x, 0.0)).rgb;
        acc += src.sample(linearSampler, in.uv + disp + float2(0.0, stepSize.y)).rgb;
        acc += src.sample(linearSampler, in.uv + disp - float2(0.0, stepSize.y)).rgb;
        color = acc / 6.0;
    }

    // 着色
    float luma = dot(color, float3(0.2126, 0.7152, 0.0722));
    color = mix(float3(luma), color, max(u.saturation, 0.0));
    color = mix(color, u.tint.rgb, saturate(u.tint.a));

    // 5 镜面高光：左上打光，只有斜面（边缘）才亮
    float3 lightDir = normalize(float3(-0.45, 0.78, 0.85));
    float3 normal = normalize(float3(n.x, -n.y, 0.9));
    float spec = pow(max(dot(normal, lightDir), 0.0), 4.0);
    color += spec * bend * u.specular;

    // 玻璃壁：轮廓内侧 1px 提亮，下方压暗制造厚度
    float wall = saturate(1.0 - (-d) / max(u.border, 0.5));
    color += wall * 0.20;
    color -= saturate((p.y / max(u.size.y, 1.0)) - 0.72) * wall * 0.18;

    return float4(color, alpha);
}
