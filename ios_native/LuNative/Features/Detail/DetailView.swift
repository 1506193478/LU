import SwiftUI
import UIKit

struct PlaybackRequest: Identifiable {
    let id = UUID()
    var subject: AnimeSubject
    var episode: AnimeEpisode
    var stream: PlayStream
    var episodes: [AnimeEpisode]
}

struct DetailView: View {
    let subjectID: Int

    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var pluginStore: PluginStore
    @Environment(\.dismiss) private var dismiss

    @State private var subject: AnimeSubject?
    @State private var episodes: [AnimeEpisode] = []
    @State private var characters: [AnimeCharacter] = []
    @State private var staffs: [AnimeStaff] = []
    @State private var comments: [AnimeComment] = []
    @State private var isLoading = true
    @State private var error: String?

    @State private var playback: PlaybackRequest?
    @State private var isResolving = false
    @State private var showManualInput = false
    @State private var manualURL = ""
    @State private var pendingEpisode: AnimeEpisode?
    @State private var expandedSummary = false
    @State private var sourceSheetShown = false
    @State private var activePluginID: String?
    /// 多源探测结果（pluginID → 命中情况）
    @State private var probe: [String: SourceProbe] = [:]
    @State private var probing = false

    struct SourceProbe: Equatable {
        var count: Int
        var first: String
        var error: String?
    }

    var body: some View {
        ZStack(alignment: .top) {
            if isLoading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error, subject == nil {
                LuEmptyState(symbol: "exclamationmark.triangle", title: "加载失败", message: error)
            } else if let subject {
                content(subject)
            }

            topBar
        }
        .navigationBarHidden(true)
        .task { await load() }
        .fullScreenCover(item: $playback) { request in
            PlayerView(subject: request.subject,
                       episode: request.episode,
                       stream: request.stream,
                       episodes: request.episodes,
                       resolveStream: { episode in
                           await resolveStream(for: episode)
                       })
        }
        .sheet(isPresented: $showManualInput) {
            manualInputSheet
        }
        .sheet(isPresented: $sourceSheetShown) {
            sourceSheet
        }
    }

    // MARK: - 顶部栏

    private var topBar: some View {
        HStack {
            LuIconButton(symbol: "chevron.left", size: 16) { dismiss() }
            Spacer()
            if let subject {
                Button {
                    let added = app.toggleCollect(subject)
                    LuHUD.shared.show(added ? "已加入追番" : "已取消追番")
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: app.isCollected(subject.id) ? "heart.fill" : "heart")
                            .font(.system(size: 13, weight: .semibold))
                        Text(app.isCollected(subject.id) ? "已追" : "追番")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(app.isCollected(subject.id) ? Color.pink : LuTheme.label)
                    .padding(.horizontal, 12)
                    .frame(height: 34)
                    .background {
                        Capsule().fill(.ultraThinMaterial)
                            .overlay(Capsule().strokeBorder(LuTheme.hairline, lineWidth: 0.5))
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, LuTheme.pagePadding)
        .padding(.top, 4)
    }

    // MARK: - 主体

    private func content(_ subject: AnimeSubject) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                coverHeader(subject)
                titleBlock(subject)
                actionRow(subject)
                summaryBlock(subject)
                episodeSection
                if !characters.isEmpty { characterSection }
                if !staffs.isEmpty { staffSection }
                if !comments.isEmpty { commentSection }
                Spacer(minLength: 24)
            }
            .padding(.bottom, 28)
        }
        .ignoresSafeArea(edges: .top)
    }

    private func coverHeader(_ subject: AnimeSubject) -> some View {
        ZStack(alignment: .bottom) {
            LuRemoteImage(url: subject.coverURL)
                .frame(height: 380)
                .blur(radius: 26, opaque: true)
                .overlay(Color.black.opacity(0.35))
                .clipped()

            LinearGradient(colors: [.clear, LuTheme.canvas],
                           startPoint: .center, endPoint: .bottom)
                .frame(height: 380)

            LuRemoteImage(url: subject.coverURL)
                .frame(width: 132, height: 176)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5)
                }
                .shadow(color: .black.opacity(0.35), radius: 18, x: 0, y: 8)
                .padding(.bottom, 6)
        }
        .frame(height: 380)
    }

    private func titleBlock(_ subject: AnimeSubject) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(subject.displayName)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(LuTheme.label)
                .fixedSize(horizontal: false, vertical: true)

            if subject.name != subject.displayName, !subject.name.isEmpty {
                Text(subject.name)
                    .font(.system(size: 13))
                    .foregroundStyle(LuTheme.secondary)
            }

            HStack(spacing: 10) {
                if subject.ratingScore > 0 {
                    LuRatingStars(score: subject.ratingScore)
                }
                if !subject.airDate.isEmpty {
                    Text(String(subject.airDate.prefix(10)))
                        .font(LuTheme.caption())
                        .foregroundStyle(LuTheme.secondary)
                }
                if subject.eps > 0 {
                    Text("\(subject.eps) 话")
                        .font(LuTheme.caption())
                        .foregroundStyle(LuTheme.secondary)
                }
            }

            if !subject.tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(subject.tags.prefix(10), id: \.self) { tag in
                            Text(tag)
                                .font(.system(size: 11))
                                .foregroundStyle(LuTheme.secondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(Color(uiColor: .tertiarySystemFill)))
                        }
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(.horizontal, LuTheme.pagePadding)
    }

    private func actionRow(_ subject: AnimeSubject) -> some View {
        HStack(spacing: 10) {
            Button {
                Task { await playNext(episode: recommendedEpisode) }
            } label: {
                HStack(spacing: 6) {
                    if isResolving {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "play.fill").font(.system(size: 13, weight: .bold))
                    }
                    Text(resumeLabel).font(.system(size: 15, weight: .semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(LuTheme.accent))
            }
            .buttonStyle(LuCardButtonStyle())
            .disabled(isResolving)

            Button {
                pendingEpisode = nil
                showManualInput = true
            } label: {
                Image(systemName: "link")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(LuTheme.label)
                    .frame(width: 46, height: 46)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.ultraThinMaterial))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(LuTheme.hairline, lineWidth: 0.5))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, LuTheme.pagePadding)
    }

    private var resumeLabel: String {
        if let last = app.lastEpisode(subjectID: subjectID),
           last.progress > 0.02, last.progress < 0.95 {
            return "继续观看 \(Int(last.progress * 100))%"
        }
        return "开始观看"
    }

    private var recommendedEpisode: AnimeEpisode? {
        if let last = app.lastEpisode(subjectID: subjectID),
           let match = episodes.first(where: { $0.id == last.episodeID }) {
            return match
        }
        return episodes.first
    }

    private func summaryBlock(_ subject: AnimeSubject) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("简介")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(LuTheme.label)
            Text(subject.summary.isEmpty
                 ? AttributedString("暂无简介")
                 : LuBBCode.render(subject.summary, fontSize: 14, color: LuTheme.secondary))
                .lineSpacing(3)
                .lineLimit(expandedSummary ? nil : 4)
            if subject.summary.count > 90 {
                Button(expandedSummary ? "收起" : "展开") {
                    withAnimation(LuTheme.spring) { expandedSummary.toggle() }
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(LuTheme.accent)
            }
        }
        .padding(.horizontal, LuTheme.pagePadding)
    }

    private var episodeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("剧集")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(LuTheme.label)
                Spacer()
                if !pluginStore.enabledPlugins.isEmpty {
                    Button {
                        sourceSheetShown = true
                    } label: {
                        HStack(spacing: 2) {
                            Text(activePlugin?.name ?? "")
                                .font(LuTheme.caption())
                            Image(systemName: "arrow.left.arrow.right")
                                .font(.system(size: 9, weight: .semibold))
                        }
                        .foregroundStyle(LuTheme.secondary)
                    }
                    .buttonStyle(.plain)
                } else {
                    Button("添加源") { sourceSheetShown = true }
                        .font(LuTheme.caption())
                        .foregroundStyle(LuTheme.accent)
                }
            }

            if episodes.isEmpty {
                Text("暂无剧集信息")
                    .font(LuTheme.caption())
                    .foregroundStyle(LuTheme.tertiary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(episodes) { episode in
                            Button {
                                Task { await playNext(episode: episode) }
                            } label: {
                                VStack(spacing: 2) {
                                    Text(episode.sort > 0 ? String(format: "%.0f", episode.sort) : "?")
                                        .font(.system(size: 15, weight: .semibold))
                                    if !episode.displayName.isEmpty {
                                        Text(episode.displayName)
                                            .font(.system(size: 9))
                                            .lineLimit(1)
                                            .frame(width: 54)
                                    }
                                }
                                .foregroundStyle(LuTheme.label)
                                .frame(width: 62, height: 52)
                                .background {
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(.ultraThinMaterial)
                                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .strokeBorder(LuTheme.hairline, lineWidth: 0.5))
                                }
                            }
                            .buttonStyle(LuCardButtonStyle())
                        }
                    }
                }
            }
        }
        .padding(.horizontal, LuTheme.pagePadding)
    }

    private var characterSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("角色")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(LuTheme.label)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(characters) { character in
                        VStack(spacing: 5) {
                            LuRemoteImage(url: character.imageURL)
                                .frame(width: 72, height: 96)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            Text(character.name)
                                .font(.system(size: 11))
                                .foregroundStyle(LuTheme.label)
                                .lineLimit(1)
                                .frame(width: 72)
                            if let actor = character.actors.first {
                                Text(actor)
                                    .font(.system(size: 9))
                                    .foregroundStyle(LuTheme.tertiary)
                                    .lineLimit(1)
                                    .frame(width: 72)
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, LuTheme.pagePadding)
    }

    private var staffSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("制作人员")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(LuTheme.label)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 14) {
                    ForEach(staffs) { staff in
                        VStack(spacing: 5) {
                            LuRemoteImage(url: staff.imageURL)
                                .frame(width: 56, height: 56)
                                .clipShape(Circle())
                            Text(staff.name)
                                .font(.system(size: 11))
                                .foregroundStyle(LuTheme.label)
                                .lineLimit(1)
                                .frame(width: 64)
                            Text(staff.relation)
                                .font(.system(size: 9))
                                .foregroundStyle(LuTheme.tertiary)
                                .lineLimit(1)
                                .frame(width: 64)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, LuTheme.pagePadding)
    }

    private var commentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("短评")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(LuTheme.label)
                Spacer()
                Text("\(comments.count) 条")
                    .font(LuTheme.caption())
                    .foregroundStyle(LuTheme.tertiary)
            }

            VStack(spacing: 0) {
                ForEach(comments.prefix(8)) { comment in
                    commentRow(comment)
                    if comment.id != comments.prefix(8).last?.id {
                        Rectangle().fill(LuTheme.hairline).frame(height: 0.5)
                    }
                }
            }
            .padding(12)
            .luGlass(.thin, cornerRadius: 12)
        }
        .padding(.horizontal, LuTheme.pagePadding)
    }

    private func commentRow(_ comment: AnimeComment) -> some View {
        HStack(alignment: .top, spacing: 10) {
            LuRemoteImage(url: URL(string: comment.avatar))
                .frame(width: 28, height: 28)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(comment.userName)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(LuTheme.label)
                    if comment.score > 0 {
                        Text("\(comment.score) 分")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(LuTheme.accent)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(LuTheme.accent.opacity(0.12)))
                    }
                    Spacer()
                    Text(shortDate(comment.date))
                        .font(.system(size: 9))
                        .foregroundStyle(LuTheme.tertiary)
                }
                Text(comment.content)
                    .font(.system(size: 12))
                    .foregroundStyle(LuTheme.secondary)
                    .lineLimit(5)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 8)
    }

    private func shortDate(_ raw: String) -> String {
        raw.count >= 10 ? String(raw.prefix(10)) : raw
    }

    // MARK: - 数据

    private func load() async {
        isLoading = true
        error = nil
        do {
            async let subjectTask = BangumiAPI.shared.subject(id: subjectID)
            async let episodeTask = BangumiAPI.shared.episodes(subjectID: subjectID)
            async let characterTask = BangumiAPI.shared.characters(subjectID: subjectID)
            async let staffTask = BangumiAPI.shared.staffs(subjectID: subjectID)
            async let commentTask = BangumiAPI.shared.comments(subjectID: subjectID)

            let loadedSubject = try await subjectTask
            subject = loadedSubject
            episodes = (try? await episodeTask) ?? []
            characters = (try? await characterTask) ?? []
            staffs = (try? await staffTask) ?? []
            comments = (try? await commentTask) ?? []
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    // MARK: - 播放

    /// 当前选中的源；没选过就用第一个启用的插件。
    private var activePlugin: PluginManifest? {
        if let activePluginID,
           let match = pluginStore.enabledPlugins.first(where: { $0.id == activePluginID }) {
            return match
        }
        return pluginStore.enabledPlugins.first
    }

    /// 解析某一集的播放地址。失败返回 nil，由调用方决定降级方式。
    private func resolveStream(for episode: AnimeEpisode) async -> PlayStream? {
        guard let subject, let plugin = activePlugin else { return nil }
        do {
            let items = try await PluginEngine.shared.search(plugin: plugin,
                                                             keyword: subject.displayName)
            guard let first = items.first else { return nil }
            let roads = try await PluginEngine.shared.chapters(plugin: plugin, detail: first.url)
            guard let road = roads.first, !road.isEmpty else { return nil }

            let index = episodes.firstIndex(where: { $0.id == episode.id }) ?? 0
            let chapter = road[min(max(index, 0), road.count - 1)]
            let streams = try await PluginEngine.shared.streams(plugin: plugin, chapter: chapter.url)
            return streams.first
        } catch {
            return nil
        }
    }

    @MainActor
    private func playNext(episode: AnimeEpisode?) async {
        guard let subject else { return }
        guard let episode else {
            LuHUD.shared.show("没有可播放的剧集")
            return
        }
        guard !pluginStore.enabledPlugins.isEmpty else {
            pendingEpisode = episode
            showManualInput = true
            return
        }

        isResolving = true
        let stream = await resolveStream(for: episode)
        isResolving = false

        if let stream {
            playback = PlaybackRequest(subject: subject, episode: episode,
                                       stream: stream, episodes: episodes)
        } else {
            LuHUD.shared.show("这个源没有解析到地址，换个直链试试")
            pendingEpisode = episode
            showManualInput = true
        }
    }

    // MARK: - 换源

    /// 一次并发搜所有启用的源，用命中数判断哪个源有这部番
    @MainActor
    private func probeSources() async {
        guard !probing, let subject else { return }
        probing = true
        probe.removeAll()
        let keyword = subject.displayName
        let plugins = pluginStore.enabledPlugins
        var collected: [String: SourceProbe] = [:]
        await withTaskGroup(of: (String, SourceProbe).self) { group in
            for plugin in plugins {
                group.addTask {
                    do {
                        let items = try await PluginEngine.shared.search(plugin: plugin,
                                                                         keyword: keyword)
                        return (plugin.id, SourceProbe(count: items.count,
                                                       first: items.first?.name ?? "—",
                                                       error: nil))
                    } catch {
                        return (plugin.id, SourceProbe(count: 0, first: "",
                                                       error: error.localizedDescription))
                    }
                }
            }
            for await (id, result) in group { collected[id] = result }
        }
        probe = collected
        probing = false
        let hit = collected.values.filter { $0.count > 0 }.count
        LuHUD.shared.show(hit > 0 ? "有 \(hit) 个源命中" : "所有源都没命中")
        luLogInfo("Plugin", "多源探测：\(hit)/\(plugins.count) 命中")
    }

    private var sourceSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if pluginStore.enabledPlugins.isEmpty {
                        LuEmptyState(symbol: "puzzlepiece.extension",
                                     title: "还没有可用的源",
                                     message: "到「我的 → 播放源插件」导入 Kazumi 插件 JSON")
                    } else {
                        LuGroup {
                            ForEach(pluginStore.enabledPlugins.indices, id: \.self) { index in
                                let plugin = pluginStore.enabledPlugins[index]
                                Button {
                                    activePluginID = plugin.id
                                    sourceSheetShown = false
                                    LuHUD.shared.show("已切换到 \(plugin.name)")
                                } label: {
                                    HStack(spacing: 10) {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(plugin.name)
                                                .font(.system(size: 15, weight: .medium))
                                                .foregroundStyle(LuTheme.label)
                                            Text(URL(string: plugin.baseURL)?.host ?? plugin.baseURL)
                                                .font(.system(size: 11))
                                                .foregroundStyle(LuTheme.tertiary)
                                                .lineLimit(1)
                                            if let result = probe[plugin.id] {
                                                Text(result.error.map { "探测失败：\($0)" }
                                                     ?? "命中 \(result.count) 条 · \(result.first)")
                                                    .font(.system(size: 10))
                                                    .foregroundStyle(result.error == nil
                                                                     ? LuTheme.accent : Color.red)
                                                    .lineLimit(1)
                                            }
                                        }
                                        Spacer()
                                        if activePlugin?.id == plugin.id {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundStyle(LuTheme.accent)
                                        }
                                    }
                                    .padding(.horizontal, 12)
                                    .frame(height: 54)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                if index < pluginStore.enabledPlugins.count - 1 {
                                    Rectangle().fill(LuTheme.hairline)
                                        .frame(height: 0.5).padding(.leading, 12)
                                }
                            }
                        }
                        Button {
                            Task { await probeSources() }
                        } label: {
                            HStack(spacing: 6) {
                                if probing {
                                    ProgressView().scaleEffect(0.7)
                                } else {
                                    Image(systemName: "dot.radiowaves.left.and.right")
                                }
                                Text(probing ? "正在并发探测…" : "并发探测所有源")
                            }
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(LuTheme.accent)
                            .frame(maxWidth: .infinity)
                            .frame(height: 42)
                            .luGlass(.thin, cornerRadius: 12)
                        }
                        .buttonStyle(.plain)
                        .disabled(probing)

                        Text("换源只影响之后的解析，正在播放的这一集不会自动重载。")
                            .font(.system(size: 11))
                            .foregroundStyle(LuTheme.tertiary)
                            .padding(.horizontal, 4)
                    }
                }
                .padding(16)
            }
            .navigationTitle("选择播放源")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { sourceSheetShown = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - 手动直链

    private var manualInputSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("粘贴 m3u8 / mp4 直链，或用插件解析。当前没有可用插件时先手动播放。")
                    .font(LuTheme.caption())
                    .foregroundStyle(LuTheme.secondary)

                TextField("https://…/index.m3u8", text: $manualURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .font(.system(size: 14, design: .monospaced))
                    .padding(12)
                    .background {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color(uiColor: .tertiarySystemFill))
                    }

                Button {
                    startManualPlayback()
                } label: {
                    Text("播放")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(manualURL.isEmpty ? Color.gray : LuTheme.accent))
                }
                .disabled(manualURL.isEmpty)

                Spacer()
            }
            .padding(20)
            .navigationTitle("添加播放地址")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { showManualInput = false }
                }
            }
        }
        .presentationDetents([.height(300)])
    }

    private func startManualPlayback() {
        guard let subject, let url = URL(string: manualURL.trimmingCharacters(in: .whitespaces)) else {
            return
        }
        let episode = pendingEpisode ?? episodes.first
            ?? AnimeEpisode(id: 0, type: 0, name: "", nameCN: "", sort: 1, airdate: "", duration: "")
        let stream = PlayStream(url: url, quality: "直链", headers: [:])
        showManualInput = false
        playback = PlaybackRequest(subject: subject, episode: episode,
                                   stream: stream, episodes: episodes)
    }
}
