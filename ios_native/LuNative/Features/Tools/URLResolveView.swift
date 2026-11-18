import SwiftUI
import UIKit

/// 直链解析：粘贴分享文本或网页链接，抽出能播的媒体地址。
/// 支持直接播放 / 复制 / 加入离线下载。
struct URLResolveView: View {
    @State private var text = ""
    @State private var candidates: [LuURLResolver.Candidate] = []
    @State private var loading = false
    @State private var error: String?
    @State private var playback: DirectPlayback?

    private struct DirectPlayback: Identifiable {
        let id = UUID()
        let subject: AnimeSubject
        let episode: AnimeEpisode
        let stream: PlayStream
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                LuPageHeader(title: "直链解析", subtitle: "分享链接 → 可播放地址")

                VStack(alignment: .leading, spacing: 8) {
                    TextEditor(text: $text)
                        .font(.system(size: 13, design: .monospaced))
                        .frame(minHeight: 88, maxHeight: 140)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 12)
                            .fill(Color(uiColor: .tertiarySystemFill)))
                        .overlay(alignment: .topLeading) {
                            if text.isEmpty {
                                Text("粘贴网页链接或整段分享文案")
                                    .font(.system(size: 13))
                                    .foregroundStyle(LuTheme.tertiary)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 16)
                                    .allowsHitTesting(false)
                            }
                        }

                    HStack(spacing: 8) {
                        Button {
                            if let value = UIPasteboard.general.string { text = value }
                        } label: {
                            Text("粘贴")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(LuTheme.label)
                                .frame(maxWidth: .infinity)
                                .frame(height: 42)
                                .luGlass(.thin, cornerRadius: 12)
                        }
                        .buttonStyle(.plain)

                        Button {
                            Task { await resolve() }
                        } label: {
                            HStack(spacing: 6) {
                                if loading {
                                    ProgressView().scaleEffect(0.7)
                                } else {
                                    Image(systemName: "wand.and.stars")
                                }
                                Text(loading ? "解析中…" : "解析")
                            }
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 42)
                            .background(RoundedRectangle(cornerRadius: 12)
                                .fill(text.isEmpty ? Color.gray : LuTheme.accent))
                        }
                        .buttonStyle(.plain)
                        .disabled(text.isEmpty || loading)
                    }
                }

                if let error {
                    Text(error)
                        .font(.system(size: 12))
                        .foregroundStyle(.red)
                }

                if !candidates.isEmpty {
                    LuGroup(title: "找到 \(candidates.count) 个地址") {
                        ForEach(candidates) { candidate in
                            row(candidate)
                            if candidate.id != candidates.last?.id {
                                Rectangle().fill(LuTheme.hairline)
                                    .frame(height: 0.5).padding(.leading, 12)
                            }
                        }
                    }
                } else if !loading && error == nil {
                    Text("解析只做三件事：从文案里提链接、链接本身是 m3u8/mp4 就直接用、是网页就抓一次 HTML 找媒体地址和 iframe。会员加密流、需要登录的页面解析不了。")
                        .font(.system(size: 11))
                        .foregroundStyle(LuTheme.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)
            }
            .padding(.horizontal, LuTheme.pagePadding)
            .padding(.bottom, 28)
        }
        .background(LuTheme.canvas.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $playback) { item in
            PlayerView(subject: item.subject,
                       episode: item.episode,
                       stream: item.stream,
                       episodes: [item.episode],
                       resolveStream: { _ in nil })
        }
    }

    private func row(_ candidate: LuURLResolver.Candidate) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(candidate.isHLS ? "HLS" : "文件")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(LuTheme.accent)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(LuTheme.accent.opacity(0.14)))
                Text(candidate.note)
                    .font(.system(size: 10))
                    .foregroundStyle(LuTheme.tertiary)
                Spacer()
            }

            Text(candidate.url.absoluteString)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(LuTheme.secondary)
                .lineLimit(2)
                .textSelection(.enabled)

            HStack(spacing: 8) {
                action("播放", symbol: "play.fill") { play(candidate) }
                action("复制", symbol: "doc.on.doc") {
                    UIPasteboard.general.string = candidate.url.absoluteString
                    LuHUD.shared.show("已复制")
                }
                action("下载", symbol: "arrow.down.circle") {
                    DownloadManager.shared.enqueue(stream: LuURLResolver.stream(from: candidate),
                                                   subjectID: 0,
                                                   subjectName: "直链",
                                                   episodeID: 0,
                                                   episodeName: candidate.url.lastPathComponent)
                    LuHUD.shared.show("已加入下载队列")
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func action(_ title: String, symbol: String,
                        action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 10))
                Text(title).font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(LuTheme.accent)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(Capsule().fill(LuTheme.accent.opacity(0.10)))
        }
        .buttonStyle(.plain)
    }

    @MainActor
    private func resolve() async {
        loading = true
        error = nil
        candidates = []
        let found = await LuURLResolver.resolve(text: text)
        candidates = found
        loading = false
        if found.isEmpty {
            error = "没有找到可播放地址。可能是需要登录的页面，或者媒体地址是动态加载的。"
        } else {
            LuHUD.shared.show("解析到 \(found.count) 个地址")
        }
    }

    private func play(_ candidate: LuURLResolver.Candidate) {
        let host = candidate.url.host ?? "直链"
        let subject = AnimeSubject(id: -abs(candidate.url.absoluteString.hashValue),
                                   name: host, nameCN: "直链播放", summary: "",
                                   images: [:], airDate: "", airWeekday: 0, eps: 1,
                                   platform: "", ratingScore: 0, ratingRank: 0,
                                   ratingTotal: 0, tags: [])
        let episode = AnimeEpisode(id: 1, type: 0, name: "第 1 话", nameCN: "",
                                   sort: 1, airdate: "", duration: "")
        playback = DirectPlayback(subject: subject, episode: episode,
                                  stream: LuURLResolver.stream(from: candidate))
    }
}
