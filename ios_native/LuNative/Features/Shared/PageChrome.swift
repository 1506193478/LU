import SwiftUI

// MARK: - 页面头部（自绘，不用系统大标题，避免与玻璃背景冲突）

struct LuPageHeader<Trailing: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(LuTheme.label)
                if let subtitle {
                    Text(subtitle)
                        .font(LuTheme.caption())
                        .foregroundStyle(LuTheme.secondary)
                }
            }
            Spacer(minLength: 12)
            trailing()
        }
        .padding(.top, 8)
        .padding(.bottom, 12)
    }
}

extension LuPageHeader where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil) {
        self.init(title: title, subtitle: subtitle) { EmptyView() }
    }
}

/// 图标按钮，玻璃胶囊底。
struct LuIconButton: View {
    let symbol: String
    var size: CGFloat = 15
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(LuTheme.label)
                .frame(width: 34, height: 34)
                .background {
                    Circle().fill(.ultraThinMaterial)
                        .overlay(Circle().strokeBorder(LuTheme.hairline, lineWidth: 0.5))
                }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 番剧卡片

struct AnimeCard: View {
    let subject: AnimeSubject
    var showsRating: Bool = true
    var onTap: (() -> Void)?

    var body: some View {
        Button {
            onTap?()
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                LuRemoteImage(url: subject.coverURL)
                    .aspectRatio(3.0 / 4.0, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(alignment: .topTrailing) {
                        if showsRating, subject.ratingScore > 0 {
                            Text(subject.ratingText)
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background {
                                    Capsule().fill(Color.black.opacity(0.55))
                                }
                                .padding(5)
                        }
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5)
                    }

                Text(subject.displayName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(LuTheme.label)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                if !subject.airDate.isEmpty {
                    Text(String(subject.airDate.prefix(10)))
                        .font(.system(size: 11))
                        .foregroundStyle(LuTheme.tertiary)
                }
            }
        }
        .buttonStyle(LuCardButtonStyle())
    }
}

struct LuCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.965 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(LuTheme.quick, value: configuration.isPressed)
    }
}

// MARK: - 横向卡片轨道

struct AnimeRow: View {
    let title: String
    let subjects: [AnimeSubject]
    var onSelect: (AnimeSubject) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(LuTheme.label)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(subjects) { subject in
                        AnimeCard(subject: subject) { onSelect(subject) }
                            .frame(width: 108)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }
}

// MARK: - 加载 / 失败容器

struct LuAsyncContent<Content: View>: View {
    let isLoading: Bool
    let error: String?
    var retry: (() -> Void)?
    @ViewBuilder var content: () -> Content

    var body: some View {
        if isLoading {
            VStack(spacing: 12) {
                ProgressView()
                Text("加载中…").font(LuTheme.caption()).foregroundStyle(LuTheme.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 60)
        } else if let error {
            VStack(spacing: 12) {
                Image(systemName: "wifi.exclamationmark")
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(LuTheme.tertiary)
                Text(error)
                    .font(LuTheme.caption())
                    .foregroundStyle(LuTheme.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                if let retry {
                    Button("重试") { retry() }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(LuTheme.accent)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 48)
        } else {
            content()
        }
    }
}
