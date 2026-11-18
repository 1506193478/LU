import SwiftUI
import UIKit
import CryptoKit

// MARK: - 弹幕模型

struct DanmakuComment: Identifiable, Hashable {
    let id: Int
    var time: Double          // 出现时刻（秒）
    var text: String
    var colorHex: Int
    var mode: Int             // 1 滚动 / 4 底部 / 5 顶部

    var color: Color {
        let r = Double((colorHex >> 16) & 0xFF) / 255
        let g = Double((colorHex >> 8) & 0xFF) / 255
        let b = Double(colorHex & 0xFF) / 255
        return Color(red: r, green: g, blue: b)
    }
}

/// 弹幕数据源协议。默认走弹弹play，未配置凭据时为空。
protocol DanmakuProvider {
    func fetch(anime: String, episode: Double, episodeTitle: String) async throws -> [DanmakuComment]
}

// MARK: - 弹幕源选择

/// 弹幕接口来源。对照 Flutter 侧 `services/network/danmaku_source.dart`：
/// B 站免凭据按番剧自动匹配，弹弹play 需要自备开放平台密钥。
enum DanmakuSourceKind: String, CaseIterable, Identifiable {
    case bilibili
    case dandanplay
    case off

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bilibili: return "B 站"
        case .dandanplay: return "弹弹play"
        case .off: return "关闭"
        }
    }

    var detail: String {
        switch self {
        case .bilibili: return "免凭据，按番剧自动匹配"
        case .dandanplay: return "需自备开放平台密钥"
        case .off: return "不加载任何弹幕"
        }
    }
}

/// 一次弹幕请求所需的上下文。
struct DanmakuQuery {
    var title: String
    var originalTitle: String?
    var bangumiID: Int?
    var episode: Double
    var episodeTitle: String
}

/// 弹幕调度：按设置选择数据源，统一做屏蔽词与简繁转换。
final class DanmakuService {
    static let shared = DanmakuService()

    func fetch(query: DanmakuQuery) async throws -> [DanmakuComment] {
        let kind = DanmakuSourceKind(rawValue: AppSettings.shared.danmakuSource) ?? .bilibili
        var comments: [DanmakuComment]
        switch kind {
        case .off:
            return []
        case .bilibili:
            comments = try await BilibiliDanmaku.shared.fetch(
                bangumiID: query.bangumiID,
                title: query.title,
                originalTitle: query.originalTitle,
                episode: query.episode
            )
        case .dandanplay:
            comments = try await DandanplayProvider.shared.fetch(
                anime: query.title,
                episode: query.episode,
                episodeTitle: query.episodeTitle
            )
        }

        let mode = LuOpenCCMode(rawValue: AppSettings.shared.textConvert) ?? .off
        if mode != .off {
            comments = comments.map { comment in
                var copy = comment
                copy.text = LuOpenCC.shared.convert(comment.text, mode: mode)
                return copy
            }
        }
        let blocked = AppSettings.shared.shieldWords
            .split(whereSeparator: { $0 == "," || $0 == "，" || $0 == "\n" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if !blocked.isEmpty {
            comments = comments.filter { comment in
                !blocked.contains { comment.text.localizedCaseInsensitiveContains($0) }
            }
        }
        return comments
    }
}

// MARK: - 弹弹play

final class DandanplayProvider: DanmakuProvider {
    static let shared = DandanplayProvider()

    var appID: String = ""
    var appSecret: String = ""
    /// 由搜索命中的剧集 id
    private(set) var matchedEpisodeID: Int?

    private var configured: Bool { !appID.isEmpty && !appSecret.isEmpty }

    private func signedRequest(path: String, query: [URLQueryItem] = []) -> HttpRequest? {
        guard configured else { return nil }
        var components = URLComponents(string: "https://api.dandanplay.net" + path)!
        components.queryItems = query.isEmpty ? nil : query
        guard let url = components.url else { return nil }

        let timestamp = String(Int(Date().timeIntervalSince1970))
        let raw = appID + timestamp + path + appSecret
        let digest = Insecure.SHA1.hash(data: Data(raw.utf8))
        let signature = Data(digest).base64EncodedString()

        return HttpRequest.get(url, headers: [
            "X-AppId": appID,
            "X-Timestamp": timestamp,
            "X-Signature": signature,
            "Accept": "application/json"
        ])
    }

    func fetch(anime: String, episode: Double, episodeTitle: String) async throws -> [DanmakuComment] {
        guard configured else { return [] }

        // 1. 搜索番剧
        guard let searchReq = signedRequest(path: "/api/v2/search/episodes",
                                            query: [URLQueryItem(name: "anime", value: anime)]) else {
            return []
        }
        struct SearchResponse: Decodable {
            struct Animes: Decodable {
                struct Episodes: Decodable {
                    let episodeId: Int
                    let episodeTitle: String
                }
                let animeTitle: String
                let episodes: [Episodes]
            }
            let animes: [Animes]?
        }
        let searchResult = try await HttpClient.shared.json(searchReq, as: SearchResponse.self)
        guard let firstAnime = searchResult.animes?.first else { return [] }

        let matched = firstAnime.episodes.first { ep in
            !episodeTitle.isEmpty && ep.episodeTitle.contains(episodeTitle)
        } ?? firstAnime.episodes.first
        guard let matched else { return [] }
        matchedEpisodeID = matched.episodeId

        // 2. 拉弹幕
        guard let commentReq = signedRequest(path: "/api/v2/comment/\(matched.episodeId)",
                                             query: [URLQueryItem(name: "withRelated", value: "true"),
                                                     URLQueryItem(name: "chConvert", value: "1")]) else {
            return []
        }
        struct CommentResponse: Decodable {
            struct Comment: Decodable {
                let cid: Int
                let p: String
                let m: String
            }
            let comments: [Comment]?
        }
        let response = try await HttpClient.shared.json(commentReq, as: CommentResponse.self)
        return (response.comments ?? []).compactMap { item in
            let parts = item.p.split(separator: ",")
            guard parts.count >= 3, let time = Double(parts[0]) else { return nil }
            return DanmakuComment(id: item.cid,
                                  time: time,
                                  text: item.m,
                                  colorHex: Int(parts[2]) ?? 0xFFFFFF,
                                  mode: Int(parts[1]) ?? 1)
        }
    }
}

// MARK: - 渲染

struct LaidOutDanmaku: Identifiable {
    let id: Int
    let comment: DanmakuComment
    let lane: Int
    let width: CGFloat
}

/// 弹幕轨道布局：按出现时间贪心分配到最早空闲的轨道。
/// 结果一次性算好，渲染阶段只做纯函数位置计算——没有逐帧状态机。
enum DanmakuLayout {
    static func layout(_ comments: [DanmakuComment], fontSize: CGFloat,
                       canvasWidth: CGFloat, duration: Double) -> [LaidOutDanmaku] {
        let sorted = comments.sorted { $0.time < $1.time }
        var laneFreeAt: [Double] = []
        var result: [LaidOutDanmaku] = []

        for comment in sorted {
            let width = measure(comment.text, fontSize: fontSize)
            // 该条完全滚出屏幕所需时间
            let travel = Double((canvasWidth + width) / max(canvasWidth, 1)) * duration

            var lane = 0
            while lane < laneFreeAt.count && laneFreeAt[lane] > comment.time {
                lane += 1
            }
            if lane == laneFreeAt.count {
                laneFreeAt.append(0)
            }
            laneFreeAt[lane] = comment.time + travel * 0.92
            result.append(LaidOutDanmaku(id: comment.id, comment: comment,
                                         lane: lane, width: width))
        }
        return result
    }

    static func measure(_ text: String, fontSize: CGFloat) -> CGFloat {
        let font = UIFont.systemFont(ofSize: fontSize, weight: .semibold)
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        return (text as NSString).size(withAttributes: attributes).width
    }
}

/// 弹幕画布。`TimelineView(.animation)` 驱动，只重绘本层。
struct DanmakuLayer: View {
    let comments: [LaidOutDanmaku]
    let currentTime: Double
    let fontSize: CGFloat
    let opacity: Double
    let areaRatio: Double
    let isPlaying: Bool
    var speed: Double = 1.0

    /// 一条弹幕从右到左的全程时长（受设置里的速度影响）
    private var travelDuration: Double {
        max(2.0, 8.0 / max(speed, 0.1))
    }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let laneHeight = fontSize + 8
            let maxLanes = max(1, Int(geo.size.height * areaRatio / laneHeight))

            Canvas(rendersAsynchronously: true) { context, size in
                for item in comments {
                    let elapsed = currentTime - item.comment.time
                    guard elapsed >= 0, elapsed <= travelDuration else { continue }

                    let progress = elapsed / travelDuration
                    let x = size.width - progress * (size.width + item.width)

                    let lane = item.lane % maxLanes
                    let y = CGFloat(lane) * laneHeight + laneHeight / 2

                    var text = context.resolve(
                        Text(item.comment.text)
                            .font(.system(size: fontSize, weight: .semibold))
                            .foregroundColor(item.comment.color)
                    )
                    text.shading = .color(item.comment.color)

                    // 描边提升复杂背景下的可读性
                    var outline = context.resolve(
                        Text(item.comment.text)
                            .font(.system(size: fontSize, weight: .semibold))
                            .foregroundColor(.black.opacity(0.55))
                    )
                    outline.shading = .color(.black.opacity(0.55))
                    context.draw(outline, at: CGPoint(x: x + 1, y: y + 1), anchor: .leading)

                    context.draw(text, at: CGPoint(x: x, y: y), anchor: .leading)
                }
            }
            .opacity(opacity)
            .allowsHitTesting(false)
        }
        .allowsHitTesting(false)
    }
}
