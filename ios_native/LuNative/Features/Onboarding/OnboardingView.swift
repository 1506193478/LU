import SwiftUI

/// 首次启动引导。三步：欢迎 → 了解能力 → 配置入口。
struct OnboardingView: View {
    @Binding var done: Bool
    @State private var page = 0
    @State private var iconScale: CGFloat = 0.8

    private let pages: [OnboardingPage] = [
        OnboardingPage(
            symbol: "sparkles.tv",
            title: "欢迎使用 LU",
            subtitle: "原生 SwiftUI 的追番客户端",
            detail: "Bangumi 数据 + 多源聚合播放 + AVPlayer 内核，界面全部使用 iOS 原生控件与玻璃材质。",
            tint: LuTheme.accent
        ),
        OnboardingPage(
            symbol: "play.rectangle.on.rectangle",
            title: "先说清楚能做什么",
            subtitle: "推荐 · 追番 · 弹幕 · 离线",
            detail: "推荐与时间表来自 Bangumi；播放靠你导入的采集源插件；弹幕默认走 B 站免凭据接口，也可切到弹弹play。",
            tint: .purple
        ),
        OnboardingPage(
            symbol: "square.stack.3d.up",
            title: "三步就能看",
            subtitle: "导入源 → 找番 → 开播",
            detail: "在「我的 → 播放源插件」粘贴 Kazumi 插件 JSON；也可以先用直链播放试水。更多设置在「我的 → 设置」。",
            tint: .green
        )
    ]

    var body: some View {
        ZStack {
            LuBackdrop()

            VStack(spacing: 0) {
                TabView(selection: $page) {
                    ForEach(pages.indices, id: \.self) { index in
                        card(pages[index])
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                HStack(spacing: 7) {
                    ForEach(0..<pages.count, id: \.self) { index in
                        Capsule()
                            .fill(index == page ? LuTheme.accent : LuTheme.hairline)
                            .frame(width: index == page ? 18 : 6, height: 6)
                            .animation(LuTheme.spring, value: page)
                    }
                }
                .padding(.bottom, 22)

                LuLiquidButton(tint: LuTheme.accent.opacity(0.88)) {
                    if page < pages.count - 1 {
                        withAnimation(LuTheme.spring) { page += 1 }
                    } else {
                        withAnimation(LuTheme.spring) { done = true }
                    }
                } label: {
                    Text(page < pages.count - 1 ? "继续" : "开始使用")
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 24)
                }
                .padding(.horizontal, 28)

                Button {
                    withAnimation(LuTheme.quick) { done = true }
                } label: {
                    Text("跳过")
                        .font(.system(size: 13))
                        .foregroundStyle(LuTheme.secondary)
                }
                .buttonStyle(.plain)
                .padding(.top, 14)
                .padding(.bottom, 24)
                .opacity(page == pages.count - 1 ? 0 : 1)
            }
        }
    }

    private func card(_ item: OnboardingPage) -> some View {
        VStack(spacing: 22) {
            Spacer()

            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [item.tint.opacity(0.85), item.tint.opacity(0.35)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 128, height: 128)
                    .blur(radius: 0.5)
                Image(systemName: item.symbol)
                    .font(.system(size: 52, weight: .light))
                    .foregroundStyle(.white)
            }
            .shadow(color: item.tint.opacity(0.35), radius: 24, x: 0, y: 12)
            .scaleEffect(iconScale)
            .onAppear {
                iconScale = 0.8
                withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) { iconScale = 1 }
            }

            VStack(spacing: 8) {
                Text(item.title)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(LuTheme.label)
                Text(item.subtitle)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(LuTheme.accent)
                Text(item.detail)
                    .font(.system(size: 14))
                    .foregroundStyle(LuTheme.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.horizontal, 32)
                    .padding(.top, 4)
            }

            Spacer()
            Spacer()
        }
    }
}

private struct OnboardingPage {
    let symbol: String
    let title: String
    let subtitle: String
    let detail: String
    let tint: Color
}
