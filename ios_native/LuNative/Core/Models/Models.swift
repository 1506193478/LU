import Foundation

// MARK: - Bangumi 条目

/// 番剧条目。字段对齐 Bangumi v0 `/subjects/{id}` 与 `/calendar`，
/// 全部按「宽容解析」处理：任一字段缺失都不应导致整条丢弃。
struct AnimeSubject: Identifiable, Hashable, Codable {
    let id: Int
    var name: String
    var nameCN: String
    var summary: String
    var images: [String: String]
    var airDate: String
    var airWeekday: Int
    var eps: Int
    var platform: String
    var ratingScore: Double
    var ratingRank: Int
    var ratingTotal: Int
    var tags: [String]

    var displayName: String { nameCN.isEmpty ? name : nameCN }
    var originalName: String { name }
    var coverURL: URL? {
        for key in ["large", "common", "medium", "grid", "small"] {
            if let raw = images[key], let url = URL(string: raw) { return url }
        }
        return nil
    }

    var ratingText: String { ratingScore > 0 ? String(format: "%.1f", ratingScore) : "—" }

    static let empty = AnimeSubject(
        id: 0, name: "", nameCN: "", summary: "", images: [:], airDate: "",
        airWeekday: 0, eps: 0, platform: "", ratingScore: 0, ratingRank: 0,
        ratingTotal: 0, tags: []
    )

    init(id: Int, name: String, nameCN: String, summary: String, images: [String: String],
         airDate: String, airWeekday: Int, eps: Int, platform: String,
         ratingScore: Double, ratingRank: Int, ratingTotal: Int, tags: [String]) {
        self.id = id
        self.name = name
        self.nameCN = nameCN
        self.summary = summary
        self.images = images
        self.airDate = airDate
        self.airWeekday = airWeekday
        self.eps = eps
        self.platform = platform
        self.ratingScore = ratingScore
        self.ratingRank = ratingRank
        self.ratingTotal = ratingTotal
        self.tags = tags
    }

    private struct TagObject: Decodable { let name: String }
    private struct Images: Decodable {
        let large: String?
        let common: String?
        let medium: String?
        let small: String?
        let grid: String?
    }
    private struct Rating: Decodable {
        let score: Double?
        let rank: Int?
        let total: Int?
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, summary, images, date, platform, eps, tags, rating
        case nameCN = "name_cn"
        case airDate = "air_date"
        case airWeekday = "air_weekday"
        case totalEpisodes = "total_episodes"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(Int.self, forKey: .id)) ?? 0
        name = (try? c.decode(String.self, forKey: .name)) ?? ""
        nameCN = (try? c.decode(String.self, forKey: .nameCN)) ?? ""
        summary = (try? c.decode(String.self, forKey: .summary)) ?? ""
        platform = (try? c.decode(String.self, forKey: .platform)) ?? ""
        airDate = (try? c.decode(String.self, forKey: .airDate))
            ?? (try? c.decode(String.self, forKey: .date)) ?? ""
        airWeekday = (try? c.decode(Int.self, forKey: .airWeekday)) ?? 0
        eps = (try? c.decode(Int.self, forKey: .eps))
            ?? (try? c.decode(Int.self, forKey: .totalEpisodes)) ?? 0

        var imageMap: [String: String] = [:]
        if let img = try? c.decode(Images.self, forKey: .images) {
            if let v = img.large { imageMap["large"] = Self.normalize(v) }
            if let v = img.common { imageMap["common"] = Self.normalize(v) }
            if let v = img.medium { imageMap["medium"] = Self.normalize(v) }
            if let v = img.small { imageMap["small"] = Self.normalize(v) }
            if let v = img.grid { imageMap["grid"] = Self.normalize(v) }
        } else if let raw = try? c.decode([String: String].self, forKey: .images) {
            imageMap = raw.mapValues(Self.normalize)
        }
        images = imageMap

        if let r = try? c.decode(Rating.self, forKey: .rating) {
            ratingScore = r.score ?? 0
            ratingRank = r.rank ?? 0
            ratingTotal = r.total ?? 0
        } else {
            ratingScore = 0; ratingRank = 0; ratingTotal = 0
        }

        if let objs = try? c.decode([TagObject].self, forKey: .tags) {
            tags = objs.map(\.name)
        } else if let names = try? c.decode([String].self, forKey: .tags) {
            tags = names
        } else {
            tags = []
        }
    }

    private static func normalize(_ raw: String) -> String {
        // Bangumi 部分镜像返回 `//lain.bgm.tv/...`，补协议头
        if raw.hasPrefix("//") { return "https:" + raw }
        return raw
    }
}

// MARK: - 剧集

struct AnimeEpisode: Identifiable, Hashable, Codable {
    let id: Int
    var type: Int          // 0 本篇 / 1 SP / 2 OP / 3 ED
    var name: String
    var nameCN: String
    var sort: Double
    var airdate: String
    var duration: String

    var displayName: String {
        let base = nameCN.isEmpty ? name : nameCN
        let no = sort > 0 ? String(format: "%.0f", sort) : "?"
        return base.isEmpty ? "第 \(no) 话" : "\(no). \(base)"
    }

    private enum CodingKeys: String, CodingKey {
        case id, type, name, sort, airdate, duration
        case nameCN = "name_cn"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(Int.self, forKey: .id)) ?? 0
        type = (try? c.decode(Int.self, forKey: .type)) ?? 0
        name = (try? c.decode(String.self, forKey: .name)) ?? ""
        nameCN = (try? c.decode(String.self, forKey: .nameCN)) ?? ""
        sort = (try? c.decode(Double.self, forKey: .sort)) ?? 0
        airdate = (try? c.decode(String.self, forKey: .airdate)) ?? ""
        duration = (try? c.decode(String.self, forKey: .duration)) ?? ""
    }

    init(id: Int, type: Int, name: String, nameCN: String, sort: Double,
         airdate: String, duration: String) {
        self.id = id; self.type = type; self.name = name; self.nameCN = nameCN
        self.sort = sort; self.airdate = airdate; self.duration = duration
    }
}

// MARK: - 角色 / 制作人员 / 评论

struct AnimeCharacter: Identifiable, Hashable, Codable {
    let id: Int
    var name: String
    var relation: String
    var image: String
    var actors: [String]

    var imageURL: URL? {
        let raw = image.hasPrefix("//") ? "https:" + image : image
        return URL(string: raw)
    }
}

struct AnimeStaff: Identifiable, Hashable, Codable {
    let id: Int
    var name: String
    var relation: String
    var image: String

    var imageURL: URL? {
        guard !image.isEmpty else { return nil }
        let raw = image.hasPrefix("//") ? "https:" + image : image
        return URL(string: raw)
    }
}

struct AnimeComment: Identifiable, Hashable, Codable {
    let id: Int
    var userName: String
    var avatar: String
    var score: Int
    var content: String
    var date: String
}

// MARK: - 本地收藏 / 历史

struct CollectRecord: Identifiable, Hashable, Codable {
    var id: Int { subject.id }
    var subject: AnimeSubject
    var addedAt: Date
    var updatedAt: Date
    var note: String

    init(subject: AnimeSubject, note: String = "") {
        self.subject = subject
        self.addedAt = Date()
        self.updatedAt = Date()
        self.note = note
    }
}

struct HistoryRecord: Identifiable, Hashable, Codable {
    var id: String { "\(subjectID)-\(episodeID)" }
    var subjectID: Int
    var subjectName: String
    var cover: String
    var episodeID: Int
    var episodeName: String
    var position: Double      // 秒
    var duration: Double      // 秒
    var updatedAt: Date

    var progress: Double {
        guard duration > 0 else { return 0 }
        return min(max(position / duration, 0), 1)
    }
}

// MARK: - 播放源

/// 解析出来的可播流。`headers` 用于需要 Referer / UA 的直链。
struct PlayStream: Identifiable, Hashable {
    var id: String { url.absoluteString }
    let url: URL
    let quality: String
    var headers: [String: String] = [:]
    var isHLS: Bool { url.pathExtension.lowercased() == "m3u8" || url.absoluteString.contains(".m3u8") }
}

// MARK: - Emby

struct EmbySession: Codable, Hashable {
    var serverURL: URL
    var userID: String
    var accessToken: String
    var userName: String
    var deviceID: String
}

struct EmbyItem: Identifiable, Hashable, Codable {
    let id: String
    var name: String
    var type: String            // Movie / Series / Episode / Folder
    var seriesID: String?
    var seriesName: String?
    var seasonName: String?
    var indexNumber: Int?
    var parentIndexNumber: Int?
    var overview: String
    var imageTag: String?
    var runTimeTicks: Int64?
    var userDataPlayed: Bool
    var userDataPositionTicks: Int64?

    var isPlayable: Bool { type == "Movie" || type == "Episode" || type == "Video" }
    var duration: Double { Double(runTimeTicks ?? 0) / 10_000_000 }
    var position: Double { Double(userDataPositionTicks ?? 0) / 10_000_000 }

    private struct ImageTags: Decodable { let primary: String? }
    private struct UserData: Decodable {
        let played: Bool?
        let playbackPositionTicks: Int64?
    }

    private enum CodingKeys: String, CodingKey {
        case id = "Id"
        case name = "Name"
        case type = "Type"
        case seriesID = "SeriesId"
        case seriesName = "SeriesName"
        case seasonName = "SeasonName"
        case indexNumber = "IndexNumber"
        case parentIndexNumber = "ParentIndexNumber"
        case overview = "Overview"
        case imageTags = "ImageTags"
        case runTimeTicks = "RunTimeTicks"
        case userData = "UserData"
        case imageTag = "ImageTag"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(String.self, forKey: .id)) ?? UUID().uuidString
        name = (try? c.decode(String.self, forKey: .name)) ?? ""
        type = (try? c.decode(String.self, forKey: .type)) ?? ""
        seriesID = try? c.decode(String.self, forKey: .seriesID)
        seriesName = try? c.decode(String.self, forKey: .seriesName)
        seasonName = try? c.decode(String.self, forKey: .seasonName)
        indexNumber = try? c.decode(Int.self, forKey: .indexNumber)
        parentIndexNumber = try? c.decode(Int.self, forKey: .parentIndexNumber)
        overview = (try? c.decode(String.self, forKey: .overview)) ?? ""
        runTimeTicks = try? c.decode(Int64.self, forKey: .runTimeTicks)
        imageTag = (try? c.decode(ImageTags.self, forKey: .imageTags))?.primary
        if let data = try? c.decode(UserData.self, forKey: .userData) {
            userDataPlayed = data.played ?? false
            userDataPositionTicks = data.playbackPositionTicks
        } else {
            userDataPlayed = false
            userDataPositionTicks = nil
        }
    }

    init(id: String, name: String, type: String, seriesID: String? = nil,
         seriesName: String? = nil, seasonName: String? = nil,
         indexNumber: Int? = nil, parentIndexNumber: Int? = nil,
         overview: String = "", imageTag: String? = nil,
         runTimeTicks: Int64? = nil, userDataPlayed: Bool = false,
         userDataPositionTicks: Int64? = nil) {
        self.id = id; self.name = name; self.type = type
        self.seriesID = seriesID; self.seriesName = seriesName; self.seasonName = seasonName
        self.indexNumber = indexNumber; self.parentIndexNumber = parentIndexNumber
        self.overview = overview; self.imageTag = imageTag
        self.runTimeTicks = runTimeTicks; self.userDataPlayed = userDataPlayed
        self.userDataPositionTicks = userDataPositionTicks
    }
}
