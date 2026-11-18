import Foundation
import Combine

// MARK: - 模型

enum DownloadState: String, Codable {
    case waiting
    case running
    case paused
    case finished
    case failed

    var title: String {
        switch self {
        case .waiting: return "等待中"
        case .running: return "下载中"
        case .paused: return "已暂停"
        case .finished: return "已完成"
        case .failed: return "失败"
        }
    }
}

struct DownloadRecord: Identifiable, Codable, Hashable {
    var id: String
    var subjectID: Int
    var subjectName: String
    var episodeID: Int
    var episodeName: String
    var remoteURL: String
    var headers: [String: String]
    var quality: String
    var isHLS: Bool
    var fileName: String
    var state: DownloadState
    var progress: Double
    var bytesWritten: Int64
    var totalBytes: Int64
    var createdAt: Date
    var error: String?
    /// 相对 download 目录的播放路径（完成后才有值）
    var playbackPath: String?
}

enum DownloadError: LocalizedError {
    case badURL
    case http(Int)
    case emptyPlaylist
    case onlyMaster

    var errorDescription: String? {
        switch self {
        case .badURL: return "下载地址无效"
        case .http(let code): return "HTTP \(code)"
        case .emptyPlaylist: return "播放列表为空"
        case .onlyMaster: return "主播放列表里没有可用码率"
        }
    }
}

// MARK: - 下载管理

/// 离线下载。对照 Flutter 侧 `lib/services/download/*`。
///
/// - 直链（mp4 / flv 等）：`URLSessionDownloadTask`，支持暂停续传（同一进程内）
/// - HLS：自己拉分片并改写播放列表，把 `EXT-X-KEY` / `EXT-X-MAP` 一并本地化，
///   完成后可以直接用 `AVPlayer` 播放本地 `index.m3u8`（离线可用）
final class DownloadManager: NSObject, ObservableObject {
    static let shared = DownloadManager()

    @Published private(set) var records: [DownloadRecord] = []

    private let store = JSONStore<[DownloadRecord]>(name: "downloads", defaultValue: [])
    private var session: URLSession!
    private var taskMap: [Int: String] = [:]
    private var taskFileNames: [Int: String] = [:]
    private var resumeData: [String: Data] = [:]
    private var hlsJobs: [String: Task<Void, Never>] = [:]

    override init() {
        super.init()
        // 上次进程退出时还在跑的，一律归位为暂停
        records = store.value.map { record in
            var copy = record
            if copy.state == .running || copy.state == .waiting {
                copy.state = .paused
            }
            return copy
        }
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60 * 60 * 6
        config.httpAdditionalHeaders = ["User-Agent": LuUserAgent.value]
        session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }

    // MARK: 路径

    static var rootDirectory: URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Downloads", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    func directory(for id: String) -> URL {
        Self.rootDirectory.appendingPathComponent(id, isDirectory: true)
    }

    func localURL(for record: DownloadRecord) -> URL? {
        guard let path = record.playbackPath, !path.isEmpty else { return nil }
        let url = directory(for: record.id).appendingPathComponent(path)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    // MARK: 入队 / 控制

    @discardableResult
    func enqueue(stream: PlayStream, subjectID: Int, subjectName: String,
                 episodeID: Int, episodeName: String) -> String {
        let id = UUID().uuidString
        let extensionName: String = {
            if stream.isHLS { return "m3u8" }
            let ext = stream.url.pathExtension
            return ext.isEmpty ? "mp4" : ext
        }()
        var record = DownloadRecord(
            id: id,
            subjectID: subjectID,
            subjectName: subjectName,
            episodeID: episodeID,
            episodeName: episodeName,
            remoteURL: stream.url.absoluteString,
            headers: stream.headers,
            quality: stream.quality,
            isHLS: stream.isHLS,
            fileName: stream.isHLS ? "index.m3u8" : "video.\(extensionName)",
            state: .waiting,
            progress: 0,
            bytesWritten: 0,
            totalBytes: 0,
            createdAt: Date(),
            error: nil,
            playbackPath: nil
        )
        try? FileManager.default.createDirectory(at: directory(for: id),
                                                 withIntermediateDirectories: true)
        // 同一集重复下载时替换旧任务
        records.removeAll { $0.subjectID == subjectID && $0.episodeID == episodeID }
        record.state = .waiting
        records.insert(record, at: 0)
        persist()
        start(id)
        luLogInfo("Download", "入队 \(subjectName) \(episodeName) HLS=\(record.isHLS)")
        return id
    }

    func start(_ id: String) {
        guard let index = index(of: id) else { return }
        if records[index].isHLS {
            startHLS(id)
            return
        }
        guard let url = URL(string: records[index].remoteURL) else {
            update(id) { $0.state = .failed; $0.error = DownloadError.badURL.localizedDescription }
            return
        }
        var request = URLRequest(url: url)
        if let data = resumeData[id] {
            let task = session.downloadTask(withResumeData: data)
            taskMap[task.taskIdentifier] = id
            taskFileNames[task.taskIdentifier] = records[index].fileName
            resumeData[id] = nil
            task.resume()
            update(id) { $0.state = .running; $0.error = nil }
            return
        }
        records[index].headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        let task = session.downloadTask(with: request)
        taskMap[task.taskIdentifier] = id
        taskFileNames[task.taskIdentifier] = records[index].fileName
        task.resume()
        update(id) { $0.state = .running; $0.error = nil }
    }

    func pause(_ id: String) {
        guard let index = index(of: id) else { return }
        if records[index].isHLS {
            hlsJobs[id]?.cancel()
            hlsJobs[id] = nil
            update(id) { $0.state = .paused }
            persist()
            return
        }
        session.getTasksWithCompletionHandler { [weak self] _, _, downloads in
            guard let self else { return }
            let identifier = self.taskMap.first(where: { $0.value == id })?.key
            guard let identifier,
                  let task = downloads.first(where: { $0.taskIdentifier == identifier }) else {
                DispatchQueue.main.async {
                    self.update(id) { $0.state = .paused }
                    self.persist()
                }
                return
            }
            task.cancel(byProducingResumeData: { data in
                DispatchQueue.main.async {
                    self.resumeData[id] = data
                    self.update(id) { $0.state = .paused }
                    self.persist()
                }
            })
        }
    }

    func resume(_ id: String) {
        start(id)
    }

    func remove(_ id: String) {
        hlsJobs[id]?.cancel()
        hlsJobs[id] = nil
        resumeData[id] = nil
        session.getTasksWithCompletionHandler { [weak self] _, _, downloads in
            guard let self else { return }
            let identifiers = self.taskMap.filter { $0.value == id }.map { $0.key }
            downloads.filter { identifiers.contains($0.taskIdentifier) }.forEach { $0.cancel() }
        }
        try? FileManager.default.removeItem(at: directory(for: id))
        records.removeAll { $0.id == id }
        persist()
    }

    func clearFinished() {
        let finished = records.filter { $0.state == .finished || $0.state == .failed }
        for record in finished {
            try? FileManager.default.removeItem(at: directory(for: record.id))
        }
        records.removeAll { $0.state == .finished || $0.state == .failed }
        persist()
    }

    var totalBytes: Int64 {
        records.reduce(0) { $0 + $1.bytesWritten }
    }

    // MARK: 内部

    private func index(of id: String) -> Int? {
        records.firstIndex { $0.id == id }
    }

    private func update(_ id: String, _ mutate: (inout DownloadRecord) -> Void) {
        guard let index = index(of: id) else { return }
        mutate(&records[index])
    }

    private func persist() {
        let snapshot = records
        store.update { $0 = snapshot }
    }

    private func startHLS(_ id: String) {
        hlsJobs[id]?.cancel()
        update(id) { $0.state = .running; $0.error = nil }
        hlsJobs[id] = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.downloadHLS(id: id)
            } catch is CancellationError {
                // 用户暂停
            } catch {
                await MainActor.run {
                    self.update(id) {
                        $0.state = .failed
                        $0.error = error.localizedDescription
                    }
                    self.persist()
                    luLogWarn("Download", "HLS 失败：\(error.localizedDescription)")
                }
            }
        }
    }

    private func downloadHLS(id: String) async throws {
        guard let record = records.first(where: { $0.id == id }),
              let playlistURL = URL(string: record.remoteURL) else {
            throw DownloadError.badURL
        }
        let dir = directory(for: id)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        var text = try await fetchText(playlistURL, headers: record.headers)
        // 主列表：挑码率最高的一路
        if text.contains("#EXT-X-STREAM-INF") {
            guard let variant = Self.bestVariant(in: text, base: playlistURL) else {
                throw DownloadError.onlyMaster
            }
            text = try await fetchText(variant, headers: record.headers)
        }
        guard text.contains("#EXTINF") || text.contains("#EXT-X-MAP") else {
            throw DownloadError.emptyPlaylist
        }

        let lines = text.replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)

        var output: [String] = []
        var segments: [(remote: URL, local: String)] = []
        var keyCount = 0
        var mapCount = 0
        let fileNamePattern = try NSRegularExpression(pattern: #"URI="([^"]+)""#)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#EXT-X-KEY") {
                if let uri = Self.firstMatch(fileNamePattern, in: line, group: 1),
                   !uri.isEmpty, !trimmed.contains("METHOD=NONE") {
                    let keyURL = URL(string: uri, relativeTo: playlistURL)?.absoluteURL
                    if let keyURL {
                        let keyData = try await downloadData(keyURL, headers: record.headers)
                        let localName = "key_\(keyCount).bin"
                        try keyData.write(to: dir.appendingPathComponent(localName))
                        keyCount += 1
                        output.append(line.replacingOccurrences(of: uri, with: localName))
                        continue
                    }
                }
                output.append(line)
                continue
            }
            if trimmed.hasPrefix("#EXT-X-MAP") {
                if let uri = Self.firstMatch(fileNamePattern, in: line, group: 1),
                   let mapURL = URL(string: uri, relativeTo: playlistURL)?.absoluteURL {
                    let data = try await downloadData(mapURL, headers: record.headers)
                    let localName = "init_\(mapCount).mp4"
                    try data.write(to: dir.appendingPathComponent(localName))
                    mapCount += 1
                    output.append(line.replacingOccurrences(of: uri, with: localName))
                    continue
                }
                output.append(line)
                continue
            }
            if trimmed.hasPrefix("#EXT-X-BYTERANGE") {
                // 本地整段下载，去掉 BYTERANGE 避免播放器按偏移读错
                continue
            }
            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                output.append(line)
                continue
            }
            guard let segmentURL = URL(string: trimmed, relativeTo: playlistURL)?.absoluteURL else {
                continue
            }
            let ext = segmentURL.pathExtension.isEmpty ? "ts" : segmentURL.pathExtension
            let localName = String(format: "seg_%05d.%@", segments.count, ext)
            segments.append((segmentURL, localName))
            output.append(localName)
        }

        guard !segments.isEmpty else { throw DownloadError.emptyPlaylist }

        for (offset, segment) in segments.enumerated() {
            try Task.checkCancellation()
            let data = try await downloadData(segment.remote, headers: record.headers)
            try data.write(to: dir.appendingPathComponent(segment.local))
            let progress = Double(offset + 1) / Double(segments.count)
            let bytes = Int64(data.count)
            await MainActor.run {
                self.update(id) { record in
                    record.progress = progress * 0.99
                    record.bytesWritten += bytes
                }
            }
        }

        let playlistText = output.joined(separator: "\n")
        try playlistText.write(to: dir.appendingPathComponent("index.m3u8"),
                               atomically: true, encoding: .utf8)
        await MainActor.run {
            self.update(id) { record in
                record.state = .finished
                record.progress = 1
                record.playbackPath = "index.m3u8"
            }
            self.persist()
            luLogInfo("Download", "HLS 完成 \(id) 分片 \(segments.count)")
        }
    }

    static func bestVariant(in text: String, base: URL) -> URL? {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n").map(String.init)
        var best: (bandwidth: Int, url: URL)?
        for (index, line) in lines.enumerated() where line.contains("#EXT-X-STREAM-INF") {
            let bandwidth = Int(Self.firstMatch(
                try! NSRegularExpression(pattern: #"BANDWIDTH=(\d+)"#), in: line, group: 1
            ) ?? "") ?? 0
            guard index + 1 < lines.count else { continue }
            let candidate = lines[index + 1].trimmingCharacters(in: .whitespaces)
            guard !candidate.isEmpty, !candidate.hasPrefix("#"),
                  let url = URL(string: candidate, relativeTo: base)?.absoluteURL else { continue }
            if best == nil || bandwidth > best!.bandwidth {
                best = (bandwidth, url)
            }
        }
        return best?.url
    }

    static func firstMatch(_ regex: NSRegularExpression, in text: String, group: Int) -> String? {
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              group < match.numberOfRanges,
              let found = Range(match.range(at: group), in: text) else { return nil }
        return String(text[found])
    }

    private func fetchText(_ url: URL, headers: [String: String]) async throws -> String {
        let data = try await downloadData(url, headers: headers)
        guard let text = String(data: data, encoding: .utf8) else {
            throw DownloadError.emptyPlaylist
        }
        return text
    }

    private func downloadData(_ url: URL, headers: [String: String]) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        if request.value(forHTTPHeaderField: "User-Agent") == nil {
            request.setValue(LuUserAgent.value, forHTTPHeaderField: "User-Agent")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw DownloadError.http(http.statusCode)
        }
        return data
    }
}

// MARK: - URLSession 回调

extension DownloadManager: URLSessionDownloadDelegate {

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard let id = taskMap[downloadTask.taskIdentifier] else { return }
        DispatchQueue.main.async {
            guard let index = self.index(of: id) else { return }
            self.records[index].bytesWritten = totalBytesWritten
            if totalBytesExpectedToWrite > 0 {
                self.records[index].totalBytes = totalBytesExpectedToWrite
                self.records[index].progress = min(1, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
            }
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        guard let id = taskMap[downloadTask.taskIdentifier],
              let fileName = taskFileNames[downloadTask.taskIdentifier] else { return }
        let dir = directory(for: id)
        let destination = dir.appendingPathComponent(fileName)
        var failure: String?
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: location, to: destination)
        } catch {
            failure = error.localizedDescription
        }
        DispatchQueue.main.async {
            self.update(id) { item in
                if let failure {
                    item.state = .failed
                    item.error = failure
                } else {
                    item.state = .finished
                    item.progress = 1
                    item.playbackPath = item.fileName
                }
            }
            self.persist()
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let id = taskMap[task.taskIdentifier] else { return }
        taskMap[task.taskIdentifier] = nil
        guard let error else { return }
        // 主动暂停不算失败
        let nsError = error as NSError
        if nsError.code == NSURLErrorCancelled { return }
        DispatchQueue.main.async {
            guard let index = self.index(of: id), self.records[index].state != .paused else { return }
            self.records[index].state = .failed
            self.records[index].error = error.localizedDescription
            self.persist()
            luLogError("Download", "失败：\(error.localizedDescription)")
        }
    }
}
