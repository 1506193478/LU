import Foundation

// MARK: - 条目

struct WebDAVEntry: Identifiable, Hashable {
    let path: String
    let name: String
    let isDirectory: Bool
    let size: Int64
    let contentType: String
    let modified: String?

    var id: String { path }

    var isVideo: Bool {
        let ext = (name as NSString).pathExtension.lowercased()
        return ["mp4", "mkv", "mov", "m4v", "avi", "webm", "ts", "flv", "m3u8"].contains(ext)
    }

    var isSubtitle: Bool {
        let ext = (name as NSString).pathExtension.lowercased()
        return ["srt", "ass", "ssa", "vtt"].contains(ext)
    }

    var sizeText: String {
        guard size > 0 else { return "" }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }
}

// MARK: - 客户端

enum WebDAVError: LocalizedError {
    case badBaseURL
    case unauthorized
    case badResponse(Int)

    var errorDescription: String? {
        switch self {
        case .badBaseURL: return "WebDAV 地址无效"
        case .unauthorized: return "认证失败，请检查账号密码"
        case .badResponse(let code): return "服务器返回 \(code)"
        }
    }
}

/// WebDAV 浏览与播放。对照 Flutter 侧 `lib/services/sync/webdav.dart`。
///
/// 只用最基础的一组方法：`PROPFIND`（Depth: 1）列目录，播放时把
/// Basic 认证头塞进 `AVURLAssetHTTPHeaderFieldsKey` 交给 AVPlayer。
final class WebDAVClient {

    let baseURL: URL
    private let username: String
    private let password: String

    init(baseURL: URL, username: String, password: String) {
        self.baseURL = baseURL
        self.username = username
        self.password = password
    }

    static func fromSettings(_ settings: AppSettings) -> WebDAVClient? {
        guard let url = URL(string: settings.webdavURL.trimmingCharacters(in: .whitespaces)),
              url.scheme?.hasPrefix("http") == true else { return nil }
        return WebDAVClient(baseURL: url, username: settings.webdavUser,
                            password: settings.webdavPassword)
    }

    private var authHeader: String? {
        guard !username.isEmpty || !password.isEmpty else { return nil }
        let raw = "\(username):\(password)"
        guard let data = raw.data(using: .utf8) else { return nil }
        return "Basic " + data.base64EncodedString()
    }

    func url(for path: String) -> URL? {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            return nil
        }
        let encoded = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
        components.percentEncodedPath = encoded.hasPrefix("/") ? encoded : "/" + encoded
        return components.url
    }

    // MARK: 列目录

    func list(_ path: String) async throws -> [WebDAVEntry] {
        guard let url = url(for: path) else { throw WebDAVError.badBaseURL }
        var request = HttpRequest(method: "PROPFIND", url: url)
        request.body = Self.propfindBody.data(using: .utf8)
        request.timeout = 25
        request.headers["Depth"] = "1"
        request.headers["Content-Type"] = "application/xml; charset=utf-8"
        if let authHeader { request.headers["Authorization"] = authHeader }

        let data: Data
        do {
            data = try await HttpClient.shared.send(request)
        } catch NetworkError.badStatus(let code, _) {
            if code == 401 { throw WebDAVError.unauthorized }
            throw WebDAVError.badResponse(code)
        }
        return parse(data, currentPath: path)
    }

    static let propfindBody = """
    <?xml version="1.0" encoding="utf-8"?>
    <d:propfind xmlns:d="DAV:">
      <d:prop>
        <d:displayname/>
        <d:getcontentlength/>
        <d:getcontenttype/>
        <d:getlastmodified/>
        <d:resourcetype/>
      </d:prop>
    </d:propfind>
    """

    private func parse(_ data: Data, currentPath: String) -> [WebDAVEntry] {
        guard let document = LuXMLDocument(data: data, isHTML: false) else { return [] }
        let responses = document.nodes("//*[local-name()='response']")
        var entries: [WebDAVEntry] = []
        let normalizedCurrent = currentPath.hasSuffix("/") ? currentPath : currentPath + "/"

        for response in responses {
            func child(_ name: String) -> LuXMLDocument.Node? {
                response.nodes("./*[local-name()='\(name)']").first
            }
            let hrefRaw = child("href")?.stringValue ?? ""
            guard !hrefRaw.isEmpty else { continue }
            let decoded = hrefRaw.removingPercentEncoding ?? hrefRaw

            // 目录自身也会被返回，跳过
            if decoded == currentPath || decoded == normalizedCurrent { continue }

            let isDirectory = response.nodes(".//*[local-name()='collection']").isEmpty == false
            var name = child("displayname")?.stringValue ?? ""
            if name.isEmpty {
                name = (decoded as NSString).lastPathComponent
            }
            let size = Int64(child("getcontentlength")?.stringValue ?? "") ?? 0
            let type = child("getcontenttype")?.stringValue ?? ""
            let modified = child("getlastmodified")?.stringValue

            entries.append(WebDAVEntry(path: decoded,
                                       name: name.isEmpty ? decoded : name,
                                       isDirectory: isDirectory,
                                       size: size,
                                       contentType: type,
                                       modified: modified))
        }
        entries.sort { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
        return entries
    }

    // MARK: 播放

    func stream(for entry: WebDAVEntry, quality: String = "直连") -> PlayStream? {
        guard let url = url(for: entry.path) else { return nil }
        var headers: [String: String] = [:]
        if let authHeader { headers["Authorization"] = authHeader }
        return PlayStream(url: url, quality: quality, headers: headers)
    }

    func subtitleTrack(for entry: WebDAVEntry) async -> SubtitleTrack? {
        guard let url = url(for: entry.path) else { return nil }
        var request = URLRequest(url: url)
        if let authHeader { request.setValue(authHeader, forHTTPHeaderField: "Authorization") }
        guard let (data, _) = try? await URLSession.shared.data(for: request) else { return nil }
        return SubtitleParser.parse(data: data, url: url)
    }

    /// 同目录下与视频同名的字幕。
    func sidecarSubtitle(for entry: WebDAVEntry) async -> SubtitleTrack? {
        let directory = (entry.path as NSString).deletingLastPathComponent
        let base = ((entry.name as NSString).deletingPathExtension).lowercased()
        guard let siblings = try? await list(directory) else { return nil }
        guard let match = siblings.first(where: {
            $0.isSubtitle && (($0.name as NSString).deletingPathExtension).lowercased().hasPrefix(base)
        }) else { return nil }
        return await subtitleTrack(for: match)
    }
}
