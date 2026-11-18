import SwiftUI

/// 全局背景层。对照 Flutter 侧 `LuBackdrop`：渐变底 + 5 颗静态光球 + 噪点。
///
/// **铁律：背景层永不动画。** 满屏重绘是掉帧元凶，这里所有元素都是静态
/// `Canvas` / `RadialGradient`，不接 timeline，不用 `.animation`。
/// 整个 App 只画一份，挂在根视图最底层。
struct LuBackdrop: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            ZStack {
                LuTheme.canvas

                // 五颗静态光球，位置按屏幕比例，浅深两套色相
                orb(color: LuTheme.accent.opacity(0.30), size: w * 0.95)
                    .offset(x: -w * 0.28, y: -h * 0.34)
                orb(color: Color(red: 0.55, green: 0.36, blue: 0.95).opacity(0.22), size: w * 0.80)
                    .offset(x: w * 0.36, y: -h * 0.10)
                orb(color: Color(red: 0.20, green: 0.72, blue: 0.68).opacity(0.16), size: w * 0.70)
                    .offset(x: -w * 0.30, y: h * 0.26)
                orb(color: Color(red: 0.95, green: 0.45, blue: 0.55).opacity(0.10), size: w * 0.60)
                    .offset(x: w * 0.40, y: h * 0.40)
                orb(color: LuTheme.accent.opacity(0.10), size: w * 0.50)
                    .offset(x: 0, y: h * 0.46)

                // 噪点：一次性绘制的静态纹理，避免每帧重建
                LuNoise()
                    .opacity(0.045)
                    .blendMode(.overlay)
                    .allowsHitTesting(false)
            }
            .ignoresSafeArea()
        }
        .allowsHitTesting(false)
    }

    private func orb(color: Color, size: CGFloat) -> some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [color, color.opacity(0.001)],
                    center: .center,
                    startRadius: 0,
                    endRadius: size / 2
                )
            )
            .frame(width: size, height: size)
            .blur(radius: 18)
    }
}

/// 静态噪点纹理。
private struct LuNoise: View {
    var body: some View {
        Canvas { context, size in
            // 固定种子，保证每次重绘纹理一致（且不需要存储）
            var seed: UInt64 = 0x9E3779B97F4A7C15
            func next() -> Double {
                seed = seed &* 6364136223846793005 &+ 1442695040888963407
                return Double((seed >> 33) & 0xFFFF) / 65535.0
            }
            let count = Int(size.width * size.height / 900)
            for _ in 0..<min(count, 6000) {
                let x = next() * size.width
                let y = next() * size.height
                let a = next() * 0.7
                let r = CGRect(x: x, y: y, width: 1, height: 1)
                context.fill(Path(r), with: .color(.white.opacity(a)))
            }
        }
        .drawingGroup()
    }
}

/// 页面容器：整体背景 + 内容。
struct LuPageBackground<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            LuBackdrop()
            content()
        }
    }
}
