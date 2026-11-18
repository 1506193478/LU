import Foundation
import CryptoKit
import Compression

/// 标题归一化与相似度打分。
///
/// 直接移植 Flutter 侧 `lib/utils/title_match.dart`：中日文标题里混着全角标点、
/// 书名号、季数后缀，先归一化再按「完全相等 → 互相包含 → 公共前缀」分级打分。
enum LuTitleMatch {

    static func normalize(_ input: String) -> String {
        var buffer = String()
        buffer.reserveCapacity(input.count)
        for scalar in input.lowercased().unicodeScalars {
            let v = scalar.value
            let isDigit = v >= 0x30 && v <= 0x39
            let isLower = v >= 0x61 && v <= 0x7A
            let isKana = v >= 0x3040 && v <= 0x30FF
            let isCJK = (v >= 0x4E00 && v <= 0x9FFF)
                || (v >= 0x3400 && v <= 0x4DBF)
                || (v >= 0xF900 && v <= 0xFAFF)
            if isDigit || isLower || isKana || isCJK {
                buffer.unicodeScalars.append(scalar)
            }
        }
        return buffer
    }

    /// 0–100 的相似度，入参需先归一化。
    static func similarity(_ a: String, _ b: String) -> Int {
        if a.isEmpty || b.isEmpty { return 0 }
        if a == b { return 100 }
        if a.contains(b) || b.contains(a) {
            let shorter = min(a.count, b.count)
            let longer = max(a.count, b.count)
            return 60 + (40 * shorter) / max(longer, 1)
        }
        let limit = min(a.count, b.count)
        var common = 0
        let aChars = Array(a), bChars = Array(b)
        while common < limit, aChars[common] == bChars[common] { common += 1 }
        guard common > 0 else { return 0 }
        return (40 * common) / max(a.count, b.count)
    }

    static func best(_ query: String, among candidates: [String]) -> Int {
        let normalized = normalize(query)
        guard !normalized.isEmpty else { return 0 }
        var best = 0
        for candidate in candidates {
            let value = similarity(normalized, normalize(candidate))
            if value > best { best = value }
        }
        return best
    }
}

// MARK: - B 站弹幕

enum DanmakuError: LocalizedError {
    case riskControl
    case noSeason
    case noEpisode
    case empty

    var errorDescription: String? {
        switch self {
        case .riskControl: return "B 站接口触发风控，稍后再试"
        case .noSeason: return "没有匹配到 B 站番剧"
        case .noEpisode: return "这一集在 B 站没有对应剧集"
        case .empty: return "该集没有弹幕"
        }
    }
}

struct BilibiliSeason: Identifiable, Hashable {
    let seasonID: Int
    let title: String
    let originalTitle: String
    let episodeCount: Int
    var id: Int { seasonID }
}

struct BilibiliEpisode: Identifiable, Hashable {
    let number: Int
    let title: String
    let longTitle: String
    let cid: Int
    var id: Int { cid }
}

/// 免凭据的 B 站弹幕源。对照 Flutter 侧 `lib/request/apis/bilibili_danmaku_api.dart`：
///
/// 1. 优先用 Bangumi 条目 id 走 `api.bgm.tv` 的 `sites` 字段直接拿 season_id（最准）
/// 2. 拿不到再用 wbi 签名搜索番剧名
/// 3. `pgc/view/web/season` 取每集 cid
/// 4. `comment.bilibili.com/{cid}.xml`（明文）或 `x/v1/dm/list.so`（deflate）取弹幕
final class BilibiliDanmaku {
    static let shared = BilibiliDanmaku()

    private let host = "https://api.bilibili.com"
    private let lock = NSLock()
    private var cachedMixinKey: String?
    private var mixinFetchedAt: Date?

    private var headers: [String: String] {
        ["Referer": "https://www.bilibili.com",
         "User-Agent": LuUserAgent.value,
         "Accept": "application/json, text/plain, */*"]
    }

    // MARK: 对外入口

    func fetch(bangumiID: Int?, title: String, originalTitle: String?,
               episode: Double) async throws -> [DanmakuComment] {
        var resolvedSeason: Int?
        if let bangumiID, bangumiID > 0 {
            resolvedSeason = await seasonID(forBangumi: bangumiID)
        }
        if resolvedSeason == nil {
            let seasons = try await searchSeasons(title)
            resolvedSeason = pickSeason(seasons, title: title, originalTitle: originalTitle)?.seasonID
        }
        guard let seasonID = resolvedSeason else { throw DanmakuError.noSeason }

        let list = try await episodes(seasonID: seasonID)
        guard !list.isEmpty else { throw DanmakuError.noEpisode }
        let index = Int(episode.rounded()) - 1
        guard index >= 0, index < list.count else { throw DanmakuError.noEpisode }

        let xml = try await danmakuXML(cid: list[index].cid)
        let comments = parse(xml)
        guard !comments.isEmpty else { throw DanmakuError.empty }
        luLogInfo("Bilibili", "cid \(list[index].cid) → \(comments.count) 条弹幕")
        return comments
    }

    // MARK: Bangumi → B 站 season

    func seasonID(forBangumi subjectID: Int) async -> Int? {
        guard let url = URL(string: "https://api.bgm.tv/subject/\(subjectID)?responseGroup=large") else {
            return nil
        }
        do {
            let data = try await HttpClient.shared.send(.get(url, headers: ["User-Agent": LuUserAgent.value]))
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let sites = object["sites"] as? [[String: Any]] else { return nil }
            for site in sites {
                guard let name = (site["site"] as? String)?.lowercased(),
                      name.contains("bilibili") else { continue }
                if let raw = site["id"] as? Int { return raw }
                if let raw = site["id"] as? String, let value = Int(raw) { return value }
            }
        } catch {
            luLogWarn("Bilibili", "bgm sites 查询失败：\(error.localizedDescription)")
        }
        return nil
    }

    // MARK: 搜索

    func searchSeasons(_ keyword: String) async throws -> [BilibiliSeason] {
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let query = try await signedQuery([
            "search_type": "media_bangumi",
            "keyword": trimmed,
            "page": "1"
        ])
        guard let url = URL(string: host + "/x/web-interface/wbi/search/type?" + query) else { return [] }
        let data = try await HttpClient.shared.send(.get(url, headers: headers))
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw DanmakuError.riskControl
        }
        if let code = object["code"] as? Int, code != 0 {
            throw DanmakuError.riskControl
        }
        guard let payload = object["data"] as? [String: Any],
              let result = payload["result"] as? [[String: Any]] else { return [] }

        var seasons: [BilibiliSeason] = []
        for item in result {
            let seasonID = intValue(item["season_id"]) ?? intValue(item["pgc_season_id"]) ?? 0
            guard seasonID > 0 else { continue }
            seasons.append(BilibiliSeason(
                seasonID: seasonID,
                title: stripHTML(stringValue(item["title"])),
                originalTitle: stripHTML(stringValue(item["org_title"])),
                episodeCount: intValue(item["ep_size"]) ?? 0
            ))
        }
        return seasons
    }

    /// 配音版 / 剧场版等同 IP 变体降权，避免抢走正片。
    private let dubMarkers = ["中配版", "中配", "国语", "普通话", "粤语", "台配"]
    private let movieMarkers = ["剧场版", "总集篇", "电影"]

    func pickSeason(_ seasons: [BilibiliSeason], title: String,
                    originalTitle: String?) -> BilibiliSeason? {
        guard !seasons.isEmpty else { return nil }
        let cn = LuTitleMatch.normalize(title)
        let org = originalTitle.map { LuTitleMatch.normalize($0) } ?? ""
        guard !cn.isEmpty || !org.isEmpty else { return seasons.first }

        var best: BilibiliSeason?
        var bestScore = 0
        for season in seasons {
            let seasonTitle = LuTitleMatch.normalize(season.title)
            let seasonOrg = LuTitleMatch.normalize(season.originalTitle)
            var score = 0
            if !cn.isEmpty, !seasonTitle.isEmpty {
                score = max(score, LuTitleMatch.similarity(cn, seasonTitle))
            }
            if !org.isEmpty, !seasonOrg.isEmpty {
                score = max(score, LuTitleMatch.similarity(org, seasonOrg) * 95 / 100)
            }
            guard score > 0 else { continue }
            let requested = cn + org
            for marker in dubMarkers where season.title.contains(marker) && !requested.contains(LuTitleMatch.normalize(marker)) {
                score -= 12
            }
            for marker in movieMarkers where season.title.contains(marker) && !requested.contains(LuTitleMatch.normalize(marker)) {
                score -= 8
            }
            if score > bestScore {
                bestScore = score
                best = season
            }
        }
        return bestScore >= 60 ? best : nil
    }

    // MARK: 剧集

    func episodes(seasonID: Int) async throws -> [BilibiliEpisode] {
        guard let url = URL(string: host + "/pgc/view/web/season?season_id=\(seasonID)") else { return [] }
        let data = try await HttpClient.shared.send(.get(url, headers: headers))
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = object["result"] as? [String: Any],
              let raw = result["episodes"] as? [[String: Any]] else { return [] }

        var list: [BilibiliEpisode] = []
        var number = 0
        for item in raw {
            let cid = intValue(item["cid"]) ?? 0
            guard cid > 0 else { continue }
            number += 1
            list.append(BilibiliEpisode(number: number,
                                        title: stringValue(item["title"]),
                                        longTitle: stringValue(item["long_title"]),
                                        cid: cid))
        }
        return list
    }

    // MARK: 弹幕 XML

    func danmakuXML(cid: Int) async throws -> String {
        guard cid > 0 else { throw DanmakuError.noEpisode }

        // 明文接口优先，省一次解压
        if let url = URL(string: "https://comment.bilibili.com/\(cid).xml"),
           let data = try? await HttpClient.shared.send(.get(url, headers: headers)),
           let text = String(data: data, encoding: .utf8),
           text.contains("<d ") {
            return text
        }

        guard let url = URL(string: host + "/x/v1/dm/list.so?oid=\(cid)") else {
            throw DanmakuError.empty
        }
        let raw = try await HttpClient.shared.send(.get(url, headers: headers))
        if let text = inflate(raw).flatMap({ String(data: $0, encoding: .utf8) }), !text.isEmpty {
            return text
        }
        if let text = String(data: raw, encoding: .utf8), text.contains("<d ") {
            return text
        }
        throw DanmakuError.empty
    }

    /// 裸 deflate（无 zlib 头）也要能吃下，所以原始字节先判断是不是 `<`。
    private func inflate(_ data: Data) -> Data? {
        guard !data.isEmpty else { return nil }
        if data[data.startIndex] == 0x3C { return data }
        let capacity = max(data.count * 10, 256 * 1024)
        var output = Data(count: capacity)
        let written = output.withUnsafeMutableBytes { destination -> Int in
            guard let dst = destination.bindMemory(to: UInt8.self).baseAddress else { return 0 }
            return data.withUnsafeBytes { source -> Int in
                guard let src = source.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                return compression_decode_buffer(dst, capacity, src, data.count, nil, COMPRESSION_ZLIB)
            }
        }
        guard written > 0 else { return nil }
        return Data(output.prefix(written))
    }

    private static let entryPattern = try! NSRegularExpression(
        pattern: #"<d p="([^"]*)"[^>]*>(.*?)</d>"#,
        options: [.dotMatchesLineSeparators]
    )

    func parse(_ xml: String) -> [DanmakuComment] {
        let range = NSRange(xml.startIndex..., in: xml)
        let matches = Self.entryPattern.matches(in: xml, range: range)
        var comments: [DanmakuComment] = []
        comments.reserveCapacity(matches.count)
        for (index, match) in matches.enumerated() {
            guard match.numberOfRanges >= 3,
                  let pRange = Range(match.range(at: 1), in: xml),
                  let tRange = Range(match.range(at: 2), in: xml) else { continue }
            let parts = String(xml[pRange]).split(separator: ",")
            guard parts.count >= 4,
                  let time = Double(parts[0]) else { continue }
            let mode = Int(parts[1]) ?? 1
            let color = Int(parts[3]) ?? 0xFFFFFF
            let text = decodeEntities(String(xml[tRange])).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            comments.append(DanmakuComment(id: index + 1,
                                           time: time,
                                           text: text,
                                           colorHex: color,
                                           mode: mapMode(mode)))
        }
        return comments
    }

    private func mapMode(_ raw: Int) -> Int {
        switch raw {
        case 4: return 4
        case 5: return 5
        default: return 1
        }
    }

    // MARK: wbi 签名

    private func signedQuery(_ params: [String: String]) async throws -> String {
        let key = try await mixinKey()
        var filtered: [String: String] = [:]
        for (name, value) in params {
            filtered[name] = value.replacingOccurrences(of: "[!'()*]", with: "",
                                                        options: .regularExpression)
        }
        filtered["wts"] = String(Int(Date().timeIntervalSince1970))
        let query = filtered.keys.sorted().map { name in
            "\(encode(name))=\(encode(filtered[name] ?? ""))"
        }.joined(separator: "&")
        let digest = Insecure.MD5.hash(data: Data((query + key).utf8))
        let signature = digest.map { String(format: "%02x", $0) }.joined()
        return query + "&w_rid=" + signature
    }

    private func mixinKey() async throws -> String {
        lock.lock()
        if let cachedMixinKey, let fetched = mixinFetchedAt,
           Date().timeIntervalSince(fetched) < 6 * 3600 {
            lock.unlock()
            return cachedMixinKey
        }
        lock.unlock()

        guard let url = URL(string: host + "/x/web-interface/nav") else { throw DanmakuError.riskControl }
        let data = try await HttpClient.shared.send(.get(url, headers: headers))
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let payload = object["data"] as? [String: Any],
              let wbi = payload["wbi_img"] as? [String: Any],
              let img = wbi["img_url"] as? String,
              let sub = wbi["sub_url"] as? String else {
            throw DanmakuError.riskControl
        }
        let raw = stripKey(img) + stripKey(sub)
        let table = [46, 47, 18, 2, 53, 8, 23, 32, 15, 50, 10, 31, 58, 3, 45, 35,
                     27, 43, 5, 49, 33, 9, 42, 19, 29, 28, 14, 39, 12, 38, 41, 13,
                     37, 48, 7, 16, 24, 55, 40, 61, 26, 17, 0, 1, 60, 51, 30, 4,
                     22, 25, 54, 21, 56, 59, 6, 63, 57, 62, 11, 36, 20, 34, 44, 52]
        let chars = Array(raw)
        var mixed = String()
        for index in table where index < chars.count {
            mixed.append(chars[index])
        }
        guard mixed.count >= 32 else { throw DanmakuError.riskControl }
        let key = String(mixed.prefix(32))
        lock.lock()
        cachedMixinKey = key
        mixinFetchedAt = Date()
        lock.unlock()
        luLogInfo("Bilibili", "wbi key 已刷新")
        return key
    }

    private func stripKey(_ url: String) -> String {
        guard let name = url.split(separator: "/").last else { return "" }
        return String(name.split(separator: ".").first ?? name)
    }

    /// 对齐 `encodeURIComponent`：只保留字母数字与 `-_.~`。
    private func encode(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-_.~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    // MARK: 工具

    private func decodeEntities(_ input: String) -> String {
        guard input.contains("&") else { return input }
        var text = input
        let map = ["&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&apos;": "'"]
        for (key, value) in map {
            text = text.replacingOccurrences(of: key, with: value)
        }
        return text
    }

    private func stripHTML(_ input: String) -> String {
        guard !input.isEmpty else { return "" }
        let text = input.replacingOccurrences(of: "<[^>]+>", with: "",
                                              options: .regularExpression)
        return decodeEntities(text).trimmingCharacters(in: .whitespaces)
    }

    private func stringValue(_ any: Any?) -> String {
        if let value = any as? String { return value }
        if let value = any as? Int { return String(value) }
        return ""
    }

    private func intValue(_ any: Any?) -> Int? {
        if let value = any as? Int { return value }
        if let value = any as? Double { return Int(value) }
        if let value = any as? String { return Int(value) }
        return nil
    }
}
