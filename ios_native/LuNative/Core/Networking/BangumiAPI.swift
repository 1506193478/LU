import Foundation

/// Bangumi 官方 API 客户端。对照 Flutter 侧 `lib/request/apis/bangumi_api.dart`，
/// 第一阶段只覆盖看番闭环所需：每日放送、搜索、条目、剧集、角色。
final class BangumiAPI {
    static let shared = BangumiAPI()

    private let base = URL(string: "https://api.bgm.tv")!
    private let client = HttpClient.shared
    /// 可选的个人 access token（设置页填写），无 token 也能用公开接口。
    var accessToken: String?

    private var authHeaders: [String: String] {
        guard let token = accessToken, !token.isEmpty else { return [:] }
        return ["Authorization": "Bearer \(token)"]
    }

    // MARK: - 每日放送

    func calendar() async throws -> [[AnimeSubject]] {
        struct Weekday: Decodable { let id: Int? }
        struct Entry: Decodable { let subject: AnimeSubject }
        let url = base.appendingPathComponent("calendar")
        let data = try await client.send(.get(url, headers: authHeaders))

        // 顶层是 { "1": [...], "2": [...] ... }，按 1...7 固定取，缺的补空数组
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NetworkError.decoding("calendar 结构异常")
        }
        var result: [[AnimeSubject]] = []
        for day in 1...7 {
            let raw = root["\(day)"] as? [[String: Any]] ?? []
            var list: [AnimeSubject] = []
            for entry in raw {
                guard let subjectDict = entry["subject"],
                      let subjectData = try? JSONSerialization.data(withJSONObject: subjectDict),
                      let subject = try? JSONDecoder().decode(AnimeSubject.self, from: subjectData) else {
                    continue
                }
                list.append(subject)
            }
            result.append(list)
        }
        _ = Weekday.self; _ = Entry.self
        return result
    }

    // MARK: - 搜索

    func search(keyword: String, limit: Int = 24, offset: Int = 0) async throws -> [AnimeSubject] {
        struct Filter: Encodable { let type: [Int] }
        struct Body: Encodable { let keyword: String; let filter: Filter }
        struct Response: Decodable { let data: [AnimeSubject]?; let total: Int? }

        let url = base.appendingPathComponent("v0/search/subjects")
        var request = HttpRequest.post(url, json: Body(keyword: keyword, filter: Filter(type: [2])),
                                       headers: authHeaders)
        request.headers["User-Agent"] = LuUserAgent.value
        let response = try await client.json(request, as: Response.self)
        return Array((response.data ?? []).prefix(limit))
            .enumerated().filter { $0.offset >= offset }.map { $0.element }
    }

    // MARK: - 条目 / 剧集 / 角色

    func subject(id: Int) async throws -> AnimeSubject {
        let url = base.appendingPathComponent("v0/subjects/\(id)")
        return try await client.json(.get(url, headers: authHeaders), as: AnimeSubject.self)
    }

    func episodes(subjectID: Int) async throws -> [AnimeEpisode] {
        struct Response: Decodable { let data: [AnimeEpisode]?; let total: Int? }
        var components = URLComponents(url: base.appendingPathComponent("v0/episodes"),
                                       resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "subject_id", value: "\(subjectID)"),
            URLQueryItem(name: "type", value: "0"),
            URLQueryItem(name: "limit", value: "100"),
            URLQueryItem(name: "offset", value: "0")
        ]
        let response = try await client.json(.get(components.url!, headers: authHeaders),
                                             as: Response.self)
        return (response.data ?? []).sorted { $0.sort < $1.sort }
    }

    func characters(subjectID: Int) async throws -> [AnimeCharacter] {
        struct Actor: Decodable { let name: String? }
        struct Entry: Decodable {
            let id: Int
            let name: String?
            let relation: String?
            let images: [String: String]?
            let actors: [Actor]?
        }
        let url = base.appendingPathComponent("v0/subjects/\(subjectID)/characters")
        let entries = try await client.json(.get(url, headers: authHeaders), as: [Entry].self)
        return entries.map { entry in
            AnimeCharacter(
                id: entry.id,
                name: entry.name ?? "",
                relation: entry.relation ?? "",
                image: entry.images?["grid"] ?? entry.images?["medium"] ?? "",
                actors: (entry.actors ?? []).compactMap(\.name)
            )
        }
    }

    // MARK: - 制作人员

    func staffs(subjectID: Int) async throws -> [AnimeStaff] {
        struct Entry: Decodable {
            let id: Int
            let name: String?
            let relation: String?
            let images: [String: String]?
        }
        let url = base.appendingPathComponent("v0/subjects/\(subjectID)/staffs")
        let entries = try await client.json(.get(url, headers: authHeaders), as: [Entry].self)
        return entries.map {
            AnimeStaff(id: $0.id,
                       name: $0.name ?? "",
                       relation: $0.relation ?? "",
                       image: $0.images?["grid"] ?? $0.images?["medium"] ?? "")
        }
    }

    // MARK: - 评论（吐槽箱）

    func comments(subjectID: Int, limit: Int = 20) async throws -> [AnimeComment] {
        struct User: Decodable {
            let username: String?
            let nickname: String?
            let avatar: [String: String]?
        }
        struct Entry: Decodable {
            let user: User?
            let rate: Int?
            let comment: String?
            let updatedAt: String?

            enum CodingKeys: String, CodingKey {
                case user, rate, comment
                case updatedAt = "updated_at"
            }
        }
        struct Response: Decodable { let data: [Entry]?; let total: Int? }

        var components = URLComponents(
            url: base.appendingPathComponent("v0/subjects/\(subjectID)/comments"),
            resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "limit", value: "\(limit)"),
            URLQueryItem(name: "offset", value: "0")
        ]
        let response = try await client.json(.get(components.url!, headers: authHeaders),
                                             as: Response.self)
        return (response.data ?? []).map { entry in
            let name = entry.user?.username
                ?? entry.user?.nickname
                ?? "匿名"
            let date = entry.updatedAt ?? ""
            return AnimeComment(id: Self.stableID(name + date + (entry.comment ?? "")),
                                userName: name,
                                avatar: entry.user?.avatar?["large"] ?? "",
                                score: entry.rate ?? 0,
                                content: entry.comment ?? "",
                                date: date)
        }
    }

    /// 评论没有自带 id，用内容做个稳定的哈希（不用 hashValue，跨进程不稳定）。
    private static func stableID(_ text: String) -> Int {
        var hash = 5381
        for byte in text.utf8 {
            hash = (hash &* 33) &+ Int(byte)
        }
        return abs(hash & Int.max)
    }
}
