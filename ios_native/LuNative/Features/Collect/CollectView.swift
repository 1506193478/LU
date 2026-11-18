import SwiftUI

struct CollectView: View {
    @EnvironmentObject private var app: AppState
    @State private var path: [Route] = []
    @State private var pendingRemoval: AnimeSubject?

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    LuPageHeader(title: "追番", subtitle: "\(app.collectCount) 部在追")

                    if app.collects.isEmpty {
                        LuEmptyState(symbol: "books.vertical",
                                     title: "还没有追番",
                                     message: "在番剧详情页点右上角收藏")
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 12)],
                                  alignment: .leading, spacing: 16) {
                            ForEach(app.collects) { record in
                                AnimeCard(subject: record.subject) {
                                    path.append(.detail(subjectID: record.subject.id))
                                }
                                .contextMenu {
                                    Button {
                                        path.append(.detail(subjectID: record.subject.id))
                                    } label: {
                                        Label("查看详情", systemImage: "info.circle")
                                    }
                                    Button(role: .destructive) {
                                        pendingRemoval = record.subject
                                    } label: {
                                        Label("取消追番", systemImage: "trash")
                                    }
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
        .confirmationDialog("取消追番？",
                            isPresented: Binding(get: { pendingRemoval != nil },
                                                 set: { if !$0 { pendingRemoval = nil } }),
                            titleVisibility: .visible) {
            Button("取消追番", role: .destructive) {
                if let subject = pendingRemoval {
                    withAnimation(LuTheme.spring) { app.removeCollect(subjectID: subject.id) }
                }
                pendingRemoval = nil
            }
            Button("保留", role: .cancel) { pendingRemoval = nil }
        } message: {
            Text(pendingRemoval?.displayName ?? "")
        }
    }
}
