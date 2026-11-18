import SwiftUI

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            ScrollView {
                VStack(spacing: 16) {
                    LuPageHeader(title: "关于")

                    VStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .fill(LinearGradient(colors: [LuTheme.accent, .purple],
                                                     startPoint: .topLeading,
                                                     endPoint: .bottomTrailing))
                            Text("LU")
                                .font(.system(size: 34, weight: .heavy))
                                .foregroundStyle(.white)
                        }
                        .frame(width: 88, height: 88)

                        Text("LU")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(LuTheme.label)
                        Text("原生 SwiftUI 版 5.0.0")
                            .font(LuTheme.caption())
                            .foregroundStyle(LuTheme.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)

                    LuGroup {
                        LuListRow(title: "版本", value: "5.0.0 (1)")
                            .padding(.horizontal, 12)
                        line
                        LuListRow(title: "界面", value: "SwiftUI")
                            .padding(.horizontal, 12)
                        line
                        LuListRow(title: "播放内核", value: "AVPlayer")
                            .padding(.horizontal, 12)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("开源说明")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(LuTheme.secondary)
                        Text("本应用基于 Kazumi（GPL-3.0）的数据结构与交互设计重写。番剧元数据来自 Bangumi，弹幕来自弹弹play。请遵守当地法律法规，仅将本应用用于个人学习与已获授权的内容。")
                            .font(.system(size: 12))
                            .foregroundStyle(LuTheme.tertiary)
                            .lineSpacing(3)
                    }
                    .padding(12)
                    .luGlass(.thin, cornerRadius: 12)
                }
                .padding(.horizontal, LuTheme.pagePadding)
                .padding(.bottom, 28)
            }
            .navigationBarHidden(true)

            VStack {
                HStack {
                    LuIconButton(symbol: "chevron.left", size: 16) { dismiss() }
                    Spacer()
                }
                .padding(.horizontal, LuTheme.pagePadding)
                Spacer()
            }
        }
    }

    private var line: some View {
        Rectangle().fill(LuTheme.hairline).frame(height: 0.5).padding(.leading, 12)
    }
}
