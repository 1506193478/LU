import SwiftUI

/// 日志查看器。内存里的最近 3000 条，可过滤、可导出。
struct LogViewerView: View {
    @ObservedObject private var log = LuLog.shared
    @Environment(\.dismiss) private var dismiss
    @State private var level: LuLogLevel?
    @State private var keyword = ""

    private var filtered: [LuLogEntry] {
        log.entries.reversed().filter { entry in
            if let level, entry.level != level { return false }
            if keyword.isEmpty { return true }
            return entry.message.localizedCaseInsensitiveContains(keyword)
                || entry.tag.localizedCaseInsensitiveContains(keyword)
        }
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                LuPageHeader(title: "日志", subtitle: "\(filtered.count) / \(log.entries.count) 条") {
                    HStack(spacing: 8) {
                        ShareLink(item: log.exportText(level: level)) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(LuTheme.label)
                                .frame(width: 34, height: 34)
                                .background(Circle().fill(.ultraThinMaterial))
                        }
                        LuIconButton(symbol: "trash") {
                            log.clear()
                            LuHUD.shared.show("日志已清空")
                        }
                    }
                }
                .padding(.horizontal, LuTheme.pagePadding)

                filterBar

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(filtered) { entry in
                            row(entry)
                        }
                    }
                    .padding(.horizontal, LuTheme.pagePadding)
                    .padding(.vertical, 8)
                }
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

    private var filterBar: some View {
        VStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    LuChip(text: "全部", selected: level == nil, action: { level = nil })
                    ForEach(LuLogLevel.allCases) { item in
                        LuChip(text: item.title, selected: level == item,
                               action: { level = item })
                    }
                }
                .padding(.horizontal, LuTheme.pagePadding)
            }
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundStyle(LuTheme.tertiary)
                TextField("搜索标签或内容", text: $keyword)
                    .font(.system(size: 13))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(RoundedRectangle(cornerRadius: 9)
                .fill(Color(uiColor: .tertiarySystemFill)))
            .padding(.horizontal, LuTheme.pagePadding)
        }
        .padding(.bottom, 6)
    }

    private func row(_ entry: LuLogEntry) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(entry.level.rawValue)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(color(entry.level))
                Text(entry.tag)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(LuTheme.tertiary)
                Spacer()
                Text(time(entry.date))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(LuTheme.tertiary)
            }
            Text(entry.message)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(LuTheme.label)
                .textSelection(.enabled)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8)
            .fill(Color(uiColor: .tertiarySystemFill).opacity(0.5)))
    }

    private func color(_ level: LuLogLevel) -> Color {
        switch level {
        case .debug: return LuTheme.tertiary
        case .info: return LuTheme.accent
        case .warn: return .orange
        case .error: return .red
        }
    }

    private func time(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
}
