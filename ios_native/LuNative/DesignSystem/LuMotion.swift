import SwiftUI
import UIKit

/// 动效令牌与转场。
///
/// 转场部分参考 ShipSwift 的 `SWTransition`（16 种转场）与 `SWChangeEffect`
/// （值变化触发的微交互）。原实现基于 iOS 17 的 `Transition` 协议与
/// `TransitionPhase`，本项目最低 iOS 16，所以这里用 `AnyTransition` +
/// `Animatable` 修饰器重写等价效果；参数含义保持一致，命名换成 `lu` 前缀。
enum LuMotion {
    /// 通用短动效：控制层显隐、状态切换
    static let quick = Animation.easeOut(duration: 0.18)
    /// 页面/卡片进出
    static let sheet = Animation.spring(response: 0.42, dampingFraction: 0.84)
    /// 强调（房间号更新、按钮脉冲）
    static let pop = Animation.spring(response: 0.34, dampingFraction: 0.66)
    /// 大面积位移
    static let smooth = Animation.easeInOut(duration: 0.28)
}

// MARK: - 转场

private struct LuBlurActive: ViewModifier, Animatable {
    var radius: CGFloat
    var opacity: Double

    var animatableData: AnimatablePair<CGFloat, Double> {
        get { AnimatablePair(radius, opacity) }
        set {
            radius = newValue.first
            opacity = newValue.second
        }
    }

    func body(content: Content) -> some View {
        content.blur(radius: radius).opacity(opacity)
    }
}

private struct LuBoingActive: ViewModifier, Animatable {
    var offset: CGFloat
    var scale: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(offset, scale) }
        set {
            offset = newValue.first
            scale = newValue.second
        }
    }

    func body(content: Content) -> some View {
        content
            .offset(y: offset)
            .scaleEffect(scale, anchor: .center)
    }
}

private struct LuWipeActive: ViewModifier, Animatable {
    var offset: CGFloat
    var opacity: Double

    var animatableData: AnimatablePair<CGFloat, Double> {
        get { AnimatablePair(offset, opacity) }
        set {
            offset = newValue.first
            opacity = newValue.second
        }
    }

    func body(content: Content) -> some View {
        content.offset(x: offset).opacity(opacity)
    }
}

private struct LuIrisActive: ViewModifier, Animatable {
    var progress: CGFloat
    var origin: UnitPoint

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        GeometryReader { geo in
            let longest = hypot(geo.size.width, geo.size.height)
            content.mask {
                Circle()
                    .frame(width: longest * 2 * max(progress, 0.001),
                           height: longest * 2 * max(progress, 0.001))
                    .position(x: geo.size.width * origin.x,
                              y: geo.size.height * origin.y)
            }
        }
    }
}

extension AnyTransition {
    /// 模糊 → 清晰（ShipSwift `swBlur`）
    static var luBlur: AnyTransition {
        .modifier(active: LuBlurActive(radius: 22, opacity: 0),
                  identity: LuBlurActive(radius: 0, opacity: 1))
    }

    /// 从下方弹入（ShipSwift `swBoing`，带一点回弹）
    static var luBoing: AnyTransition {
        .modifier(active: LuBoingActive(offset: 26, scale: 0.94),
                  identity: LuBoingActive(offset: 0, scale: 1))
    }

    /// 从右侧擦入（ShipSwift `swSkid`）
    static var luWipe: AnyTransition {
        .modifier(active: LuWipeActive(offset: 60, opacity: 0),
                  identity: LuWipeActive(offset: 0, opacity: 1))
    }

    /// 从指定点圆形展开（ShipSwift `swIris`）
    static func luIris(origin: UnitPoint = .center) -> AnyTransition {
        .modifier(active: LuIrisActive(progress: 0.001, origin: origin),
                  identity: LuIrisActive(progress: 1, origin: origin))
    }
}

// MARK: - 微交互

private struct LuShakeModifier: ViewModifier {
    var trigger: Int
    @State private var offset: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .offset(x: offset)
            .onChange(of: trigger) { value in
                guard value > 0 else { return }
                shake()
            }
    }

    private func shake() {
        let steps: [(Double, CGFloat)] = [
            (0.00, -9), (0.06, 8), (0.12, -6), (0.18, 4), (0.24, 0)
        ]
        for (delay, value) in steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                withAnimation(.linear(duration: 0.06)) { offset = value }
            }
        }
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
    }
}

private struct LuShimmerModifier: ViewModifier {
    var isActive: Bool
    @State private var phase: CGFloat = -1.2

    func body(content: Content) -> some View {
        content
            .overlay {
                if isActive {
                    GeometryReader { geo in
                        LinearGradient(
                            colors: [.clear, Color.white.opacity(0.28), .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: geo.size.width * 0.55)
                        .offset(x: phase * geo.size.width)
                    }
                    .blendMode(.plusLighter)
                    .allowsHitTesting(false)
                    .clipped()
                }
            }
            .onAppear {
                guard isActive else { return }
                phase = -1.2
                withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                    phase = 1.6
                }
            }
    }
}

extension View {
    /// 值变化时横向抖一下。`trigger` 加一即触发（对齐 `SWChangeEffect` 的 shake）。
    func luShake(trigger: Int) -> some View {
        modifier(LuShakeModifier(trigger: trigger))
    }

    /// 骨架屏扫光。仅用于加载占位，不要挂在常驻卡片上。
    func luShimmer(_ isActive: Bool = true) -> some View {
        modifier(LuShimmerModifier(isActive: isActive))
    }
}
