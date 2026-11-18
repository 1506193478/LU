import SwiftUI
import UIKit
import Combine

// MARK: - 异步图片（内存缓存 + 磁盘由 URLCache 负责）

final class LuImageCache {
    static let shared = LuImageCache()
    private let memory = NSCache<NSURL, UIImage>()
    private init() {
        memory.countLimit = 200
        memory.totalCostLimit = 96 * 1024 * 1024
    }

    func cached(_ url: URL) -> UIImage? { memory.object(forKey: url as NSURL) }
    func store(_ image: UIImage, for url: URL) { memory.setObject(image, forKey: url as NSURL) }
}

struct LuRemoteImage: View {
    let url: URL?
    var contentMode: ContentMode = .fill
    var placeholderColor: Color = Color(uiColor: .tertiarySystemFill)

    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .transition(.opacity)
            } else {
                placeholderColor
                    .overlay {
                        if failed {
                            Image(systemName: "photo")
                                .font(.system(size: 18))
                                .foregroundStyle(LuTheme.tertiary)
                        }
                    }
            }
        }
        .clipped()
        .task(id: url) { await load() }
    }

    private func load() async {
        guard let url else { return }
        if let cached = LuImageCache.shared.cached(url) {
            image = cached
            return
        }
        failed = false
        do {
            var request = URLRequest(url: url)
            request.setValue(LuUserAgent.value, forHTTPHeaderField: "User-Agent")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  let decoded = UIImage(data: data) else {
                failed = true
                return
            }
            LuImageCache.shared.store(decoded, for: url)
            withAnimation(LuTheme.quick) { image = decoded }
        } catch {
            failed = true
        }
    }
}

// MARK: - 底栏

struct LuTabItem: Identifiable, Hashable {
    let id: String
    let title: String
    let symbol: String
}

struct LuTabBar: View {
    let items: [LuTabItem]
    @Binding var selection: Int
    var namespace: Namespace.ID

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items.indices, id: \.self) { index in
                let item = items[index]
                Button {
                    guard selection != index else { return }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(LuTheme.spring) { selection = index }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: selection == index ? item.symbol + ".fill" : item.symbol)
                            .font(.system(size: 19, weight: .regular))
                            .frame(height: 22)
                        Text(item.title)
                            .font(.system(size: 10, weight: selection == index ? .semibold : .regular))
                    }
                    .foregroundStyle(selection == index ? LuTheme.accent : LuTheme.secondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: LuTheme.tabBarHeight)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 6)
        .background {
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                Rectangle()
                    .fill(LinearGradient(colors: [.white.opacity(0.14), .clear],
                                         startPoint: .top, endPoint: .bottom))
                    .blendMode(.plusLighter)
                VStack {
                    Rectangle().fill(LuTheme.hairline).frame(height: 0.5)
                    Spacer()
                }
            }
        }
    }
}

// MARK: - 小组件

struct LuChip: View {
    let text: String
    var selected: Bool = false
    var action: (() -> Void)?

    var body: some View {
        let label = Text(text)
            .font(.system(size: 13, weight: selected ? .semibold : .regular))
            .lineLimit(1)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .foregroundStyle(selected ? Color.white : LuTheme.label)
            .background {
                Capsule(style: .continuous)
                    .fill(selected ? LuTheme.accent : Color(uiColor: .tertiarySystemFill))
            }

        if let action {
            Button(action: action) { label }.buttonStyle(.plain)
        } else {
            label
        }
    }
}

struct LuSectionHeader: View {
    let title: String
    var trailing: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(LuTheme.label)
            Spacer(minLength: 8)
            if let trailing {
                Button {
                    action?()
                } label: {
                    HStack(spacing: 2) {
                        Text(trailing).font(LuTheme.caption())
                        Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(LuTheme.secondary)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct LuRatingStars: View {
    let score: Double   // 0...10

    var body: some View {
        let stars = score / 2.0
        HStack(spacing: 1) {
            ForEach(0..<5, id: \.self) { index in
                Image(systemName: symbol(for: index, stars: stars))
                    .font(.system(size: 10))
            }
            Text(String(format: "%.1f", score))
                .font(.system(size: 11, weight: .semibold))
                .padding(.leading, 3)
        }
        .foregroundStyle(Color.orange)
    }

    private func symbol(for index: Int, stars: Double) -> String {
        let value = stars - Double(index)
        if value >= 1 { return "star.fill" }
        if value >= 0.5 { return "star.leadinghalf.filled" }
        return "star"
    }
}

struct LuEmptyState: View {
    let symbol: String
    let title: String
    var message: String?

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(LuTheme.tertiary)
            Text(title)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(LuTheme.secondary)
            if let message {
                Text(message)
                    .font(LuTheme.caption())
                    .foregroundStyle(LuTheme.tertiary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }
}

/// 底部胶囊通知。对照 Flutter 的 KzHud。
final class LuHUD: ObservableObject {
    static let shared = LuHUD()
    @Published var message: String?
    private var task: Task<Void, Never>?

    func show(_ text: String, duration: Double = 2.0) {
        task?.cancel()
        withAnimation(LuTheme.spring) { message = text }
        task = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            withAnimation(LuTheme.quick) { self.message = nil }
        }
    }
}

struct LuHUDOverlay: View {
    @ObservedObject private var hud = LuHUD.shared

    var body: some View {
        VStack {
            Spacer()
            if let message = hud.message {
                Text(message)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background {
                        Capsule(style: .continuous).fill(Color.black.opacity(0.78))
                    }
                    .padding(.bottom, 96)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .allowsHitTesting(false)
        .animation(LuTheme.spring, value: hud.message)
    }
}

/// 设置风格的列表行。
struct LuListRow: View {
    let title: String
    var subtitle: String?
    var symbol: String?
    var value: String?
    var chevron: Bool = false
    var tint: Color = LuTheme.accent

    var body: some View {
        HStack(spacing: 12) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(tint))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(LuTheme.rowTitle()).foregroundStyle(LuTheme.label)
                if let subtitle {
                    Text(subtitle).font(LuTheme.caption()).foregroundStyle(LuTheme.secondary)
                }
            }
            Spacer(minLength: 8)
            if let value {
                Text(value).font(LuTheme.caption()).foregroundStyle(LuTheme.secondary)
            }
            if chevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(LuTheme.tertiary)
            }
        }
        .frame(minHeight: LuTheme.rowHeight)
        .contentShape(Rectangle())
    }
}

/// 分组卡片容器。
struct LuGroup<Content: View>: View {
    var title: String?
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title {
                Text(title)
                    .font(LuTheme.label13())
                    .foregroundStyle(LuTheme.secondary)
                    .padding(.leading, 4)
            }
            VStack(spacing: 0) { content() }
                .luGlass(.thin, cornerRadius: LuTheme.cardRadius)
        }
    }
}
