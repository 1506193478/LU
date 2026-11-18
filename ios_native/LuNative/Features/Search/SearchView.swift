import SwiftUI
import Combine

final class SearchViewModel: ObservableObject {
    @Published var keyword: String = ""
    @Published var results: [AnimeSubject] = []
    @Published var isLoading = false
    @Published var error: String?
    @Published var hasSearched = false

    func search() async {
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isLoading = true
        error = nil
        hasSearched = true
        do {
            results = try await BangumiAPI.shared.search(keyword: trimmed)
            AppState.shared.rememberSearch(trimmed)
        } catch {
            self.error = error.localizedDescription
            results = []
        }
        isLoading = false
    }
}

struct SearchView: View {
    @StateObject private var vm = SearchViewModel()
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                searchField

                if !vm.hasSearched, !app.searchHistory.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("最近搜索")
                                .font(LuTheme.label13())
                                .foregroundStyle(LuTheme.secondary)
                            Spacer()
                            Button("清空") { app.clearSearchHistory() }
                                .font(LuTheme.caption())
                                .foregroundStyle(LuTheme.secondary)
                        }
                        FlowLayout(spacing: 8) {
                            ForEach(app.searchHistory, id: \.self) { word in
                                LuChip(text: word) {
                                    vm.keyword = word
                                    Task { await vm.search() }
                                }
                            }
                        }
                    }
                }

                LuAsyncContent(isLoading: vm.isLoading, error: vm.error, retry: {
                    Task { await vm.search() }
                }) {
                    if vm.results.isEmpty && vm.hasSearched {
                        LuEmptyState(symbol: "magnifyingglass",
                                     title: "没有找到",
                                     message: "换个关键词试试，或检查网络")
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 12)],
                                  alignment: .leading, spacing: 16) {
                            ForEach(vm.results) { subject in
                                NavigationLink(value: Route.detail(subjectID: subject.id)) {
                                    AnimeCard(subject: subject)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, LuTheme.pagePadding)
            .padding(.bottom, 28)
        }
        .navigationBarHidden(true)
        .onAppear { focused = true }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(LuTheme.label)
            }
            .buttonStyle(.plain)

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(LuTheme.secondary)
                TextField("搜索番剧、动画", text: $vm.keyword)
                    .focused($focused)
                    .submitLabel(.search)
                    .font(.system(size: 15))
                    .onSubmit { Task { await vm.search() } }
                if !vm.keyword.isEmpty {
                    Button {
                        vm.keyword = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(LuTheme.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 36)
            .background {
                Capsule(style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(Capsule().strokeBorder(LuTheme.hairline, lineWidth: 0.5))
            }
        }
        .padding(.top, 8)
    }
}

// MARK: - 简单流式布局（搜索历史 chips 用）

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth == .infinity ? x : maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize,
                       subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
