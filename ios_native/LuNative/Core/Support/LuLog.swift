import Foundation
import Combine

/// 日志级别。对照 Flutter 侧 `lib/services/logging/logger.dart`。
enum LuLogLevel: String, Codable, CaseIterable, Identifiable {
    case debug = "DEBUG"
    case info = "INFO"
    case warn = "WARN"
    case error = "ERROR"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .debug: return "调试"
        case .info: return "信息"
        case .warn: return "警告"
        case .error: return "错误"
        }
    }
}

struct LuLogEntry: Identifiable, Codable, Hashable {
    let id: UUID
    let date: Date
    let level: LuLogLevel
    let tag: String
    let message: String
}

/// 应用日志：内存环形缓冲（供日志页实时查看）+ 文件追加（供导出）。
///
/// 只保留最近 3000 条在内存里。播放解析、网络请求这类高频路径都走这里，
/// 不做格式化开销大的工作，落盘在串行队列上完成。
final class LuLog: ObservableObject {
    static let shared = LuLog()

    @Published private(set) var entries: [LuLogEntry] = []

    private let lock = NSLock()
    private var storage: [LuLogEntry] = []
    private let limit = 3000
    private let fileURL: URL
    private let ioQueue = DispatchQueue(label: "lu.log.io", qos: .utility)
    private let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm:ss.SSS"
        f.locale = Locale(identifier: "zh_CN")
        return f
    }()

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask)[0]
            .appendingPathComponent("LU", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        fileURL = base.appendingPathComponent("lu.log")
        // 单文件超过 2MB 就轮转一次，避免无限膨胀
        if let size = try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int,
           size > 2 * 1024 * 1024 {
            try? FileManager.default.removeItem(at: fileURL)
        }
    }

    func write(_ level: LuLogLevel, _ tag: String, _ message: String) {
        let entry = LuLogEntry(id: UUID(), date: Date(), level: level,
                               tag: tag, message: message)
        lock.lock()
        storage.append(entry)
        if storage.count > limit {
            storage.removeFirst(storage.count - limit)
        }
        let snapshot = storage
        lock.unlock()

        if Thread.isMainThread {
            entries = snapshot
        } else {
            DispatchQueue.main.async { [weak self] in self?.entries = snapshot }
        }

        ioQueue.async { [weak self] in
            guard let self else { return }
            // DateFormatter 非线程安全，统一在 io 队列里格式化
            let line = "\(self.formatter.string(from: entry.date)) [\(entry.level.rawValue)] "
                + "[\(entry.tag)] \(entry.message)\n"
            guard let data = line.data(using: .utf8) else { return }
            if let handle = try? FileHandle(forWritingTo: self.fileURL) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            } else {
                try? data.write(to: self.fileURL, options: .atomic)
            }
        }
    }

    func clear() {
        lock.lock()
        storage.removeAll()
        lock.unlock()
        entries = []
        ioQueue.async { [weak self] in
            guard let self else { return }
            try? FileManager.default.removeItem(at: self.fileURL)
        }
    }

    func exportText(level: LuLogLevel? = nil) -> String {
        lock.lock()
        let snapshot = storage
        lock.unlock()
        let filtered = level.map { target in snapshot.filter { $0.level == target } } ?? snapshot
        let header = "LU 日志导出 · \(formatter.string(from: Date())) · \(filtered.count) 条\n\n"
        return header + filtered.map {
            "\(formatter.string(from: $0.date)) [\($0.level.rawValue)] [\($0.tag)] \($0.message)"
        }.joined(separator: "\n")
    }

    var lastError: LuLogEntry? {
        lock.lock()
        let snapshot = storage
        lock.unlock()
        return snapshot.last { $0.level == .error }
    }
}

func luLogDebug(_ tag: String, _ message: String) {
    LuLog.shared.write(.debug, tag, message)
}

func luLogInfo(_ tag: String, _ message: String) {
    LuLog.shared.write(.info, tag, message)
}

func luLogWarn(_ tag: String, _ message: String) {
    LuLog.shared.write(.warn, tag, message)
}

func luLogError(_ tag: String, _ message: String) {
    LuLog.shared.write(.error, tag, message)
}
