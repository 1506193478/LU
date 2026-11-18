import Foundation
import SwiftUI
import UIKit
import Combine

enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "浅色"
        case .dark: return "深色"
        }
    }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

/// 主题强调色。深浅色各一套，避免深色下发灰。
enum LuAccent: String, CaseIterable, Identifiable {
    case blue, indigo, purple, pink, orange, green, graphite

    var id: String { rawValue }

    var title: String {
        switch self {
        case .blue: return "海蓝"
        case .indigo: return "靛青"
        case .purple: return "紫罗兰"
        case .pink: return "樱粉"
        case .orange: return "暖橙"
        case .green: return "青草"
        case .graphite: return "石墨"
        }
    }

    var light: UIColor {
        switch self {
        case .blue: return UIColor(red: 0.10, green: 0.48, blue: 0.92, alpha: 1)
        case .indigo: return UIColor(red: 0.29, green: 0.33, blue: 0.86, alpha: 1)
        case .purple: return UIColor(red: 0.55, green: 0.35, blue: 0.90, alpha: 1)
        case .pink: return UIColor(red: 0.93, green: 0.31, blue: 0.55, alpha: 1)
        case .orange: return UIColor(red: 0.95, green: 0.53, blue: 0.16, alpha: 1)
        case .green: return UIColor(red: 0.16, green: 0.66, blue: 0.42, alpha: 1)
        case .graphite: return UIColor(white: 0.32, alpha: 1)
        }
    }

    var dark: UIColor {
        switch self {
        case .blue: return UIColor(red: 0.42, green: 0.80, blue: 1.00, alpha: 1)
        case .indigo: return UIColor(red: 0.58, green: 0.62, blue: 1.00, alpha: 1)
        case .purple: return UIColor(red: 0.74, green: 0.60, blue: 1.00, alpha: 1)
        case .pink: return UIColor(red: 1.00, green: 0.56, blue: 0.74, alpha: 1)
        case .orange: return UIColor(red: 1.00, green: 0.70, blue: 0.34, alpha: 1)
        case .green: return UIColor(red: 0.44, green: 0.88, blue: 0.62, alpha: 1)
        case .graphite: return UIColor(white: 0.78, alpha: 1)
        }
    }

    var color: Color {
        Color(uiColor: UIColor { trait in
            trait.userInterfaceStyle == .dark ? self.dark : self.light
        })
    }
}

/// 全局设置。UserDefaults 承载，改动即落盘。
/// 对照 Flutter 侧 `lib/bean/settings`，第一阶段只保留跨平台通用项。
final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    private let d = UserDefaults.standard

    @Published var appearance: AppAppearance {
        didSet { d.set(appearance.rawValue, forKey: "lu.appearance") }
    }
    @Published var defaultTab: String {
        didSet { d.set(defaultTab, forKey: "lu.defaultTab") }
    }
    /// 强调色（LuAccent.rawValue）
    @Published var accent: String { didSet { d.set(accent, forKey: "lu.theme.accent") } }
    /// 隐藏的底栏项，逗号分隔
    @Published var hiddenTabs: String { didSet { d.set(hiddenTabs, forKey: "lu.tabs.hidden") } }
    /// 追番更新提醒（本地通知）
    @Published var updateReminder: Bool { didSet { d.set(updateReminder, forKey: "lu.reminder.update") } }
    @Published var bangumiToken: String {
        didSet { d.set(bangumiToken, forKey: "lu.bangumiToken") }
    }

    // 弹幕
    @Published var danmakuEnabled: Bool { didSet { d.set(danmakuEnabled, forKey: "lu.dm.enabled") } }
    @Published var danmakuOpacity: Double { didSet { d.set(danmakuOpacity, forKey: "lu.dm.opacity") } }
    @Published var danmakuFontSize: Double { didSet { d.set(danmakuFontSize, forKey: "lu.dm.size") } }
    @Published var danmakuSpeed: Double { didSet { d.set(danmakuSpeed, forKey: "lu.dm.speed") } }
    @Published var danmakuArea: Double { didSet { d.set(danmakuArea, forKey: "lu.dm.area") } }
    @Published var shieldWords: String { didSet { d.set(shieldWords, forKey: "lu.dm.shield") } }
    /// 弹幕源：bilibili / dandanplay / off
    @Published var danmakuSource: String { didSet { d.set(danmakuSource, forKey: "lu.dm.source") } }
    /// 简繁转换：off / t2s / s2t
    @Published var textConvert: String { didSet { d.set(textConvert, forKey: "lu.dm.convert") } }
    @Published var dandanplayAppID: String {
        didSet {
            d.set(dandanplayAppID, forKey: "lu.dm.appId")
            DandanplayProvider.shared.appID = dandanplayAppID
        }
    }
    @Published var dandanplaySecret: String {
        didSet {
            d.set(dandanplaySecret, forKey: "lu.dm.secret")
            DandanplayProvider.shared.appSecret = dandanplaySecret
        }
    }

    // 播放
    @Published var autoPlayNext: Bool { didSet { d.set(autoPlayNext, forKey: "lu.play.autoNext") } }
    @Published var preferredQuality: String { didSet { d.set(preferredQuality, forKey: "lu.play.quality") } }
    @Published var rememberPosition: Bool { didSet { d.set(rememberPosition, forKey: "lu.play.remember") } }
    /// 跳过片头秒数，0 = 关闭
    @Published var skipIntroSeconds: Int { didSet { d.set(skipIntroSeconds, forKey: "lu.play.skipIntro") } }
    /// 播放时禁止锁屏
    @Published var keepScreenOn: Bool { didSet { d.set(keepScreenOn, forKey: "lu.play.keepAwake") } }
    /// 画质增强：off / sharpen / vivid / soft
    @Published var videoEnhance: String { didSet { d.set(videoEnhance, forKey: "lu.play.enhance") } }
    /// 画面比例：fit / fill / sixteenNine
    @Published var aspectMode: String { didSet { d.set(aspectMode, forKey: "lu.play.aspect") } }

    // Emby 会话（JSON 存储）
    @Published var embySession: EmbySession? {
        didSet {
            if let session = embySession, let data = try? JSONEncoder().encode(session) {
                d.set(data, forKey: "lu.emby.session")
            } else {
                d.removeObject(forKey: "lu.emby.session")
            }
        }
    }

    // WebDAV
    @Published var webdavURL: String { didSet { d.set(webdavURL, forKey: "lu.dav.url") } }
    @Published var webdavUser: String { didSet { d.set(webdavUser, forKey: "lu.dav.user") } }
    @Published var webdavPassword: String { didSet { d.set(webdavPassword, forKey: "lu.dav.pass") } }

    // 一起看
    @Published var syncPlayName: String { didSet { d.set(syncPlayName, forKey: "lu.sync.name") } }
    /// 跨网中继地址，例如 wss://lu-sync.deno.dev 或 1.2.3.4:8787
    @Published var syncRelayURL: String { didSet { d.set(syncRelayURL, forKey: "lu.sync.relay") } }

    // 自定义播放源（HLS 直链模板，供插件缺失时兜底）
    @Published var customSourceTemplate: String {
        didSet { d.set(customSourceTemplate, forKey: "lu.source.template") }
    }

    private init() {
        appearance = AppAppearance(rawValue: d.string(forKey: "lu.appearance") ?? "") ?? .system
        defaultTab = d.string(forKey: "lu.defaultTab") ?? "popular"
        accent = d.string(forKey: "lu.theme.accent") ?? LuAccent.blue.rawValue
        hiddenTabs = d.string(forKey: "lu.tabs.hidden") ?? ""
        updateReminder = d.object(forKey: "lu.reminder.update") as? Bool ?? false
        bangumiToken = d.string(forKey: "lu.bangumiToken") ?? ""
        danmakuEnabled = d.object(forKey: "lu.dm.enabled") as? Bool ?? true
        danmakuOpacity = d.object(forKey: "lu.dm.opacity") as? Double ?? 0.9
        danmakuFontSize = d.object(forKey: "lu.dm.size") as? Double ?? 17
        danmakuSpeed = d.object(forKey: "lu.dm.speed") as? Double ?? 1.0
        danmakuArea = d.object(forKey: "lu.dm.area") as? Double ?? 0.4
        shieldWords = d.string(forKey: "lu.dm.shield") ?? ""
        danmakuSource = d.string(forKey: "lu.dm.source") ?? DanmakuSourceKind.bilibili.rawValue
        textConvert = d.string(forKey: "lu.dm.convert") ?? LuOpenCCMode.off.rawValue
        dandanplayAppID = d.string(forKey: "lu.dm.appId") ?? ""
        dandanplaySecret = d.string(forKey: "lu.dm.secret") ?? ""
        autoPlayNext = d.object(forKey: "lu.play.autoNext") as? Bool ?? true
        preferredQuality = d.string(forKey: "lu.play.quality") ?? "1080p"
        rememberPosition = d.object(forKey: "lu.play.remember") as? Bool ?? true
        skipIntroSeconds = d.object(forKey: "lu.play.skipIntro") as? Int ?? 0
        keepScreenOn = d.object(forKey: "lu.play.keepAwake") as? Bool ?? true
        videoEnhance = d.string(forKey: "lu.play.enhance") ?? "off"
        aspectMode = d.string(forKey: "lu.play.aspect") ?? "fit"
        customSourceTemplate = d.string(forKey: "lu.source.template") ?? ""
        webdavURL = d.string(forKey: "lu.dav.url") ?? ""
        webdavUser = d.string(forKey: "lu.dav.user") ?? ""
        webdavPassword = d.string(forKey: "lu.dav.pass") ?? ""
        syncPlayName = d.string(forKey: "lu.sync.name") ?? UIDevice.current.name
        syncRelayURL = d.string(forKey: "lu.sync.relay") ?? ""
        if let data = d.data(forKey: "lu.emby.session") {
            embySession = try? JSONDecoder().decode(EmbySession.self, from: data)
        } else {
            embySession = nil
        }
        BangumiAPI.shared.accessToken = bangumiToken
        DandanplayProvider.shared.appID = dandanplayAppID
        DandanplayProvider.shared.appSecret = dandanplaySecret
    }

    func applyTokenToAPI() {
        BangumiAPI.shared.accessToken = bangumiToken
        DandanplayProvider.shared.appID = dandanplayAppID
        DandanplayProvider.shared.appSecret = dandanplaySecret
    }
}

/// 轻量 JSON 文档存储：收藏 / 历史 / 搜索历史 / 插件清单。
/// 数据量在千条级，整体读写足够；后续换 Core Data 只需替换本类。
final class JSONStore<T: Codable> {
    private let url: URL
    private let lock = NSLock()
    private var cache: T

    init(name: String, defaultValue: T) {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask)[0]
            .appendingPathComponent("LU", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        url = base.appendingPathComponent("\(name).json")
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let data = try? Data(contentsOf: url),
           let decoded = try? decoder.decode(T.self, from: data) {
            cache = decoded
        } else {
            cache = defaultValue
        }
    }

    var value: T {
        lock.lock(); defer { lock.unlock() }
        return cache
    }

    func update(_ mutate: (inout T) -> Void) {
        lock.lock()
        mutate(&cache)
        let snapshot = cache
        lock.unlock()
        persist(snapshot)
    }

    private func persist(_ value: T) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(value) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
