import SwiftUI

struct TimelineView: View {
    @State private var calendar: [[AnimeSubject]] = []
    @State private var isLoading = true
    @State private var error: String?
    @State private var path: [Route] = []

    private let weekdayNames = ["周一", "周二", "周三", "周四", "周五", "周六", "周日"]

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    LuPageHeader(title: "时间表", subtitle: "每周放送")

                    LuAsyncContent(isLoading: isLoading, error: error, retry: {
                        Task { await load() }
                    }) {
                        ForEach(calendar.indices, id: \.self) { index in
                            let list = calendar[index]
                            if !list.isEmpty {
                                AnimeRow(title: weekdayNames[min(index, weekdayNames.count - 1)],
                                         subjects: list) { subject in
                                    path.append(.detail(subjectID: subject.id))
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, LuTheme.pagePadding)
                .padding(.bottom, 28)
            }
            .navigationBarHidden(true)
            .navigationDestination(for: Route.self) { RouteView(route: $0) }
        }
        .task {
            if calendar.isEmpty { await load() }
        }
    }

    private func load() async {
        isLoading = true
        error = nil
        do {
            calendar = try await BangumiAPI.shared.calendar()
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }
}
