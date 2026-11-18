import Foundation
import Combine

/// 采集源插件清单。字段对齐 Kazumi 的 XPath 插件格式（`api`/`type` 之外的
/// 解析规则全部保留），以便直接导入现有插件 JSON。
struct PluginManifest: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var version: String
    var author: String
    var baseURL: String
    var searchURL: String          // 支持 @keyword 占位
    var searchList: String         // XPath
    var searchName: String         // XPath（相对节点）
    var searchResult: String       // XPath，取 href
    var chapterRoads: String       // XPath，线路分组
    var chapterResult: String      // XPath，剧集节点
    var userAgent: String?
    var referer: String?
    var enabled: Bool

    // API 模式（对齐 Kazumi 的 `searchMode` / `chapterMode` + `*ApiConfig`）
    var searchMode: String = "xpath"      // xpath / api
    var chapterMode: String = "xpath"
    var usePost: Bool = false             // XPath 模式下把搜索参数改成表单 POST
    var searchApi: LuApiSearchConfig?
    var chapterApi: LuApiChapterConfig?

    enum CodingKeys: String, CodingKey {
        case id, name, version, author
        case baseURL = "baseURL"
        case searchURL, searchList, searchName, searchResult
        case chapterRoads, chapterResult
        case userAgent, referer, enabled
        case searchMode, chapterMode, usePost
        case searchApi, searchApiConfig
        case chapterApi, chapterApiConfig
    }

    /// 显式编码：CodingKeys 里的 searchApiConfig / chapterApiConfig 只是导入兼容别名，
    /// 合成 encode 会因「键与存储属性不对应」失败。
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(version, forKey: .version)
        try c.encode(author, forKey: .author)
        try c.encode(baseURL, forKey: .baseURL)
        try c.encode(searchURL, forKey: .searchURL)
        try c.encode(searchList, forKey: .searchList)
        try c.encode(searchName, forKey: .searchName)
        try c.encode(searchResult, forKey: .searchResult)
        try c.encode(chapterRoads, forKey: .chapterRoads)
        try c.encode(chapterResult, forKey: .chapterResult)
        try c.encodeIfPresent(userAgent, forKey: .userAgent)
        try c.encodeIfPresent(referer, forKey: .referer)
        try c.encode(enabled, forKey: .enabled)
        try c.encode(searchMode, forKey: .searchMode)
        try c.encode(chapterMode, forKey: .chapterMode)
        try c.encode(usePost, forKey: .usePost)
        try c.encodeIfPresent(searchApi, forKey: .searchApi)
        try c.encodeIfPresent(chapterApi, forKey: .chapterApi)
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(String.self, forKey: .id)) ?? UUID().uuidString
        name = (try? c.decode(String.self, forKey: .name)) ?? "未命名源"
        version = (try? c.decode(String.self, forKey: .version)) ?? "1.0"
        author = (try? c.decode(String.self, forKey: .author)) ?? ""
        baseURL = (try? c.decode(String.self, forKey: .baseURL)) ?? ""
        searchURL = (try? c.decode(String.self, forKey: .searchURL)) ?? ""
        searchList = (try? c.decode(String.self, forKey: .searchList)) ?? ""
        searchName = (try? c.decode(String.self, forKey: .searchName)) ?? ""
        searchResult = (try? c.decode(String.self, forKey: .searchResult)) ?? ""
        chapterRoads = (try? c.decode(String.self, forKey: .chapterRoads)) ?? ""
        chapterResult = (try? c.decode(String.self, forKey: .chapterResult)) ?? ""
        userAgent = try? c.decode(String.self, forKey: .userAgent)
        referer = try? c.decode(String.self, forKey: .referer)
        enabled = (try? c.decode(Bool.self, forKey: .enabled)) ?? true
        searchMode = Self.mode(try? c.decode(String.self, forKey: .searchMode))
        chapterMode = Self.mode(try? c.decode(String.self, forKey: .chapterMode))
        usePost = (try? c.decode(Bool.self, forKey: .usePost)) ?? false
        searchApi = (try? c.decode(LuApiSearchConfig.self, forKey: .searchApi))
            ?? (try? c.decode(LuApiSearchConfig.self, forKey: .searchApiConfig))
        chapterApi = (try? c.decode(LuApiChapterConfig.self, forKey: .chapterApi))
            ?? (try? c.decode(LuApiChapterConfig.self, forKey: .chapterApiConfig))
    }

    private static func mode(_ raw: String?) -> String {
        (raw ?? "").lowercased() == "api" ? "api" : "xpath"
    }

    init(id: String = UUID().uuidString, name: String, version: String = "1.0",
         author: String = "", baseURL: String, searchURL: String,
         searchList: String, searchName: String, searchResult: String,
         chapterRoads: String, chapterResult: String,
         userAgent: String? = nil, referer: String? = nil, enabled: Bool = true,
         searchMode: String = "xpath", chapterMode: String = "xpath",
         usePost: Bool = false,
         searchApi: LuApiSearchConfig? = nil, chapterApi: LuApiChapterConfig? = nil) {
        self.id = id; self.name = name; self.version = version; self.author = author
        self.baseURL = baseURL; self.searchURL = searchURL
        self.searchList = searchList; self.searchName = searchName
        self.searchResult = searchResult
        self.chapterRoads = chapterRoads; self.chapterResult = chapterResult
        self.userAgent = userAgent; self.referer = referer; self.enabled = enabled
        self.searchMode = searchMode; self.chapterMode = chapterMode
        self.usePost = usePost
        self.searchApi = searchApi; self.chapterApi = chapterApi
    }
}

struct PluginSearchItem: Identifiable, Hashable {
    let id = UUID()
    var name: String
    var url: URL
    var pluginID: String
}

struct PluginChapter: Identifiable, Hashable {
    let id = UUID()
    var title: String
    var url: URL
}

// MARK: - XPath + HTML 解析

/// HTML 解析器薄壳。实际实现走系统 libxml2（见 `Core/Support/LuXML.swift`）：
/// Xcode 26 的显式模块构建不再把 `XMLDocument` 随 Foundation 暴露，
/// `FoundationXML` 又是 Linux 独有模块，所以直接用 C API。
/// 容错优先：HTML 不合法时 libxml2 的 recover 模式会尽力修补。
enum LuHTML {

    static func document(from data: Data) -> LuXMLDocument? {
        LuXMLDocument(data: data)
    }
}

// MARK: - 插件引擎

enum PluginError: LocalizedError {
    case badBaseURL
    case emptyRule(String)
    case noResult
    case noStream
    case badJSON(String)

    var errorDescription: String? {
        switch self {
        case .badBaseURL: return "插件 baseURL 无效"
        case .emptyRule(let name): return "插件缺少规则：\(name)"
        case .noResult: return "该源没有搜到结果"
        case .noStream: return "没有解析到可播放地址"
        case .badJSON(let snippet):
            return snippet.isEmpty ? "接口返回的不是 JSON" : "接口返回的不是 JSON：\(snippet)"
        }
    }
}

final class PluginEngine {
    static let shared = PluginEngine()

    private func headers(for plugin: PluginManifest) -> [String: String] {
        var h: [String: String] = [:]
        if let ua = plugin.userAgent, !ua.isEmpty { h["User-Agent"] = ua }
        if let ref = plugin.referer, !ref.isEmpty { h["Referer"] = ref }
        return h
    }

    private func absolute(_ raw: String, base: URL) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasPrefix("http") { return URL(string: trimmed) }
        return URL(string: trimmed, relativeTo: base)?.absoluteURL
    }

    // MARK: 搜索

    func search(plugin: PluginManifest, keyword: String) async throws -> [PluginSearchItem] {
        if plugin.searchMode == "api", let config = plugin.searchApi {
            return try await LuApiRuleRunner.search(plugin: plugin, config: config, keyword: keyword)
        }

        guard let base = URL(string: plugin.baseURL) else { throw PluginError.badBaseURL }
        guard !plugin.searchURL.isEmpty else { throw PluginError.emptyRule("searchURL") }

        let encoded = keyword.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? keyword
        let path = plugin.searchURL.replacingOccurrences(of: "@keyword", with: encoded)
        guard let url = absolute(path, base: base) else { throw PluginError.badBaseURL }

        let data = try await HttpClient.shared.send(request(for: plugin, url: url))
        guard let doc = LuHTML.document(from: data) else { throw PluginError.noResult }

        var source = doc.nodes(plugin.searchList)
        if source.isEmpty, let root = doc.root {
            source = [root]
        }

        var items: [PluginSearchItem] = []
        for node in source {
            let name = node.string(plugin.searchName) ?? ""
            guard !name.isEmpty else { continue }
            let href = node.string(plugin.searchResult) ?? ""
            guard let itemURL = absolute(href, base: url) else { continue }
            items.append(PluginSearchItem(name: name, url: itemURL, pluginID: plugin.id))
        }
        luLogInfo("Plugin", "\(plugin.name) 搜索「\(keyword)」→ \(items.count) 条")
        return items
    }

    /// XPath 模式下的搜索请求：`usePost` 时把 URL 里的 query 挪到表单 body（对齐 Kazumi）。
    private func request(for plugin: PluginManifest, url: URL) -> HttpRequest {
        guard plugin.usePost,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return .get(url, headers: headers(for: plugin)) }

        let items = components.queryItems ?? []
        components.query = nil
        let target = components.url ?? url
        var headers = headers(for: plugin)
        headers["Content-Type"] = "application/x-www-form-urlencoded"
        let body = items.map { item in
            let name = LuTemplate.percentEncode(item.name)
            let value = LuTemplate.percentEncode(item.value ?? "")
            return "\(name)=\(value)"
        }.joined(separator: "&")
        return HttpRequest(method: "POST", url: target, headers: headers,
                           body: body.data(using: .utf8))
    }

    // MARK: 剧集

    func chapters(plugin: PluginManifest, detail url: URL) async throws -> [[PluginChapter]] {
        if plugin.chapterMode == "api", let config = plugin.chapterApi {
            return try await LuApiRuleRunner.chapters(plugin: plugin, config: config, detailURL: url)
        }

        let data = try await HttpClient.shared.send(.get(url, headers: headers(for: plugin)))
        guard let doc = LuHTML.document(from: data) else { throw PluginError.noResult }

        var roads = doc.nodes(plugin.chapterRoads)
        if roads.isEmpty, let root = doc.root {
            roads = [root]
        }

        var result: [[PluginChapter]] = []
        for road in roads {
            let chapterNodes = road.nodes(plugin.chapterResult)
            var chapters: [PluginChapter] = []
            for (index, node) in chapterNodes.enumerated() {
                let title = node.stringValue ?? "第 \(index + 1) 话"
                let href: String
                if let value = node.attribute("href") {
                    href = value
                } else {
                    href = node.stringValue ?? ""
                }
                guard let chapterURL = absolute(href, base: url) else { continue }
                chapters.append(PluginChapter(title: title.isEmpty ? "第 \(index + 1) 话" : title,
                                              url: chapterURL))
            }
            if !chapters.isEmpty { result.append(chapters) }
        }
        return result
    }

    // MARK: 播放地址

    func streams(plugin: PluginManifest, chapter url: URL) async throws -> [PlayStream] {
        let data = try await HttpClient.shared.send(
            .get(url, headers: headers(for: plugin))
        )
        guard let text = String(data: data, encoding: .utf8) else { throw PluginError.noStream }

        // 1. 直接出现的 m3u8 / mp4
        var candidates = Self.extractMediaURLs(from: text)

        // 2. iframe 再进一层（常见于第三方播放页）
        if candidates.isEmpty {
            let iframes = Self.extractIframes(from: text, base: url)
            for iframe in iframes.prefix(2) {
                if let inner = try? await HttpClient.shared.send(
                    .get(iframe, headers: headers(for: plugin))
                ), let innerText = String(data: inner, encoding: .utf8) {
                    candidates.append(contentsOf: Self.extractMediaURLs(from: innerText))
                }
                if !candidates.isEmpty { break }
            }
        }

        var seen = Set<String>()
        return candidates.compactMap { raw -> PlayStream? in
            guard let streamURL = self.absolute(raw, base: url) else { return nil }
            guard seen.insert(streamURL.absoluteString).inserted else { return nil }
            var headers = self.headers(for: plugin)
            headers["Referer"] = url.absoluteString
            let quality = streamURL.absoluteString.lowercased().contains("1080") ? "1080p"
                : streamURL.absoluteString.lowercased().contains("720") ? "720p"
                : "自动"
            return PlayStream(url: streamURL, quality: quality, headers: headers)
        }
    }

    static func extractMediaURLs(from text: String) -> [String] {
        let patterns = [
            #"https?://[^\s"'\\<>]+?\.m3u8[^\s"'\\<>]*"#,
            #"https?://[^\s"'\\<>]+?\.mp4[^\s"'\\<>]*"#
        ]
        var found: [String] = []
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(text.startIndex..., in: text)
            regex.matches(in: text, range: range).forEach { match in
                if let r = Range(match.range, in: text) {
                    found.append(String(text[r]).replacingOccurrences(of: "\\/", with: "/"))
                }
            }
        }
        return found
    }

    static func extractIframes(from text: String, base: URL) -> [URL] {
        guard let regex = try? NSRegularExpression(pattern: #"<iframe[^>]+src=["']([^"']+)["']"#,
                                                   options: .caseInsensitive) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard match.numberOfRanges > 1, let r = Range(match.range(at: 1), in: text) else { return nil }
            let raw = String(text[r])
            return raw.hasPrefix("http") ? URL(string: raw) : URL(string: raw, relativeTo: base)?.absoluteURL
        }
    }
}

// MARK: - 插件仓库

final class PluginStore: ObservableObject {
    static let shared = PluginStore()
    private let store = JSONStore<[PluginManifest]>(name: "plugins", defaultValue: [])
    @Published private(set) var plugins: [PluginManifest] = []
    @Published var activePluginID: String?

    private init() {
        plugins = store.value
        activePluginID = plugins.first(where: { $0.enabled })?.id
    }

    var enabledPlugins: [PluginManifest] { plugins.filter(\.enabled) }

    func importJSON(_ text: String) throws {
        guard let data = text.data(using: .utf8) else { throw PluginError.noResult }
        let manifest = try JSONDecoder().decode(PluginManifest.self, from: data)
        plugins.removeAll { $0.id == manifest.id || $0.name == manifest.name }
        plugins.append(manifest)
        persist()
    }

    /// 编辑器的保存入口：同 id 覆盖，新 id 追加。
    func save(_ manifest: PluginManifest) {
        if let index = plugins.firstIndex(where: { $0.id == manifest.id }) {
            plugins[index] = manifest
        } else {
            plugins.append(manifest)
        }
        if activePluginID == nil { activePluginID = manifest.id }
        persist()
        luLogInfo("Plugin", "保存插件 \(manifest.name)")
    }

    func remove(id: String) {
        plugins.removeAll { $0.id == id }
        if activePluginID == id { activePluginID = plugins.first?.id }
        persist()
    }

    func toggle(id: String) {
        guard let index = plugins.firstIndex(where: { $0.id == id }) else { return }
        plugins[index].enabled.toggle()
        persist()
    }

    private func persist() { store.update { $0 = self.plugins } }
}
