import Foundation

/// 直链解析：把用户粘贴的分享文本 / 网页链接，尽量变成能播的媒体地址。
///
/// 不做「解密会员视频」这类事，只做三件事：
/// 1. 文本里提取所有 http(s) 链接
/// 2. 本身就是 m3u8 / mp4 的直接用
/// 3. 是网页的，拉一次 HTML，抽出其中的媒体地址与 iframe（再进一层）
enum LuURLResolver {

    struct Candidate: Identifiable {
        let id = UUID()
        var url: URL
        var referer: String?
        var note: String

        var isHLS: Bool { url.pathExtension.lowercased() == "m3u8" }
    }

    static func extractLinks(from text: String) -> [URL] {
        var found: [URL] = []
        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
            let range = NSRange(text.startIndex..., in: text)
            detector.enumerateMatches(in: text, range: range) { result, _, _ in
                if let url = result?.url { found.append(url) }
            }
        }
        if found.isEmpty {
            let pattern = #"https?://[^\s"'<>]+"#
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let range = NSRange(text.startIndex..., in: text)
                regex.matches(in: text, range: range).forEach { match in
                    if let r = Range(match.range, in: text), let url = URL(string: String(text[r])) {
                        found.append(url)
                    }
                }
            }
        }

        var seen = Set<String>()
        return found.filter { seen.insert($0.absoluteString).inserted }
    }

    static func resolve(text: String) async -> [Candidate] {
        let links = Array(extractLinks(from: text).prefix(3))
        guard !links.isEmpty else { return [] }

        var candidates: [Candidate] = []
        for link in links {
            let ext = link.pathExtension.lowercased()
            if ["m3u8", "mp4", "mov", "mkv"].contains(ext) {
                candidates.append(Candidate(url: link, referer: link.absoluteString,
                                            note: "链接本身是媒体文件"))
                continue
            }

            guard let data = try? await HttpClient.shared.send(
                .get(link, headers: ["Referer": link.absoluteString])
            ), let html = String(data: data, encoding: .utf8) else {
                continue
            }

            let medias = PluginEngine.extractMediaURLs(from: html)
            for raw in medias.prefix(4) {
                if let url = URL(string: raw) {
                    candidates.append(Candidate(url: url, referer: link.absoluteString,
                                                note: "页面内媒体地址"))
                }
            }

            if medias.isEmpty {
                // 播放页通常是 iframe 里再套一层
                for iframe in PluginEngine.extractIframes(from: html, base: link).prefix(2) {
                    guard let inner = try? await HttpClient.shared.send(
                        .get(iframe, headers: ["Referer": link.absoluteString])
                    ), let innerHTML = String(data: inner, encoding: .utf8) else { continue }
                    for raw in PluginEngine.extractMediaURLs(from: innerHTML).prefix(4) {
                        if let url = URL(string: raw) {
                            candidates.append(Candidate(url: url, referer: iframe.absoluteString,
                                                        note: "iframe 内媒体地址"))
                        }
                    }
                }
            }
        }

        var seen = Set<String>()
        return candidates.filter { seen.insert($0.url.absoluteString).inserted }
    }

    /// 把候选包装成播放器能用的流
    static func stream(from candidate: Candidate) -> PlayStream {
        var headers: [String: String] = [:]
        if let referer = candidate.referer { headers["Referer"] = referer }
        return PlayStream(url: candidate.url, quality: "直链", headers: headers)
    }
}
