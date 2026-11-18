import SwiftUI

struct EmbyView: View {
    @EnvironmentObject private var settings: AppSettings
    @State private var path = NavigationPath()
    @State private var views: [EmbyItem] = []
    @State private var isLoading = false
    @State private var error: String?

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    LuPageHeader(title: "Emby", subtitle: settings.embySession?.userName ?? "未连接") {
                        LuIconButton(symbol: "gearshape") { path.append(Route.embySettings) }
                    }

                    if settings.embySession == nil {
                        loginPrompt
                    } else {
                        LuAsyncContent(isLoading: isLoading, error: error, retry: {
                            Task { await load() }
                        }) {
                            if views.isEmpty && !isLoading {
                                LuEmptyState(symbol: "externaldrive.badge.questionmark",
                                             title: "服务器上没有媒体库",
                                             message: "检查 Emby 服务端是否已添加媒体库")
                            } else {
                                libraryGrid
                            }
                        }
                    }
                }
                .padding(.horizontal, LuTheme.pagePadding)
                .padding(.bottom, 28)
            }
            .navigationBarHidden(true)
            .navigationDestination(for: EmbyItem.self) { item in
                EmbyLibraryView(root: item)
            }
            .navigationDestination(for: Route.self) { RouteView(route: $0) }
        }
        .task { await load() }
    }

    private var loginPrompt: some View {
        VStack(spacing: 14) {
            Image(systemName: "externaldrive.connected.to.line.below")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(LuTheme.tertiary)
            Text("连接 Emby 服务器")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(LuTheme.label)
            Text("登录后可浏览媒体库、直接串流播放，支持 HLS 转码与直连。")
                .font(LuTheme.caption())
                .foregroundStyle(LuTheme.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
            Button {
                path.append(Route.embySettings)
            } label: {
                Text("添加服务器")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 180, height: 44)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(LuTheme.accent))
            }
            .buttonStyle(LuCardButtonStyle())
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .luGlass(.thin, cornerRadius: 16)
    }

    private var libraryGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("媒体库")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(LuTheme.label)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)],
                      alignment: .leading, spacing: 14) {
                ForEach(views) { item in
                    NavigationLink(value: item) {
                        VStack(alignment: .leading, spacing: 6) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color(uiColor: .tertiarySystemFill))
                                if let session = settings.embySession,
                                   let url = EmbyAPI.shared.imageURL(session, item: item, maxWidth: 400) {
                                    LuRemoteImage(url: url)
                                } else {
                                    Image(systemName: iconName(for: item.type))
                                        .font(.system(size: 26, weight: .light))
                                        .foregroundStyle(LuTheme.secondary)
                                }
                            }
                            .frame(height: 96)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                            Text(item.name)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(LuTheme.label)
                                .lineLimit(1)
                        }
                    }
                    .buttonStyle(LuCardButtonStyle())
                }
            }
        }
    }

    private func iconName(for type: String) -> String {
        switch type {
        case "movies": return "film"
        case "tvshows": return "tv"
        case "music": return "music.note"
        default: return "folder"
        }
    }

    private func load() async {
        guard let session = settings.embySession else { return }
        isLoading = true
        error = nil
        do {
            views = try await EmbyAPI.shared.views(session)
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }
}

// MARK: - 媒体库列表

struct EmbyLibraryView: View {
    let root: EmbyItem
    @EnvironmentObject private var settings: AppSettings
    @State private var items: [EmbyItem] = []
    @State private var isLoading = true
    @State private var error: String?
    @State private var playing: EmbyItem?
    @State private var metadataItem: EmbyItem?

    var body: some View {
        ZStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    LuPageHeader(title: root.name, subtitle: "\(items.count) 项")

                    LuAsyncContent(isLoading: isLoading, error: error, retry: {
                        Task { await load() }
                    }) {
                        if items.isEmpty {
                            LuEmptyState(symbol: "tray", title: "这里是空的")
                        } else {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 108), spacing: 10)],
                                      alignment: .leading, spacing: 16) {
                                ForEach(items) { item in
                                    Button {
                                        playing = item
                                    } label: {
                                        posterCard(item)
                                    }
                                    .buttonStyle(LuCardButtonStyle())
                                    .contextMenu {
                                        Button {
                                            playing = item
                                        } label: { Label("播放", systemImage: "play.fill") }
                                        Button {
                                            metadataItem = item
                                        } label: {
                                            Label("修正元数据", systemImage: "wand.and.stars")
                                        }
                                        if !item.userDataPlayed {
                                            Button {
                                                Task { await markPlayed(item) }
                                            } label: {
                                                Label("标记为已看", systemImage: "checkmark.circle")
                                            }
                                        }
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

            VStack {
                HStack {
                    LuIconButton(symbol: "chevron.left", size: 16) {
                        // 由 NavigationStack 处理返回
                        dismissSelf()
                    }
                    Spacer()
                }
                .padding(.horizontal, LuTheme.pagePadding)
                Spacer()
            }
        }
        .task { await load() }
        .fullScreenCover(item: $playing) { item in
            EmbyPlayerHost(item: item)
        }
        .sheet(item: $metadataItem) { item in
            EmbyMetadataSheet(item: item)
        }
    }

    @MainActor
    private func markPlayed(_ item: EmbyItem) async {
        guard let session = settings.embySession else { return }
        do {
            try await EmbyAPI.shared.markPlayed(session: session, itemID: item.id)
            if let index = items.firstIndex(where: { $0.id == item.id }) {
                items[index].userDataPlayed = true
            }
            LuHUD.shared.show("已标记")
        } catch {
            LuHUD.shared.show(error.localizedDescription)
        }
    }

    @Environment(\.dismiss) private var dismiss
    private func dismissSelf() { dismiss() }

    private func posterCard(_ item: EmbyItem) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            ZStack(alignment: .bottomTrailing) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(uiColor: .tertiarySystemFill))
                if let session = settings.embySession,
                   let url = EmbyAPI.shared.imageURL(session, item: item, maxWidth: 360) {
                    LuRemoteImage(url: url)
                } else {
                    Image(systemName: item.type == "Series" ? "tv" : "film")
                        .font(.system(size: 22, weight: .light))
                        .foregroundStyle(LuTheme.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                if item.userDataPlayed {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.white, LuTheme.accent)
                        .padding(5)
                }
            }
            .aspectRatio(2.0 / 3.0, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            Text(item.name)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(LuTheme.label)
                .lineLimit(2)
        }
    }

    private func load() async {
        guard let session = settings.embySession else { return }
        isLoading = true
        error = nil
        do {
            if root.type == "Series" {
                items = try await EmbyAPI.shared.episodes(session, seriesID: root.id)
            } else {
                items = try await EmbyAPI.shared.items(session, parentID: root.id)
            }
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }
}

// MARK: - Emby 播放承接

struct EmbyPlayerHost: View {
    let item: EmbyItem
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        if let session = settings.embySession,
           let url = EmbyAPI.shared.hlsURL(session, item: item) {
            PlayerView(
                subject: AnimeSubject(
                    id: 0, name: item.name, nameCN: item.name,
                    summary: item.overview, images: [:], airDate: "", airWeekday: 0,
                    eps: 1, platform: "Emby", ratingScore: 0, ratingRank: 0,
                    ratingTotal: 0, tags: []
                ),
                episode: AnimeEpisode(id: 0, type: 0, name: item.name, nameCN: item.name,
                                      sort: Double(item.indexNumber ?? 1),
                                      airdate: "", duration: ""),
                stream: PlayStream(url: url, quality: "转码", headers: [:]),
                episodes: [],
                resolveStream: { _ in nil }
            )
        } else {
            LuEmptyState(symbol: "exclamationmark.triangle", title: "无法播放")
        }
    }
}
