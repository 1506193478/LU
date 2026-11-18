import SwiftUI
import Combine

final class PopularViewModel: ObservableObject {
    @Published var calendar: [[AnimeSubject]] = []
    @Published var isLoading = false
    @Published var error: String?
    @Published var selectedDay: Int = 0     // 0...6 对应 周一...周日

    private var loaded = false

    /// Bangumi 的 weekday：1 = 周一 … 7 = 周日。
    static var todayBgmIndex: Int {
        let weekday = Calendar.current.component(.weekday, from: Date()) // 1 = 周日
        return (weekday + 5) % 7 + 1
    }

    var todayList: [AnimeSubject] {
        let index = Self.todayBgmIndex - 1
        guard calendar.indices.contains(index) else { return [] }
        return calendar[index]
    }

    var selectedList: [AnimeSubject] {
        guard calendar.indices.contains(selectedDay) else { return [] }
        return calendar[selectedDay]
    }

    var topRated: [AnimeSubject] {
        calendar.flatMap { $0 }
            .filter { $0.ratingScore > 0 }
            .sorted { $0.ratingScore > $1.ratingScore }
            .prefix(12)
            .map { $0 }
    }

    var seasonList: [AnimeSubject] {
        calendar.flatMap { $0 }
    }

    func loadIfNeeded() async {
        guard !loaded else { return }
        await load()
    }

    func load() async {
        isLoading = true
        error = nil
        do {
            let data = try await BangumiAPI.shared.calendar()
            calendar = data
            selectedDay = max(0, min(6, Self.todayBgmIndex - 1))
            loaded = true
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }
}

struct PopularView: View {
    @StateObject private var vm = PopularViewModel()
    @State private var path: [Route] = []

    private let weekdayTitles = ["一", "二", "三", "四", "五", "六", "日"]

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    LuPageHeader(title: "推荐", subtitle: "每日放送 · Bangumi") {
                        LuIconButton(symbol: "magnifyingglass") { path.append(.search) }
                    }

                    LuAsyncContent(isLoading: vm.isLoading, error: vm.error, retry: {
                        Task { await vm.load() }
                    }) {
                        content
                    }
                }
                .padding(.horizontal, LuTheme.pagePadding)
                .padding(.bottom, 28)
            }
            .navigationBarHidden(true)
            .navigationDestination(for: Route.self) { RouteView(route: $0) }
        }
        .task { await vm.loadIfNeeded() }
    }

    @ViewBuilder
    private var content: some View {
        if !vm.todayList.isEmpty {
            AnimeRow(title: "今天更新", subjects: vm.todayList) { subject in
                path.append(.detail(subjectID: subject.id))
            }
        }

        if !vm.topRated.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("高分推荐")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(LuTheme.label)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(vm.topRated) { subject in
                            wideCard(subject)
                        }
                    }
                }
            }
        }

        VStack(alignment: .leading, spacing: 12) {
            Text("每周放送")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(LuTheme.label)

            HStack(spacing: 8) {
                ForEach(0..<7, id: \.self) { index in
                    LuChip(text: "周" + weekdayTitles[index], selected: vm.selectedDay == index) {
                        withAnimation(LuTheme.spring) { vm.selectedDay = index }
                    }
                }
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 12)],
                      alignment: .leading, spacing: 16) {
                ForEach(vm.selectedList) { subject in
                    AnimeCard(subject: subject) {
                        path.append(.detail(subjectID: subject.id))
                    }
                }
            }
        }
    }

    private func wideCard(_ subject: AnimeSubject) -> some View {
        Button {
            path.append(.detail(subjectID: subject.id))
        } label: {
            ZStack(alignment: .bottomLeading) {
                LuRemoteImage(url: subject.coverURL)
                    .frame(width: 220, height: 124)
                LinearGradient(colors: [.clear, .black.opacity(0.82)],
                               startPoint: .center, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 3) {
                    Text(subject.displayName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                    LuRatingStars(score: subject.ratingScore)
                }
                .padding(10)
            }
            .frame(width: 220, height: 124)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5)
            }
        }
        .buttonStyle(LuCardButtonStyle())
    }
}
