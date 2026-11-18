import Foundation

/// 深链解析。
///
/// 支持：
/// - `kazumi://subject/123`
/// - `kazumi://detail?id=123`
/// - `https://bgm.tv/subject/123`、`https://bangumi.tv/subject/123`
/// - `https://bgm.tv/anime/subject/123`（老路径）
///
/// 只处理「打开某部番」，搜索类链接忽略。
enum LuDeepLink {

    static func subjectID(from url: URL) -> Int? {
        let host = (url.host ?? "").lowercased()
        let scheme = (url.scheme ?? "").lowercased()
        let pathParts = url.path.split(separator: "/").map(String.init)

        // 自定义 scheme
        if scheme == "kazumi" || scheme == "lu" {
            if host == "subject" || host == "detail" || host == "anime" {
                if let last = pathParts.last, let id = Int(last) { return id }
                if let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                    .queryItems?.first(where: { $0.name == "id" })?.value,
                   let id = Int(query) {
                    return id
                }
            }
            // kazumi:///subject/123 这种 host 为空的写法
            if host.isEmpty, let index = pathParts.firstIndex(where: { $0 == "subject" }),
               index + 1 < pathParts.count, let id = Int(pathParts[index + 1]) {
                return id
            }
            return nil
        }

        // Bangumi 网页
        guard host.hasSuffix("bgm.tv") || host.hasSuffix("bangumi.tv") else { return nil }
        if let index = pathParts.firstIndex(where: { $0 == "subject" }),
           index + 1 < pathParts.count, let id = Int(pathParts[index + 1]) {
            return id
        }
        return nil
    }

    @discardableResult
    static func handle(_ url: URL) -> Bool {
        guard let id = subjectID(from: url) else {
            luLogWarn("DeepLink", "无法识别的链接：\(url.absoluteString)")
            return false
        }
        luLogInfo("DeepLink", "打开条目 \(id)")
        AppState.shared.pendingSubjectID = id
        return true
    }
}
