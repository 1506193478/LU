import SwiftUI

/// 玻璃材质三档。iOS 16 没有系统液态玻璃 API，这里用 `UIVisualEffectView`
/// 的 `.systemUltraThinMaterial` 系列打底，叠「顶部高光 + 发丝描边 + 内阴影」
/// 还原液态玻璃的三层结构：
///
/// 1. 模糊底衬（材料）—— 折射感的近似
/// 2. 顶部 45° 白色渐变高光 —— 液面反射
/// 3. 0.5pt 描边 + 外侧柔光 —— 边缘浸润
///
/// 注意：材料层是一层常驻的 `UIVisualEffectView`，在滚动列表里大量使用时
/// 会掉跟手感（Flutter 侧踩过同样的坑）。列表卡片优先用 `.thin`，
/// 只有悬浮控件（底栏、浮层、播放器控件）才用 `.regular` / `.thick`。
enum LuGlassLevel {
    case thin
    case regular
    case thick

    var material: Material {
        switch self {
        case .thin: return .ultraThinMaterial
        case .regular: return .thinMaterial
        case .thick: return .regularMaterial
        }
    }

    var highlightOpacity: Double {
        switch self {
        case .thin: return 0.10
        case .regular: return 0.16
        case .thick: return 0.22
        }
    }
}

struct LuGlassSurface: ViewModifier {
    var level: LuGlassLevel = .regular
    var cornerRadius: CGFloat = LuTheme.cardRadius
    var showsStroke: Bool = true

    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(level.material)

                    // 液面反射：从顶部到底部的白色渐变
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(level.highlightOpacity),
                                    Color.white.opacity(0.02),
                                    Color.clear
                                ],
                                startPoint: .top,
                                endPoint: .center
                            )
                        )
                        .blendMode(.plusLighter)
                        .allowsHitTesting(false)

                    // 内壁阴影，制造厚度
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.28),
                                    Color.white.opacity(0.04),
                                    Color.black.opacity(0.10)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.5
                        )
                        .allowsHitTesting(false)
                }
            }
            .compositingGroup()
    }
}

extension View {
    /// 玻璃容器。level 默认 `.regular`，列表卡片请显式传 `.thin`。
    func luGlass(_ level: LuGlassLevel = .regular,
                 cornerRadius: CGFloat = LuTheme.cardRadius,
                 showsStroke: Bool = true) -> some View {
        modifier(LuGlassSurface(level: level, cornerRadius: cornerRadius, showsStroke: showsStroke))
    }
}

/// 便捷玻璃卡片：内容自带内边距。
struct LuGlassCard<Content: View>: View {
    var level: LuGlassLevel = .thin
    var cornerRadius: CGFloat = LuTheme.cardRadius
    var padding: CGFloat = 12
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .luGlass(level, cornerRadius: cornerRadius)
    }
}

/// 悬浮控件专用：带轻微投影的玻璃胶囊。
struct LuGlassCapsule<Content: View>: View {
    var level: LuGlassLevel = .regular
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background {
                Capsule(style: .continuous)
                    .fill(level.material)
                    .overlay {
                        Capsule(style: .continuous)
                            .fill(LinearGradient(colors: [.white.opacity(0.20), .clear],
                                                 startPoint: .top, endPoint: .bottom))
                            .blendMode(.plusLighter)
                    }
                    .overlay {
                        Capsule(style: .continuous)
                            .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5)
                    }
            }
            .shadow(color: .black.opacity(0.18), radius: 12, x: 0, y: 6)
    }
}
