import Foundation

/// 本地备份。一个 JSON 覆盖：收藏、历史、插件、常用设置。
/// 敏感项（Bangumi token、弹弹play Secret、Emby 密码、WebDAV 密码）**不导出**。
struct LuBackup: Codable {
    var version: Int = 1
    var createdAt: Date = Date()
    var appVersion: String = UpdateChecker.currentVersion
    var collects: [CollectRecord] = []
    var history: [HistoryRecord] = []
    var plugins: [PluginManifest] = []
    var settings: [String: String] = [:]
}

enum LuBackupError: LocalizedError {
    case empty
    case badFormat

    var errorDescription: String? {
        switch self {
        case .empty: return "备份文件是空的"
        case .badFormat: return "不是有效的 LU 备份文件"
        }
    }
}

enum LuBackupService {

    struct Summary {
        var collects: Int
        var history: Int
        var plugins: Int
    }

    /// 导出到「文件」可见的目录，返回文件 URL 供 ShareLink / 文件 App 使用
    static func export() throws -> URL {
        var backup = LuBackup()
        backup.collects = AppState.shared.collects
        backup.history = AppState.shared.history
        backup.plugins = PluginStore.shared.plugins
        backup.settings = exportSettings()

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(backup)

        let stamp = ISO8601DateFormatter()
        stamp.formatOptions = [.withFullDate, .withTime, .withColonSeparatorInTime]
        let name = "LU-backup-\(stamp.string(from: Date()).replacingOccurrences(of: ":", with: "-")).json"

        let directory = FileManager.default.urls(for: .documentDirectory,
                                                 in: .userDomainMask)[0]
        let url = directory.appendingPathComponent(name)
        try data.write(to: url, options: .atomic)
        luLogInfo("Backup", "导出 \(name) · \(data.count) 字节")
        return url
    }

    @discardableResult
    static func restore(from url: URL) throws -> Summary {
        let needsScope = url.startAccessingSecurityScopedResource()
        defer { if needsScope { url.stopAccessingSecurityScopedResource() } }

        let data = try Data(contentsOf: url)
        guard !data.isEmpty else { throw LuBackupError.empty }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let backup = try? decoder.decode(LuBackup.self, from: data) else {
            throw LuBackupError.badFormat
        }

        AppState.shared.merge(collected: backup.collects, history: backup.history)
        for plugin in backup.plugins {
            PluginStore.shared.save(plugin)
        }
        applySettings(backup.settings)
        LuUpdateReminder.shared.refresh()

        let summary = Summary(collects: backup.collects.count,
                              history: backup.history.count,
                              plugins: backup.plugins.count)
        luLogInfo("Backup", "恢复 \(summary.collects) 收藏 / \(summary.history) 历史 / \(summary.plugins) 插件")
        return summary
    }

    // MARK: 设置白名单

    private static func exportSettings() -> [String: String] {
        let s = AppSettings.shared
        var map: [String: String] = [:]
        map["appearance"] = s.appearance.rawValue
        map["accent"] = s.accent
        map["hiddenTabs"] = s.hiddenTabs
        map["danmakuEnabled"] = s.danmakuEnabled ? "1" : "0"
        map["danmakuOpacity"] = "\(s.danmakuOpacity)"
        map["danmakuFontSize"] = "\(s.danmakuFontSize)"
        map["danmakuSpeed"] = "\(s.danmakuSpeed)"
        map["danmakuArea"] = "\(s.danmakuArea)"
        map["danmakuSource"] = s.danmakuSource
        map["textConvert"] = s.textConvert
        map["shieldWords"] = s.shieldWords
        map["autoPlayNext"] = s.autoPlayNext ? "1" : "0"
        map["rememberPosition"] = s.rememberPosition ? "1" : "0"
        map["skipIntroSeconds"] = "\(s.skipIntroSeconds)"
        map["keepScreenOn"] = s.keepScreenOn ? "1" : "0"
        map["videoEnhance"] = s.videoEnhance
        map["aspectMode"] = s.aspectMode
        map["syncPlayName"] = s.syncPlayName
        map["syncRelayURL"] = s.syncRelayURL
        map["updateReminder"] = s.updateReminder ? "1" : "0"
        return map
    }

    private static func applySettings(_ map: [String: String]) {
        guard !map.isEmpty else { return }
        let s = AppSettings.shared
        if let raw = map["appearance"], let value = AppAppearance(rawValue: raw) { s.appearance = value }
        if let raw = map["accent"], LuAccent(rawValue: raw) != nil { s.accent = raw }
        if let raw = map["hiddenTabs"] { s.hiddenTabs = raw }
        if let raw = map["danmakuEnabled"] { s.danmakuEnabled = raw == "1" }
        if let raw = map["danmakuOpacity"], let value = Double(raw) { s.danmakuOpacity = value }
        if let raw = map["danmakuFontSize"], let value = Double(raw) { s.danmakuFontSize = value }
        if let raw = map["danmakuSpeed"], let value = Double(raw) { s.danmakuSpeed = value }
        if let raw = map["danmakuArea"], let value = Double(raw) { s.danmakuArea = value }
        if let raw = map["danmakuSource"] { s.danmakuSource = raw }
        if let raw = map["textConvert"] { s.textConvert = raw }
        if let raw = map["shieldWords"] { s.shieldWords = raw }
        if let raw = map["autoPlayNext"] { s.autoPlayNext = raw == "1" }
        if let raw = map["rememberPosition"] { s.rememberPosition = raw == "1" }
        if let raw = map["skipIntroSeconds"], let value = Int(raw) { s.skipIntroSeconds = value }
        if let raw = map["keepScreenOn"] { s.keepScreenOn = raw == "1" }
        if let raw = map["videoEnhance"] { s.videoEnhance = raw }
        if let raw = map["aspectMode"] { s.aspectMode = raw }
        if let raw = map["syncPlayName"], !raw.isEmpty { s.syncPlayName = raw }
        if let raw = map["syncRelayURL"] { s.syncRelayURL = raw }
        if let raw = map["updateReminder"] { s.updateReminder = raw == "1" }
    }
}
