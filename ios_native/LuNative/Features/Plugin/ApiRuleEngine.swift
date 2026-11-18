import Foundation
import CoreFoundation

// MARK: - 通用 JSON 值
//
// 插件请求体在 Kazumi 里是 `dynamic`（字符串 / 对象 / 数组都可能），
// Swift 的 Codable 需要一个确定类型，这里用递归枚举把它完整保留下来。

enum LuJSONValue: Codable, Hashable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([LuJSONValue])
    case object([String: LuJSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null; return }
        if let value = try? container.decode(Bool.self) { self = .bool(value); return }
        if let value = try? container.decode(Double.self) { self = .number(value); return }
        if let value = try? container.decode(String.self) { self = .string(value); return }
        if let value = try? container.decode([LuJSONValue].self) { self = .array(value); return }
        if let value = try? container.decode([String: LuJSONValue].self) { self = .object(value); return }
        self = .null
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }

    /// 模板替换时用的字符串形态。
    var text: String {
        switch self {
        case .null: return ""
        case .bool(let value): return value ? "true" : "false"
        case .number(let value):
            if value == value.rounded(), abs(value) < 1e15 { return String(Int(value)) }
            return String(value)
        case .string(let value): return value
        case .array, .object:
            guard let data = try? JSONEncoder().encode(self),
                  let text = String(data: data, encoding: .utf8) else { return "" }
            return text
        }
    }
}

// MARK: - 受限 JSONPath

enum LuJSONPathError: LocalizedError {
    case invalid(String)

    var errorDescription: String? {
        switch self {
        case .invalid(let detail): return "JSONPath 无效：\(detail)"
        }
    }
}

/// Kazumi 的 API 规则只允许 JSONPath 的一个安全子集：
/// `$.a.b`、`$.list[*]`、`$.list[0]`、`$['a-b']`。递归下降、过滤、函数都不支持。
/// 这里逐字符解析成段序列，非法表达式直接抛错（供编辑器校验用）。
enum LuJSONPath {

    enum Segment: Equatable {
        case key(String)
        case index(Int)
        case wildcard
    }

    static func segments(_ expression: String) throws -> [Segment] {
        let trimmed = expression.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("$") else {
            throw LuJSONPathError.invalid("必须以 $ 开头 → \(expression)")
        }
        let chars = Array(trimmed)
        var index = 1
        var result: [Segment] = []

        while index < chars.count {
            let char = chars[index]
            if char == "." {
                index += 1
                let start = index
                while index < chars.count, isNameCharacter(chars[index]) { index += 1 }
                guard index > start else {
                    throw LuJSONPathError.invalid("字段名为空 → \(expression)")
                }
                result.append(.key(String(chars[start..<index])))
                continue
            }
            if char == "[" {
                let end = try bracketEnd(chars, from: index, expression: expression)
                let content = String(chars[(index + 1)..<end])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if content == "*" {
                    result.append(.wildcard)
                } else if !content.isEmpty, let value = Int(content) {
                    result.append(.index(value))
                } else if let key = unquote(content) {
                    result.append(.key(key))
                } else {
                    throw LuJSONPathError.invalid("不支持的片段 → [\(content)]")
                }
                index = end + 1
                continue
            }
            throw LuJSONPathError.invalid("不支持的字符「\(char)」→ \(expression)")
        }
        return result
    }

    static func read(_ document: Any, _ expression: String) throws -> [Any] {
        let path = try segments(expression)
        var current: [Any] = [document]
        for segment in path {
            var next: [Any] = []
            for value in current {
                switch segment {
                case .key(let key):
                    if let dict = value as? [String: Any], let found = dict[key] {
                        next.append(found)
                    }
                case .index(let position):
                    if let array = value as? [Any], position >= 0, position < array.count {
                        next.append(array[position])
                    }
                case .wildcard:
                    if let array = value as? [Any] {
                        next.append(contentsOf: array)
                    } else if let dict = value as? [String: Any] {
                        next.append(contentsOf: dict.values)
                    }
                }
            }
            current = next
            if current.isEmpty { break }
        }
        return current
    }

    static func first(_ document: Any, _ expression: String) throws -> Any? {
        try read(document, expression).first
    }

    // MARK: 词法辅助

    private static func isNameCharacter(_ char: Character) -> Bool {
        char.isLetter || char.isNumber || char == "_" || char == "-" || char == "$"
    }

    private static func bracketEnd(_ chars: [Character], from start: Int,
                                   expression: String) throws -> Int {
        var quote: Character?
        var escaped = false
        var index = start + 1
        while index < chars.count {
            let char = chars[index]
            if escaped { escaped = false; index += 1; continue }
            if char == "\\" { escaped = true; index += 1; continue }
            if let current = quote {
                if char == current { quote = nil }
                index += 1
                continue
            }
            if char == "'" || char == "\"" { quote = char; index += 1; continue }
            if char == "]" { return index }
            index += 1
        }
        throw LuJSONPathError.invalid("缺少 ] → \(expression)")
    }

    private static func unquote(_ content: String) -> String? {
        guard content.count >= 2,
              let first = content.first, let last = content.last,
              first == last, first == "'" || first == "\""
        else { return nil }
        return String(content.dropFirst().dropLast())
    }
}

// MARK: - 文本取值

enum LuJSONText {
    /// 把 JSONSerialization 产出的任意值转成规则里能用的字符串。
    static func string(_ value: Any?) -> String {
        guard let value, !(value is NSNull) else { return "" }
        if let text = value as? String {
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let number = value as? NSNumber {
            if CFGetTypeID(number as CFTypeRef) == CFBooleanGetTypeID() {
                return number.boolValue ? "true" : "false"
            }
            let raw = number.doubleValue
            if raw == raw.rounded(), abs(raw) < 1e15 { return String(number.intValue) }
            return String(raw)
        }
        return "\(value)".trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 单值表达式求值，失败返回 nil（不抛错，便于逐条容错）。
    static func value(_ node: Any, _ expression: String) -> String? {
        guard !expression.isEmpty else { return nil }
        guard let result = (try? LuJSONPath.first(node, expression)) ?? nil else { return nil }
        return string(result)
    }
}

// MARK: - 模板变量
//
// 规则里的 `@keyword` / `@source` / `@episodeUrl` 就是这套替换，
// 前面不能紧挨字母数字下划线（`/GV@source` 这种要能正常替换）。

enum LuTemplate {
    private static let pattern = "(?<![A-Za-z0-9_])@([A-Za-z_][A-Za-z0-9_]*)"

    static func render(_ template: String, variables: [String: String],
                       encode: Bool = false) -> String {
        guard template.contains("@"),
              let regex = try? NSRegularExpression(pattern: pattern) else { return template }

        let source = template as NSString
        let matches = regex.matches(in: template,
                                    range: NSRange(location: 0, length: source.length))
        var result = template
        // 倒序替换，避免前面的替换把后面匹配的 range 顶偏
        for match in matches.reversed() {
            guard match.numberOfRanges > 1 else { continue }
            let name = source.substring(with: match.range(at: 1))
            guard let raw = variables[name] else { continue }
            let replacement = encode ? percentEncode(raw) : raw
            if let range = Range(match.range, in: result) {
                result.replaceSubrange(range, with: replacement)
            }
        }
        return result
    }

    /// 与 Dart `Uri.encodeComponent` 对齐（保留 -_.~ 不转义）。
    static func percentEncode(_ text: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-_.~")
        return text.addingPercentEncoding(withAllowedCharacters: allowed) ?? text
    }

    /// `@name` 独占一个字符串时保留原始类型语义（这里统一成字符串即可）。
    static func exactVariable(_ value: String) -> String? {
        guard value.hasPrefix("@"), value.count > 1 else { return nil }
        let name = String(value.dropFirst())
        guard name.first?.isLetter == true || name.first == "_" else { return nil }
        for char in name.dropFirst() {
            if !(char.isLetter || char.isNumber || char == "_") { return nil }
        }
        return name
    }
}

// MARK: - API 规则配置

struct LuApiRequest: Codable, Hashable {
    var method: String = "GET"
    var url: String = ""
    var headers: [String: String] = [:]
    var query: [String: String] = [:]
    var bodyType: String = "none"       // none / json / form
    var body: LuJSONValue?

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        method = ((try? container.decode(String.self, forKey: .method)) ?? "GET").uppercased()
        url = (try? container.decode(String.self, forKey: .url)) ?? ""
        headers = Self.textMap(try? container.decode([String: LuJSONValue].self, forKey: .headers))
        query = Self.textMap(try? container.decode([String: LuJSONValue].self, forKey: .query))
        bodyType = ((try? container.decode(String.self, forKey: .bodyType)) ?? "none").lowercased()
        body = try? container.decode(LuJSONValue.self, forKey: .body)
    }

    private static func textMap(_ raw: [String: LuJSONValue]?) -> [String: String] {
        guard let raw else { return [:] }
        var result: [String: String] = [:]
        for pair in raw { result[pair.key] = pair.value.text }
        return result
    }
}

struct LuApiSearchConfig: Codable, Hashable {
    var request = LuApiRequest()
    var listPath = "$.data[*]"
    var namePath = "$.name"
    var sourcePath = "$.url"
    var sourceTemplate = ""

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        request = (try? container.decode(LuApiRequest.self, forKey: .request)) ?? LuApiRequest()
        listPath = (try? container.decode(String.self, forKey: .listPath)) ?? "$.data[*]"
        namePath = (try? container.decode(String.self, forKey: .namePath)) ?? "$.name"
        sourcePath = (try? container.decode(String.self, forKey: .sourcePath)) ?? "$.url"
        sourceTemplate = (try? container.decode(String.self, forKey: .sourceTemplate)) ?? ""
    }

    func validate() throws {
        try LuJSONPath.segments(listPath)
        try LuJSONPath.segments(namePath)
        try LuJSONPath.segments(sourcePath)
        if !sourceTemplate.isEmpty, !sourceTemplate.contains("@source") {
            throw LuJSONPathError.invalid("详情页模板必须引用 @source")
        }
    }
}

struct LuApiEpisodePage: Codable, Hashable {
    var url = ""
    var query: [String: String] = [:]

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        url = (try? container.decode(String.self, forKey: .url)) ?? ""
        let raw = try? container.decode([String: LuJSONValue].self, forKey: .query)
        if let raw {
            var map: [String: String] = [:]
            for pair in raw { map[pair.key] = pair.value.text }
            query = map
        }
    }
}

struct LuApiChapterConfig: Codable, Hashable {
    var request = LuApiRequest()
    var format = "nested"               // nested / delimited
    var roadsPath = "$.data.roads[*]"
    var roadNamePath = "$.name"
    var episodesPath = "$.episodes[*]"
    var episodeNamePath = "$.name"
    var episodeUrlPath = "$.url"
    var roadNamesPath = ""
    var roadEpisodesPath = ""
    var roadSeparator = "$$$"
    var episodeSeparator = "#"
    var fieldSeparator = "$"
    var variables: [String: String] = [:]
    var episodePage: LuApiEpisodePage?

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        request = (try? container.decode(LuApiRequest.self, forKey: .request)) ?? LuApiRequest()
        format = ((try? container.decode(String.self, forKey: .format)) ?? "nested").lowercased()
        roadsPath = (try? container.decode(String.self, forKey: .roadsPath)) ?? "$.data.roads[*]"
        roadNamePath = (try? container.decode(String.self, forKey: .roadNamePath)) ?? "$.name"
        episodesPath = (try? container.decode(String.self, forKey: .episodesPath)) ?? "$.episodes[*]"
        episodeNamePath = (try? container.decode(String.self, forKey: .episodeNamePath)) ?? "$.name"
        episodeUrlPath = (try? container.decode(String.self, forKey: .episodeUrlPath)) ?? "$.url"
        roadNamesPath = (try? container.decode(String.self, forKey: .roadNamesPath)) ?? ""
        roadEpisodesPath = (try? container.decode(String.self, forKey: .roadEpisodesPath)) ?? ""
        roadSeparator = (try? container.decode(String.self, forKey: .roadSeparator)) ?? "$$$"
        episodeSeparator = (try? container.decode(String.self, forKey: .episodeSeparator)) ?? "#"
        fieldSeparator = (try? container.decode(String.self, forKey: .fieldSeparator)) ?? "$"
        if let raw = try? container.decode([String: LuJSONValue].self, forKey: .variables) {
            var map: [String: String] = [:]
            for pair in raw { map[pair.key] = pair.value.text }
            variables = map
        }
        episodePage = try? container.decode(LuApiEpisodePage.self, forKey: .episodePage)
    }

    func validate() throws {
        if format == "delimited" {
            guard !roadEpisodesPath.isEmpty else {
                throw LuJSONPathError.invalid("分隔符格式必须填写剧集字段")
            }
            try LuJSONPath.segments(roadEpisodesPath)
            if !roadNamesPath.isEmpty { try LuJSONPath.segments(roadNamesPath) }
        } else {
            if !roadsPath.isEmpty { try LuJSONPath.segments(roadsPath) }
            try LuJSONPath.segments(episodesPath)
            if !episodeUrlPath.isEmpty { try LuJSONPath.segments(episodeUrlPath) }
        }
        for path in variables.values { try LuJSONPath.segments(path) }
        if let episodePage, !episodePage.url.isEmpty, !episodePage.url.contains("@") {
            throw LuJSONPathError.invalid("播放页模板必须引用变量")
        }
    }
}

// MARK: - API 规则执行

/// Kazumi 的「API 模式」规则：直接打接口拿 JSON，用 JSONPath 取值。
/// 与 XPath 模式互斥，由 `searchMode` / `chapterMode` 决定走哪条。
enum LuApiRuleRunner {

    static func search(plugin: PluginManifest, config: LuApiSearchConfig,
                       keyword: String) async throws -> [PluginSearchItem] {
        try config.validate()
        let variables = ["keyword": keyword]
        let (data, _) = try await perform(plugin: plugin, request: config.request,
                                          variables: variables)
        let document = try decode(data)
        let nodes = try LuJSONPath.read(document, config.listPath)

        var items: [PluginSearchItem] = []
        for node in nodes {
            guard let name = LuJSONText.value(node, config.namePath), !name.isEmpty else { continue }
            guard let source = LuJSONText.value(node, config.sourcePath), !source.isEmpty else { continue }
            let resolved = config.sourceTemplate.isEmpty
                ? source
                : config.sourceTemplate.replacingOccurrences(
                    of: "@source", with: LuTemplate.percentEncode(source))
            guard let url = resolve(resolved, base: URL(string: plugin.baseURL)) else { continue }
            items.append(PluginSearchItem(name: name, url: url, pluginID: plugin.id))
        }
        luLogInfo("Plugin", "\(plugin.name) API 搜索「\(keyword)」→ \(items.count) 条")
        return items
    }

    static func chapters(plugin: PluginManifest, config: LuApiChapterConfig,
                         detailURL: URL) async throws -> [[PluginChapter]] {
        try config.validate()
        var variables: [String: String] = ["source": detailURL.absoluteString]

        let (data, finalURL) = try await perform(plugin: plugin, request: config.request,
                                                 variables: variables)
        let document = try decode(data)

        for pair in config.variables {
            guard let value = (try? LuJSONPath.first(document, pair.value)) ?? nil else {
                throw PluginError.emptyRule("变量 \(pair.key) 未命中 \(pair.value)")
            }
            variables[pair.key] = LuJSONText.string(value)
        }

        let roads = config.format == "delimited"
            ? try parseDelimited(config, document: document, variables: variables, base: finalURL)
            : try parseNested(config, document: document, variables: variables, base: finalURL)

        luLogInfo("Plugin", "\(plugin.name) API 章节 → \(roads.count) 条线路")
        return roads
    }

    // MARK: 嵌套格式

    private static func parseNested(_ config: LuApiChapterConfig, document: Any,
                                    variables: [String: String],
                                    base: URL) throws -> [[PluginChapter]] {
        let hasRoads = !config.roadsPath.trimmingCharacters(in: .whitespaces).isEmpty
        let roadNodes = hasRoads
            ? try LuJSONPath.read(document, config.roadsPath)
            : [document]

        var roads: [[PluginChapter]] = []
        for (roadIndex, roadNode) in roadNodes.enumerated() {
            let roadName = hasRoads && !config.roadNamePath.isEmpty
                ? (LuJSONText.value(roadNode, config.roadNamePath) ?? "")
                : ""
            let episodes = try LuJSONPath.read(roadNode, config.episodesPath)
            var list: [PluginChapter] = []
            for (index, node) in episodes.enumerated() {
                let name = LuJSONText.value(node, config.episodeNamePath) ?? ""
                let raw = config.episodeUrlPath.isEmpty
                    ? ""
                    : (LuJSONText.value(node, config.episodeUrlPath) ?? "")
                guard let url = episodeURL(config, variables: variables, rawURL: raw,
                                           roadIndex: roadIndex, episodeIndex: index,
                                           base: base) else { continue }
                let title = name.isEmpty ? "第 \(index + 1) 集" : name
                list.append(PluginChapter(title: title, url: url))
            }
            if !list.isEmpty {
                if !roadName.isEmpty {
                    luLogDebug("Plugin", "线路 \(roadIndex)：\(roadName)")
                }
                roads.append(list)
            }
        }
        return roads
    }

    // MARK: 分隔符格式

    private static func parseDelimited(_ config: LuApiChapterConfig, document: Any,
                                       variables: [String: String],
                                       base: URL) throws -> [[PluginChapter]] {
        let namesText = config.roadNamesPath.isEmpty
            ? ""
            : (LuJSONText.value(document, config.roadNamesPath) ?? "")
        let episodesText = LuJSONText.value(document, config.roadEpisodesPath) ?? ""
        guard !episodesText.isEmpty else { return [] }

        let roadNames = namesText.components(separatedBy: config.roadSeparator)
        let roadGroups = episodesText.components(separatedBy: config.roadSeparator)

        var roads: [[PluginChapter]] = []
        for (roadIndex, group) in roadGroups.enumerated() {
            var list: [PluginChapter] = []
            let entries = group.components(separatedBy: config.episodeSeparator)
            for (index, entry) in entries.enumerated() {
                let trimmed = entry.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                guard let fieldRange = trimmed.range(of: config.fieldSeparator) else { continue }
                let name = String(trimmed[trimmed.startIndex..<fieldRange.lowerBound])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let raw = String(trimmed[fieldRange.upperBound...])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard let url = episodeURL(config, variables: variables, rawURL: raw,
                                           roadIndex: roadIndex, episodeIndex: index,
                                           base: base) else { continue }
                list.append(PluginChapter(title: name.isEmpty ? "第 \(index + 1) 集" : name,
                                          url: url))
            }
            if !list.isEmpty { roads.append(list) }
        }
        _ = roadNames
        return roads
    }

    // MARK: 剧集地址

    private static func episodeURL(_ config: LuApiChapterConfig,
                                   variables: [String: String],
                                   rawURL: String,
                                   roadIndex: Int,
                                   episodeIndex: Int,
                                   base: URL) -> URL? {
        guard let page = config.episodePage, !page.url.isEmpty else {
            return resolve(rawURL, base: base)
        }
        var renderVars = variables
        renderVars["source"] = variables["source"] ?? ""
        renderVars["episodeUrl"] = rawURL
        renderVars["roadIndex"] = String(roadIndex)
        renderVars["episodeIndex"] = String(episodeIndex)
        renderVars["episodeNumber"] = String(episodeIndex + 1)

        let path = LuTemplate.render(page.url, variables: renderVars, encode: true)
        guard var components = URLComponents(string: path) else { return nil }
        if !page.query.isEmpty {
            var items = components.queryItems ?? []
            for pair in page.query.sorted(by: { $0.key < $1.key }) {
                items.append(URLQueryItem(name: pair.key,
                                          value: LuTemplate.render(pair.value, variables: renderVars)))
            }
            components.queryItems = items
        }
        return components.url
    }

    // MARK: 请求

    private static func perform(plugin: PluginManifest, request: LuApiRequest,
                                variables: [String: String]) async throws -> (Data, URL) {
        let method = request.method.uppercased()
        guard method == "GET" || method == "POST" else {
            throw PluginError.emptyRule("method 只能是 GET/POST")
        }
        guard !request.url.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw PluginError.emptyRule("API 地址")
        }

        let rendered = LuTemplate.render(request.url.trimmingCharacters(in: .whitespaces),
                                         variables: variables, encode: true)
        guard let target = resolve(rendered, base: URL(string: plugin.baseURL)) else {
            throw PluginError.badBaseURL
        }

        var components = URLComponents(url: target, resolvingAgainstBaseURL: false)
        if !request.query.isEmpty {
            var items = components?.queryItems ?? []
            for pair in request.query.sorted(by: { $0.key < $1.key }) {
                items.append(URLQueryItem(name: pair.key,
                                          value: LuTemplate.render(pair.value, variables: variables)))
            }
            components?.queryItems = items
        }
        let finalURL = components?.url ?? target

        var headers = pluginHeaders(plugin)
        for pair in request.headers {
            headers[pair.key] = LuTemplate.render(pair.value, variables: variables)
        }

        var body: Data?
        if method == "POST", request.bodyType != "none", let raw = request.body {
            switch request.bodyType {
            case "json":
                body = LuTemplate.render(raw.text, variables: variables).data(using: .utf8)
                headers["Content-Type"] = "application/json"
            case "form":
                body = formBody(raw, variables: variables).data(using: .utf8)
                headers["Content-Type"] = "application/x-www-form-urlencoded"
            default:
                break
            }
        }

        let http = HttpRequest(method: method, url: finalURL, headers: headers, body: body)
        let data = try await HttpClient.shared.send(http)
        return (data, finalURL)
    }

    private static func pluginHeaders(_ plugin: PluginManifest) -> [String: String] {
        var headers: [String: String] = [:]
        if let ua = plugin.userAgent, !ua.isEmpty { headers["User-Agent"] = ua }
        if let referer = plugin.referer, !referer.isEmpty { headers["Referer"] = referer }
        return headers
    }

    private static func formBody(_ body: LuJSONValue,
                                 variables: [String: String]) -> String {
        switch body {
        case .object(let dict):
            return dict.sorted { $0.key < $1.key }.map { pair in
                let value = LuTemplate.render(pair.value.text, variables: variables)
                return "\(LuTemplate.percentEncode(pair.key))=\(LuTemplate.percentEncode(value))"
            }.joined(separator: "&")
        case .string(let text):
            return LuTemplate.render(text, variables: variables)
        default:
            return ""
        }
    }

    private static func decode(_ data: Data) throws -> Any {
        do {
            return try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        } catch {
            let snippet = String(data: data.prefix(160), encoding: .utf8) ?? ""
            throw PluginError.badJSON(snippet)
        }
    }

    static func resolve(_ raw: String, base: URL?) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasPrefix("http") { return URL(string: trimmed) }
        if trimmed.hasPrefix("//"), let base, let scheme = base.scheme {
            return URL(string: "\(scheme):\(trimmed)")
        }
        guard let base else { return URL(string: trimmed) }
        return URL(string: trimmed, relativeTo: base)?.absoluteURL
    }
}
