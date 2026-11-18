import SwiftUI

// MARK: - 离线播放请求

struct OfflinePlaybackRequest: Identifiable {
    let id = UUID()
    var subject: AnimeSubject
    var episode: AnimeEpisode
    var stream: PlayStream
    var episodes: [AnimeEpisode]
    var subtitle: SubtitleTrack?
}

/// 本地文件播放时没有 Bangumi 条目，这里合成一个最小可用的数据模型。
enum OfflineMedia {
    static func subject(id: Int, name: String) -> AnimeSubject {
        AnimeSubject(id: id, name: name, nameCN: name, summary: "",
                     images: [:], airDate: "", airWeekday: 0, eps: 0,
                     platform: "", ratingScore: 0, ratingRank: 0,
                     ratingTotal: 0, tags: [])
    }

    static func episode(id: Int, name: String, sort: Double) -> AnimeEpisode {
        AnimeEpisode(id: id, type: 0, name: name, nameCN: name, sort: sort,
                     airdate: "", duration: "")
    }
}

// MARK: - 下载页

struct DownloadsView: View {
    @ObservedObject private var manager = DownloadManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var playback: OfflinePlaybackRequest?
    @State private var confirmClear = false

    var body: some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    LuPageHeader(title: "离线下载",
                                 subtitle: "已占用 \(sizeText(manager.totalBytes))") {
                        if !manager.records.isEmpty {
                            LuIconButton(symbol: "trash") { confirmClear = true }
                        }
                    }

                    if manager.records.isEmpty {
                        LuEmptyState(symbol: "arrow.down.circle",
                                     title: "还没有下载",
                                     message: "在播放器右上角的下载按钮里，把当前这一集存到本地")
                    } else {
                        ForEach(manager.records) { record in
                            row(record)
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
        .fullScreenCover(item: $playback) { request in
            PlayerView(subject: request.subject,
                       episode: request.episode,
                       stream: request.stream,
                       episodes: request.episodes,
                       initialSubtitle: request.subtitle,
                       resolveStream: { _ in nil })
        }
        .confirmationDialog("清空已完成的任务？", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("清空已完成与失败", role: .destructive) {
                manager.clearFinished()
                LuHUD.shared.show("已清理")
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("会删除已下载的文件，未完成的任务保留。")
        }
    }

    private func row(_ record: DownloadRecord) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(record.subjectName)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(LuTheme.label)
                        .lineLimit(1)
                    Text("\(record.episodeName) · \(record.quality)")
                        .font(LuTheme.caption())
                        .foregroundStyle(LuTheme.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                stateBadge(record)
            }

            if record.state == .running {
                ProgressView(value: max(0.01, record.progress))
                    .tint(LuTheme.accent)
            }

            HStack(spacing: 14) {
                Text(detail(record))
                    .font(.system(size: 11))
                    .foregroundStyle(LuTheme.tertiary)
                Spacer()
                actionButton(record)
            }
        }
        .padding(12)
        .luGlass(.thin, cornerRadius: 12)
        .contentShape(Rectangle())
        .onTapGesture {
            guard record.state == .finished else { return }
            play(record)
        }
        .contextMenu {
            if record.state == .finished {
                Button { play(record) } label: { Label("播放", systemImage: "play.fill") }
            }
            if record.state == .running {
                Button { manager.pause(record.id) } label: { Label("暂停", systemImage: "pause.fill") }
            }
            if record.state == .paused || record.state == .failed {
                Button { manager.resume(record.id) } label: { Label("继续", systemImage: "play.circle") }
            }
            Button(role: .destructive) { manager.remove(record.id) } label: {
                Label("删除", systemImage: "trash")
            }
        }
    }

    @ViewBuilder
    private func actionButton(_ record: DownloadRecord) -> some View {
        switch record.state {
        case .running:
            Button { manager.pause(record.id) } label: {
                Image(systemName: "pause.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(LuTheme.accent)
            }
            .buttonStyle(.plain)
        case .paused, .failed:
            Button { manager.resume(record.id) } label: {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(LuTheme.accent)
            }
            .buttonStyle(.plain)
        case .finished:
            Button { play(record) } label: {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(LuTheme.accent)
            }
            .buttonStyle(.plain)
        case .waiting:
            ProgressView().scaleEffect(0.7)
        }
    }

    private func stateBadge(_ record: DownloadRecord) -> some View {
        Text(record.state.title)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(color(record.state))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(color(record.state).opacity(0.14)))
    }

    private func color(_ state: DownloadState) -> Color {
        switch state {
        case .running: return LuTheme.accent
        case .finished: return .green
        case .failed: return .red
        default: return LuTheme.secondary
        }
    }

    private func detail(_ record: DownloadRecord) -> String {
        if let error = record.error, record.state == .failed { return error }
        if record.state == .finished {
            return sizeText(record.bytesWritten > 0 ? record.bytesWritten : record.totalBytes)
        }
        let written = sizeText(record.bytesWritten)
        if record.totalBytes > 0 {
            return "\(written) / \(sizeText(record.totalBytes))"
        }
        return written
    }

    private func sizeText(_ bytes: Int64) -> String {
        guard bytes > 0 else { return "0 MB" }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    private func play(_ record: DownloadRecord) {
        guard let url = manager.localURL(for: record) else {
            LuHUD.shared.show("文件不存在了")
            return
        }
        let subject = OfflineMedia.subject(id: record.subjectID, name: record.subjectName)
        let episode = OfflineMedia.episode(id: record.episodeID, name: record.episodeName, sort: 1)
        let stream = PlayStream(url: url, quality: record.quality, headers: [:])
        var subtitle: SubtitleTrack?
        if let sidecar = SubtitleParser.sidecarURL(for: url),
           let data = try? Data(contentsOf: sidecar) {
            subtitle = SubtitleParser.parse(data: data, url: sidecar)
        }
        playback = OfflinePlaybackRequest(subject: subject, episode: episode,
                                          stream: stream, episodes: [episode],
                                          subtitle: subtitle)
    }
}
