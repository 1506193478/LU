import Foundation

/// 简繁转换模式。对照 Flutter 侧 `lib/modules/danmaku/danmaku_ch_convert.dart`。
enum LuOpenCCMode: String, CaseIterable, Identifiable {
    case off
    case t2s          // 繁 → 简
    case s2t          // 简 → 繁

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: return "不转换"
        case .t2s: return "繁 → 简"
        case .s2t: return "简 → 繁"
        }
    }
}

/// 离线简繁转换。词典直接复用 Flutter 侧 `assets/opencc` 的四份 JSON
/// （字符表 + 词组表），先按词组最长匹配，再退回单字映射。
///
/// 词典较大（s2t 词组 22 万条），因此只在真正启用转换时加载，
/// 且加载过程放到后台线程，避免首帧卡顿。
final class LuOpenCC {
    static let shared = LuOpenCC()

    private final class Table {
        var characters: [Character: Character] = [:]
        var phrases: [Character: [(key: [Character], value: String)]] = [:]

        func convert(_ text: String) -> String {
            let chars = Array(text)
            guard !chars.isEmpty else { return text }
            var result = String()
            result.reserveCapacity(text.count)
            var index = 0
            while index < chars.count {
                if let candidates = phrases[chars[index]] {
                    var matched = false
                    for candidate in candidates {
                        let end = index + candidate.key.count
                        guard end <= chars.count else { continue }
                        if Array(chars[index..<end]) == candidate.key {
                            result += candidate.value
                            index = end
                            matched = true
                            break
                        }
                    }
                    if matched { continue }
                }
                if let mapped = characters[chars[index]] {
                    result.append(mapped)
                } else {
                    result.append(chars[index])
                }
                index += 1
            }
            return result
        }
    }

    private let lock = NSLock()
    private var t2sTable: Table?
    private var s2tTable: Table?

    private init() {}

    func convert(_ text: String, mode: LuOpenCCMode) -> String {
        guard mode != .off, !text.isEmpty else { return text }
        guard let table = table(for: mode) else { return text }
        return table.convert(text)
    }

    private func table(for mode: LuOpenCCMode) -> Table? {
        lock.lock()
        defer { lock.unlock() }
        switch mode {
        case .off:
            return nil
        case .t2s:
            if let t2sTable { return t2sTable }
            let table = load(prefix: "t2s")
            t2sTable = table
            return table
        case .s2t:
            if let s2tTable { return s2tTable }
            let table = load(prefix: "s2t")
            s2tTable = table
            return table
        }
    }

    private func load(prefix: String) -> Table {
        let table = Table()
        if let map = decode("\(prefix)_characters") {
            for (key, value) in map where key.count == 1 && value.count == 1 {
                if let k = key.first, let v = value.first {
                    table.characters[k] = v
                }
            }
        }
        if let map = decode("\(prefix)_phrases") {
            var index: [Character: [(key: [Character], value: String)]] = [:]
            index.reserveCapacity(map.count / 8)
            for (key, value) in map {
                let chars = Array(key)
                guard let first = chars.first, chars.count > 1 else { continue }
                index[first, default: []].append((chars, value))
            }
            for key in index.keys {
                index[key]?.sort { $0.key.count > $1.key.count }
            }
            table.phrases = index
        }
        luLogInfo("OpenCC", "加载词典 \(prefix)（字 \(table.characters.count) / 词 \(table.phrases.count)）")
        return table
    }

    private func decode(_ name: String) -> [String: String]? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            luLogWarn("OpenCC", "词典缺失：\(name).json")
            return nil
        }
        return try? JSONDecoder().decode([String: String].self, from: data)
    }
}
