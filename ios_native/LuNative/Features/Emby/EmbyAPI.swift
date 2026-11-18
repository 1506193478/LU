import Foundation
import UIKit

/// Emby 服务端 API。对照 Flutter 侧 `lib/modules/emby` 与 `lib/services/emby`，
/// 第一阶段覆盖：登录、媒体库、条目列表、封面、播放地址。
final class EmbyAPI {
    static let shared = EmbyAPI()
    private let client = HttpClient.shared

    private var deviceID: String {
        if let stored = UserDefaults.standard.string(forKey: "lu.emby.deviceId") {
            return stored
        }
        let id = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        UserDefaults.standard.set(id, forKey: "lu.emby.deviceId")
        return id
    }

    private func authHeader() -> String {
        "MediaBrowser Client=\"LU\", Device=\"iPhone\", DeviceId=\"\(deviceID)\", Version=\"5.0.0\""
    }

    // MARK: 登录

    func authenticate(server: URL, username: String, password: String) async throws -> EmbySession {
        struct User: Decodable {
            let Id: String?
            let Name: String?
        }
        struct Response: Decodable {
            let User: User?
            let AccessToken: String?
        }

        let url = server.appendingPathComponent("Users/AuthenticateByName")
        var request = HttpRequest(method: "POST", url: url)
        request.headers["X-Emby-Authorization"] = authHeader()
        request.headers["Content-Type"] = "application/json"
        request.body = try JSONSerialization.data(withJSONObject: [
            "Username": username,
            "Pw": password
        ])

        let response = try await client.json(request, as: Response.self)
        guard let token = response.AccessToken, let userID = response.User?.Id else {
            throw NetworkError.decoding("缺少 AccessToken")
        }
        return EmbySession(serverURL: server,
                           userID: userID,
                           accessToken: token,
                           userName: response.User?.Name ?? username,
                           deviceID: deviceID)
    }

    private func tokenHeaders(_ session: EmbySession) -> [String: String] {
        ["X-Emby-Token": session.accessToken,
         "X-Emby-Authorization": authHeader()]
    }

    // MARK: 媒体库

    func views(_ session: EmbySession) async throws -> [EmbyItem] {
        struct Response: Decodable { let Items: [EmbyItem]? }
        var components = URLComponents(url: session.serverURL
            .appendingPathComponent("Users/\(session.userID)/Views"),
            resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "IncludeExternalContent", value: "false")]
        let response = try await client.json(.get(components.url!, headers: tokenHeaders(session)),
                                             as: Response.self)
        return response.Items ?? []
    }

    func items(_ session: EmbySession, parentID: String) async throws -> [EmbyItem] {
        struct Response: Decodable { let Items: [EmbyItem]?; let TotalRecordCount: Int? }
        var components = URLComponents(url: session.serverURL.appendingPathComponent("Items"),
                                       resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "ParentId", value: parentID),
            URLQueryItem(name: "Recursive", value: "false"),
            URLQueryItem(name: "IncludeItemTypes", value: "Movie,Series,BoxSet,Folder,Video"),
            URLQueryItem(name: "SortBy", value: "SortName"),
            URLQueryItem(name: "SortOrder", value: "Ascending"),
            URLQueryItem(name: "Fields", value: "PrimaryImageAspectRatio,Overview,ChildCount"),
            URLQueryItem(name: "ImageTypeLimit", value: "1"),
            URLQueryItem(name: "Limit", value: "200")
        ]
        let response = try await client.json(.get(components.url!, headers: tokenHeaders(session)),
                                             as: Response.self)
        return response.Items ?? []
    }

    func episodes(_ session: EmbySession, seriesID: String) async throws -> [EmbyItem] {
        var components = URLComponents(url: session.serverURL.appendingPathComponent("Shows/\(seriesID)/Episodes"),
                                       resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "UserId", value: session.userID),
            URLQueryItem(name: "Fields", value: "Overview,PrimaryImageAspectRatio"),
            URLQueryItem(name: "Limit", value: "500")
        ]
        struct Response: Decodable { let Items: [EmbyItem]? }
        let response = try await client.json(.get(components.url!, headers: tokenHeaders(session)),
                                             as: Response.self)
        return response.Items ?? []
    }

    // MARK: 图片 / 播放

    func imageURL(_ session: EmbySession, item: EmbyItem, maxWidth: Int = 400) -> URL? {
        guard item.imageTag != nil else { return nil }
        var components = URLComponents(
            url: session.serverURL.appendingPathComponent("Items/\(item.id)/Images/Primary"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "maxWidth", value: "\(maxWidth)"),
            URLQueryItem(name: "quality", value: "90"),
            URLQueryItem(name: "api_key", value: session.accessToken)
        ]
        return components.url
    }

    /// HLS 转码地址。服务端按能力实时转码，兼容性最好；
    /// 失败时调用 `directStreamURL` 退回直连。
    func hlsURL(_ session: EmbySession, item: EmbyItem) -> URL? {
        var components = URLComponents(
            url: session.serverURL.appendingPathComponent("Videos/\(item.id)/master.m3u8"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "MediaSourceId", value: item.id),
            URLQueryItem(name: "VideoCodec", value: "h264"),
            URLQueryItem(name: "AudioCodec", value: "aac"),
            URLQueryItem(name: "TranscodingContainer", value: "ts"),
            URLQueryItem(name: "TranscodingProtocol", value: "hls"),
            URLQueryItem(name: "api_key", value: session.accessToken),
            URLQueryItem(name: "DeviceId", value: deviceID)
        ]
        return components.url
    }

    /// 标记已看。Emby 的 PlayedItems 接口用 DELETE 取消、POST 标记。
    func markPlayed(session: EmbySession, itemID: String) async throws {
        var request = HttpRequest(method: "POST",
                                  url: session.serverURL.appendingPathComponent("Users/\(session.userID)/PlayedItems/\(itemID)"))
        request.headers = tokenHeaders(session)
        _ = try await client.send(request)
    }

    func directStreamURL(_ session: EmbySession, item: EmbyItem) -> URL? {
        var components = URLComponents(
            url: session.serverURL.appendingPathComponent("Videos/\(item.id)/stream"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "Static", value: "true"),
            URLQueryItem(name: "api_key", value: session.accessToken)
        ]
        return components.url
    }
}

// MARK: - 元数据刮削（路线 A）

/// Emby 服务端自带 TMDB 等刮削器，客户端只需要调 RemoteSearch + Apply，
/// 不用自己存 TMDB API Key，也不会把密钥泄漏到客户端。
struct EmbyRemoteResult: Identifiable {
    let id: String
    let name: String
    let year: Int?
    let overview: String
    let imageURL: URL?
    /// 原始 JSON（Apply 时原样回传）
    let payload: Data
}

extension EmbyAPI {

    private func remoteSearchPath(for type: String) -> String {
        switch type {
        case "Series": return "Items/RemoteSearch/Series"
        case "Episode": return "Items/RemoteSearch/Episode"
        case "BoxSet": return "Items/RemoteSearch/BoxSet"
        default: return "Items/RemoteSearch/Movie"
        }
    }

    func remoteSearch(session: EmbySession,
                      item: EmbyItem,
                      name: String,
                      year: Int?) async throws -> [EmbyRemoteResult] {
        var searchInfo: [String: Any] = ["Name": name]
        if let year { searchInfo["Year"] = year }
        if item.type == "Episode" {
            searchInfo["SeriesName"] = item.seriesName ?? ""
            if let index = item.indexNumber { searchInfo["IndexNumber"] = index }
            if let season = item.parentIndexNumber { searchInfo["ParentIndexNumber"] = season }
        }
        let body: [String: Any] = [
            "SearchInfo": searchInfo,
            "IncludePeople": false,
            "IncludeMediaInfo": false,
            "IncludeGenres": false,
            "IncludeStudios": false,
            "Limit": 12
        ]

        var request = HttpRequest(method: "POST",
                                  url: session.serverURL.appendingPathComponent(remoteSearchPath(for: item.type)))
        request.headers = tokenHeaders(session)
        request.headers["Content-Type"] = "application/json"
        request.body = try JSONSerialization.data(withJSONObject: body)

        let data = try await client.send(request)
        guard let array = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }
        return array.enumerated().compactMap { index, entry in
            guard let entryData = try? JSONSerialization.data(withJSONObject: entry) else { return nil }
            let name = entry["Name"] as? String ?? "未命名"
            let year = entry["ProductionYear"] as? Int
            let overview = entry["Overview"] as? String ?? ""
            let image = (entry["ImageUrl"] as? String).flatMap { URL(string: $0) }
            return EmbyRemoteResult(id: "\(index)-\(name)", name: name, year: year,
                                    overview: overview, imageURL: image, payload: entryData)
        }
    }

    func applyRemoteResult(session: EmbySession, item: EmbyItem,
                           payload: Data, replaceImages: Bool = true) async throws {
        var components = URLComponents(
            url: session.serverURL.appendingPathComponent("Items/RemoteSearch/Apply/\(item.id)"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [URLQueryItem(name: "ReplaceAllImages",
                                              value: replaceImages ? "true" : "false")]
        var request = HttpRequest(method: "POST", url: components.url!)
        request.headers = tokenHeaders(session)
        request.headers["Content-Type"] = "application/json"
        request.body = payload
        _ = try await client.send(request)
        luLogInfo("Emby", "元数据已应用：\(item.name)")
    }
}
