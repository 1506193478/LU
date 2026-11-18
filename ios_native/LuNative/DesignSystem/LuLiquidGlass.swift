import SwiftUI

/// 液态玻璃。
///
/// 两级实现，按能力自动降级：
///
/// **A. Metal 逐像素折射**（`LuMetalGlass.swift` + `LuGlassRefraction.metal`）
/// iOS 16 没有 iOS 17 的 `layerEffect`，所以走「抓底层纹理 → 自写 fragment shader」：
/// 圆角矩形 SDF 切形状，用 SDF 法线做边缘位移（真折射，不是模糊），
/// RGB 三通道不同倍率采样做色散，再叠磨砂、镜面高光与玻璃壁。
///
/// **B. 材质兜底**（`UIVisualEffectView` + 渐变高光 + 描边）
/// Metal 不可用、或调用方显式 `refraction: 0` 时使用。
///
/// 视觉参数对齐两个 Web 实现（`rdev/liquid-glass-react`、`CruxGarden/plasma-ui`）：
/// `frost` ↔ `blurAmount`、`aberration` ↔ `aberrationIntensity`、
/// `refraction` ↔ 位移贴图强度、按下缩放 ↔ `elasticity`。
/// 两个库本身是 React + WebGL，二进制层面链不进 SwiftUI，只能照配方重搭。
struct LuLiquidGlass<Content: View>: View {
    var cornerRadius: CGFloat = 24
    /// 0 = 通透，1 = 磨砂
    var frost: Double = 0.45
    /// 显色强度
    var saturation: Double = 1.35
    /// 边缘色散 0…1
    var aberration: Double = 0.45
    /// 着色
    var tint: Color = .clear
    /// 边缘折射强度（像素）。0 = 关掉 Metal，走材质版
    var refraction: CGFloat = 14
    @ViewBuilder var content: () -> Content

    private var material: Material {
        if frost < 0.34 { return .ultraThinMaterial }
        if frost < 0.67 { return .thinMaterial }
        return .regularMaterial
    }

    private var highlightOpacity: Double {
        0.18 + frost * 0.16
    }

    var body: some View {
        content()
            .background {
                if refraction > 0.5, LuGlassRenderer.shared.isReady {
                    LuMetalGlassBackground(style: LuGlassStyle(
                        cornerRadius: cornerRadius,
                        refraction: refraction,
                        aberration: aberration,
                        frost: frost,
                        specular: 0.55,
                        border: 1.2,
                        saturation: saturation,
                        tint: tint
                    ))
                    .allowsHitTesting(false)
                } else {
                    fallbackLayers
                }
            }
            .compositingGroup()
    }

    // MARK: 材质兜底

    private var fallbackLayers: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return ZStack {
            shape
                .fill(material)
                .saturation(saturation)

            if tint != .clear {
                shape.fill(tint)
            }

            // 边缘折射带：内侧一圈渐变白边，模糊后像玻璃壁的厚度
            shape
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.34),
                            Color.white.opacity(0.06),
                            Color.white.opacity(0.20)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 12
                )
                .blur(radius: 7)
                .mask(shape)
                .allowsHitTesting(false)

            // 镜面高光
            shape
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(highlightOpacity),
                            Color.white.opacity(highlightOpacity * 0.25),
                            Color.clear
                        ],
                        startPoint: UnitPoint(x: 0.15, y: 0),
                        endPoint: UnitPoint(x: 0.55, y: 0.75)
                    )
                )
                .blendMode(.plusLighter)
                .allowsHitTesting(false)

            // 色散：冷暖两条细描边轻微错位
            if aberration > 0.01 {
                shape
                    .strokeBorder(Color(red: 0.55, green: 0.86, blue: 1.0)
                        .opacity(0.22 * aberration), lineWidth: 0.8)
                    .offset(x: -aberration, y: -aberration)
                    .allowsHitTesting(false)
                shape
                    .strokeBorder(Color(red: 1.0, green: 0.62, blue: 0.55)
                        .opacity(0.18 * aberration), lineWidth: 0.8)
                    .offset(x: aberration, y: aberration)
                    .allowsHitTesting(false)
            }

            // 外描边 + 内壁暗边
            shape
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.34),
                            Color.white.opacity(0.05),
                            Color.black.opacity(0.14)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.6
                )
                .allowsHitTesting(false)
        }
    }
}

extension View {
    /// 液态玻璃容器。`refraction` 传 0 可以强制用材质版（列表里更省电）。
    func luLiquidGlass(cornerRadius: CGFloat = 24,
                       frost: Double = 0.45,
                       saturation: Double = 1.35,
                       aberration: Double = 0.45,
                       tint: Color = .clear,
                       refraction: CGFloat = 14) -> some View {
        LuLiquidGlass(cornerRadius: cornerRadius, frost: frost, saturation: saturation,
                      aberration: aberration, tint: tint, refraction: refraction) { self }
    }
}

// MARK: - 液态玻璃按钮

/// 按下时轻微收缩 + 高光提亮，模拟 plasma-ui 里 `PlasmaButton` 的点击脉冲。
struct LuLiquidPressStyle: ButtonStyle {
    var cornerRadius: CGFloat = 100
    var tint: Color = .clear
    var horizontalPadding: CGFloat = 18
    var verticalPadding: CGFloat = 10
    var refraction: CGFloat = 8

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .luLiquidGlass(cornerRadius: cornerRadius, frost: 0.5,
                           saturation: 1.4, aberration: 0.5, tint: tint,
                           refraction: refraction)
            .scaleEffect(configuration.isPressed ? 0.965 : 1)
            .brightness(configuration.isPressed ? 0.05 : 0)
            .shadow(color: .black.opacity(configuration.isPressed ? 0.10 : 0.18),
                    radius: configuration.isPressed ? 6 : 12,
                    x: 0, y: configuration.isPressed ? 3 : 6)
            .animation(LuMotion.pop, value: configuration.isPressed)
    }
}

/// 胶囊形的液态玻璃按钮，文字与图标都走 label。
struct LuLiquidButton<Label: View>: View {
    var tint: Color = .white.opacity(0.10)
    var action: () -> Void
    @ViewBuilder var label: () -> Label

    var body: some View {
        Button(action: action) {
            label()
                .font(.system(size: 15, weight: .semibold))
        }
        .buttonStyle(LuLiquidPressStyle(tint: tint))
    }
}
