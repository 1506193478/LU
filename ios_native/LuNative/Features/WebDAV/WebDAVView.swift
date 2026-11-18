import SwiftUI

struct WebDAVPlayback: Identifiable {
    let id = UUID()
    var entry: WebDAVEntry
    var stream: PlayStream
    var subtitle: SubtitleTrack?
}

/// WebDAV 文件浏览与直接播放。配置在设置页填写。
struct WebDAVView: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    @State private var path = "/"
    @State private var entries: [WebDAVEntry] = []
    @State private var isLoading = false
    @State private var error: String?
    @State private var playback: WebDAVPlayback?

    private var client: WebDAVClient? { WebDAVClient.fromSettings(settings) }

    var body: some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    LuPageHeader(title: "WebDAV", subtitle: path) {
                        LuIconButton(symbol: "arrow.clockwise") {
                            Task { await load(path) }
                        }
                    }

                    if client == nil {
                        configureHint
                    } else {
                        breadcrumb
                        LuAsyncContent(isLoading: isLoading, error: error,
                                       retry: { Task { await load(path) } }) {
                            if entries.isEmpty {
                                LuEmptyState(symbol: "folder",
                                             title: "这个目录是空的",
                                             message: "或者服务器不支持 PROPFIND")
                            } else {
                                LuGroup {
                                    ForEach(entries.indices, id: \.self) { index in
                                        let entry = entries[index]
                                        row(entry)
                                        if index < entries.count - 1 {
                                            Rectangle().fill(LuTheme.hairline)
                                                .frame(height: 0.5)
                                                .padding(.leading, 52)
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
                    LuIconButton(symbol: "chevron.left", size: 16) { dismiss() }
                    Spacer()
                }
                .padding(.horizontal, LuTheme.pagePadding)
                Spacer()
            }
        }
        .task { await load(path) }
        .fullScreenCover(item: $playback) { request in
            PlayerView(subject: OfflineMedia.subject(id: 0, name: request.entry.name),
                       episode: OfflineMedia.episode(id: 0, name: request.entry.name, sort: 1),
                       stream: request.stream,
                       episodes: [OfflineMedia.episode(id: 0, name: request.entry.name, sort: 1)],
                       initialSubtitle: request.subtitle,
                       resolveStream: { _ in nil })
        }
    }

    private var configureHint: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("还没有配置 WebDAV")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(LuTheme.label)
            Text("到「我的 → 设置 → WebDAV」填写服务器地址与账号，回来即可浏览网盘里的番剧。")
                .font(LuTheme.caption())
                .foregroundStyle(LuTheme.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .luGlass(.thin, cornerRadius: 12)
    }

    private var breadcrumb: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(components.indices, id: \.self) { index in
                    let item = components[index]
                    Button {
                        Task { await load(item.path) }
                    } label: {
                        Text(item.title)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(LuTheme.accent)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Color(uiColor: .tertiarySystemFill)))
                    }
                    .buttonStyle(.plain)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(LuTheme.tertiary)
                }
            }
        }
    }

    /// `/a/b/c` → 根 + 每级可点
    private var components: [(title: String, path: String)] {
        var result: [(title: String, path: String)] = [("根目录", "/")]
        var current = ""
        for piece in path.split(separator: "/") {
            current += "/" + piece
            result.append((title: String(piece), path: current))
        }
        return result
    }

    private func row(_ entry: WebDAVEntry) -> some View {
        Button {
            if entry.isDirectory {
                Task { await load(entry.path) }
            } else if entry.isVideo {
                Task { await play(entry) }
            } else {
                LuHUD.shared.show("不支持的文件类型")
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: entry.isDirectory ? "folder.fill" : icon(entry))
                    .font(.system(size: 16))
                    .foregroundStyle(entry.isDirectory ? LuTheme.accent : LuTheme.secondary)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.name)
                        .font(.system(size: 15))
                        .foregroundStyle(LuTheme.label)
                        .lineLimit(1)
                    Text(entry.isDirectory ? "文件夹" : entry.sizeText)
                        .font(.system(size: 11))
                        .foregroundStyle(LuTheme.tertiary)
                }
                Spacer()
                if entry.isVideo {
                    Image(systemName: "play.circle")
                        .foregroundStyle(LuTheme.accent)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            if entry.isVideo, client != nil {
                Button {
                    Task { await play(entry) }
                } label: { Label("播放", systemImage: "play.fill") }
                Button {
                    Task { await enqueue(entry) }
                } label: { Label("下载", systemImage: "arrow.down.circle") }
            }
        }
    }

    private func icon(_ entry: WebDAVEntry) -> String {
        entry.isVideo ? "film" : entry.isSubtitle ? "text.bubble" : "doc"
    }

    // MARK: 数据

    @MainActor
    private func load(_ target: String) async {
        guard let client else { return }
        isLoading = true
        error = nil
        do {
            let list = try await client.list(target)
            entries = list
            path = target
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    @MainActor
    private func play(_ entry: WebDAVEntry) async {
        guard let client, let stream = client.stream(for: entry) else { return }
        LuHUD.shared.show("正在准备字幕…")
        let subtitle = await client.sidecarSubtitle(for: entry)
        playback = WebDAVPlayback(entry: entry, stream: stream, subtitle: subtitle)
    }

    private func enqueue(_ entry: WebDAVEntry) async {
        guard let client, let stream = client.stream(for: entry) else { return }
        await MainActor.run {
            DownloadManager.shared.enqueue(stream: stream,
                                           subjectID: 0,
                                           subjectName: "WebDAV",
                                           episodeID: entry.path.hashValue,
                                           episodeName: entry.name)
            LuHUD.shared.show("已加入下载")
        }
    }
}
