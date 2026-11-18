import Foundation
import Combine

/// 应用级数据仓库：收藏、历史、搜索历史。
/// 对照 Flutter 侧 `lib/repositories/*`，第一阶段用 JSON 文档存储，
/// 数据规模（千条内）足够，后续可平滑替换为 Core Data。
final class AppState: ObservableObject {
    static let shared = AppState()

    private let collectStore = JSONStore<[CollectRecord]>(name: "collect", defaultValue: [])
    private let historyStore = JSONStore<[HistoryRecord]>(name: "history", defaultValue: [])
    private let searchStore = JSONStore<[String]>(name: "searchHistory", defaultValue: [])

    @Published private(set) var collects: [CollectRecord] = []
    @Published private(set) var history: [HistoryRecord] = []
    @Published private(set) var searchHistory: [String] = []

    /// 深链待打开的条目（RootView 消费后置回 nil）
    @Published var pendingSubjectID: Int?

    private init() {
        collects = collectStore.value
        history = historyStore.value
        searchHistory = searchStore.value
    }

    // MARK: - 收藏

    func isCollected(_ subjectID: Int) -> Bool {
        collects.contains { $0.subject.id == subjectID }
    }

    @discardableResult
    func toggleCollect(_ subject: AnimeSubject) -> Bool {
        if let index = collects.firstIndex(where: { $0.subject.id == subject.id }) {
            collects.remove(at: index)
            collectStore.update { $0 = self.collects }
            LuUpdateReminder.shared.refresh()
            return false
        } else {
            collects.insert(CollectRecord(subject: subject), at: 0)
            collectStore.update { $0 = self.collects }
            LuUpdateReminder.shared.refresh()
            return true
        }
    }

    func removeCollect(subjectID: Int) {
        collects.removeAll { $0.subject.id == subjectID }
        collectStore.update { $0 = self.collects }
        LuUpdateReminder.shared.refresh()
    }

    var collectCount: Int { collects.count }

    // MARK: - 历史

    func recordPlayback(subject: AnimeSubject, episode: AnimeEpisode,
                        position: Double, duration: Double) {
        guard position > 5 else { return }   // 5 秒以内的误触不记
        let record = HistoryRecord(
            subjectID: subject.id,
            subjectName: subject.displayName,
            cover: subject.images["common"] ?? subject.images["medium"] ?? "",
            episodeID: episode.id,
            episodeName: episode.displayName,
            position: position,
            duration: duration,
            updatedAt: Date()
        )
        history.removeAll { $0.subjectID == subject.id && $0.episodeID == episode.id }
        history.insert(record, at: 0)
        if history.count > 300 { history = Array(history.prefix(300)) }
        historyStore.update { $0 = self.history }
    }

    func resumePosition(subjectID: Int, episodeID: Int) -> Double {
        history.first { $0.subjectID == subjectID && $0.episodeID == episodeID }?.position ?? 0
    }

    func lastEpisode(subjectID: Int) -> HistoryRecord? {
        history.first { $0.subjectID == subjectID }
    }

    func clearHistory() {
        history.removeAll()
        historyStore.update { $0 = [] }
    }

    // MARK: - 搜索历史

    func rememberSearch(_ keyword: String) {
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        searchHistory.removeAll { $0.caseInsensitiveCompare(trimmed) == .orderedSame }
        searchHistory.insert(trimmed, at: 0)
        if searchHistory.count > 20 { searchHistory = Array(searchHistory.prefix(20)) }
        searchStore.update { $0 = self.searchHistory }
    }

    // MARK: - 备份恢复

    /// 合并式恢复：同 id 以备份为准，不删除本地多出来的条目。
    func merge(collected: [CollectRecord], history importedHistory: [HistoryRecord]) {
        var byID: [Int: CollectRecord] = [:]
        for record in collects { byID[record.id] = record }
        for record in collected { byID[record.id] = record }
        let merged = byID.values.sorted { $0.updatedAt > $1.updatedAt }
        collects = merged
        collectStore.update { $0 = merged }

        var historyMap: [String: HistoryRecord] = [:]
        for record in history { historyMap[record.id] = record }
        for record in importedHistory { historyMap[record.id] = record }
        let mergedHistory = historyMap.values.sorted { $0.updatedAt > $1.updatedAt }
        history = mergedHistory
        historyStore.update { $0 = mergedHistory }
        luLogInfo("Backup", "恢复收藏 \(collected.count) 条、历史 \(importedHistory.count) 条")
    }

    func clearSearchHistory() {
        searchHistory.removeAll()
        searchStore.update { $0 = [] }
    }
}
