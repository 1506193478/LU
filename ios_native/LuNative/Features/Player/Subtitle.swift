import Foundation
import CoreFoundation

// MARK: - 字幕模型

struct SubtitleCue: Identifiable, Hashable {
    let id: Int
    let start: Double
    let end: Double
    let text: String
}

enum SubtitleFormat: String {
    case srt
    case vtt
    case ass
    case unknown

    static func detect(_ url: URL) -> SubtitleFormat {
        switch url.pathExtension.lowercased() {
        case "srt": return .srt
        case "vtt": return .vtt
        case "ass", "ssa": return .ass
        default: return .unknown
        }
    }

    static func detect(text: String, fallback: URL) -> SubtitleFormat {
        let head = text.prefix(400).uppercased()
        if head.contains("WEBVTT") { return .vtt }
        if head.contains("[SCRIPT INFO]") || head.contains("[EVENTS]") { return .ass }
        let byExtension = detect(fallback)
        return byExtension == .unknown ? .srt : byExtension
    }
}

struct SubtitleTrack: Identifiable, Hashable {
    var id: String { url.absoluteString }
    let url: URL
    let name: String
    let cues: [SubtitleCue]

    func cue(at time: Double) -> SubtitleCue? {
        // 二分查找当前时间所在的字幕块
        var low = 0
        var high = cues.count - 1
        while low <= high {
            let mid = (low + high) / 2
            let cue = cues[mid]
            if time < cue.start {
                high = mid - 1
            } else if time > cue.end {
                low = mid + 1
            } else {
                return cue
            }
        }
        return nil
    }
}

// MARK: - 解析

/// 外挂字幕解析。覆盖 SRT / WebVTT / ASS(SSA)，编码自动识别 UTF-8 与 GB18030。
enum SubtitleParser {

    static func parse(data: Data, url: URL) -> SubtitleTrack? {
        guard let text = decode(data) else { return nil }
        return parse(text: text, url: url)
    }

    static func parse(text: String, url: URL) -> SubtitleTrack? {
        let format = SubtitleFormat.detect(text: text, fallback: url)
        var cues: [SubtitleCue] = []
        switch format {
        case .vtt, .srt, .unknown:
            cues = parseSRTLike(text)
        case .ass:
            cues = parseASS(text)
        }
        guard !cues.isEmpty else { return nil }
        let normalized = cues.enumerated().map { index, cue in
            SubtitleCue(id: index, start: cue.start, end: cue.end, text: cue.text)
        }
        luLogInfo("Subtitle", "\(url.lastPathComponent) → \(normalized.count) 条（\(format.rawValue)）")
        return SubtitleTrack(url: url, name: url.deletingPathExtension().lastPathComponent,
                             cues: normalized)
    }

    static func decode(_ data: Data) -> String? {
        if let text = String(data: data, encoding: .utf8) {
            return text
        }
        let gb = CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
        )
        if let text = String(data: data, encoding: String.Encoding(rawValue: gb)) {
            return text
        }
        let big5 = CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.big5.rawValue)
        )
        return String(data: data, encoding: String.Encoding(rawValue: big5))
    }

    // MARK: SRT / VTT

    private static let timeLinePattern = try! NSRegularExpression(
        pattern: #"(\d{1,2}):(\d{2}):(\d{2})[,.](\d{1,3})\s*-->\s*(\d{1,2}):(\d{2}):(\d{2})[,.](\d{1,3})"#
    )

    static func parseSRTLike(_ text: String) -> [SubtitleCue] {
        let unified = text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        var cues: [SubtitleCue] = []
        for block in unified.components(separatedBy: "\n\n") {
            let lines = block.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            guard let timeIndex = lines.firstIndex(where: { $0.contains("-->") }) else { continue }
            let timeLine = lines[timeIndex]
            let range = NSRange(timeLine.startIndex..., in: timeLine)
            guard let match = timeLinePattern.firstMatch(in: timeLine, range: range) else { continue }
            let start = Double(component(match, 1, timeLine)) * 3600
                + Double(component(match, 2, timeLine)) * 60
                + Double(component(match, 3, timeLine))
                + Double(component(match, 4, timeLine)) / 1000
            let end = Double(component(match, 5, timeLine)) * 3600
                + Double(component(match, 6, timeLine)) * 60
                + Double(component(match, 7, timeLine))
                + Double(component(match, 8, timeLine)) / 1000
            let body = lines[(timeIndex + 1)...].joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !body.isEmpty, end > start else { continue }
            cues.append(SubtitleCue(id: cues.count, start: start, end: end,
                                    text: cleanMarkup(body)))
        }
        return cues
    }

    private static func component(_ match: NSTextCheckingResult, _ index: Int, _ source: String) -> Int {
        guard index < match.numberOfRanges,
              let range = Range(match.range(at: index), in: source) else { return 0 }
        return Int(source[range]) ?? 0
    }

    // MARK: ASS / SSA

    static func parseASS(_ text: String) -> [SubtitleCue] {
        let unified = text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = unified.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        // 以 Format 行确定 Start/End/Text 的下标，不同字幕组字段顺序不一样
        var startIndex = 1, endIndex = 2, textIndex = 9
        var inEvents = false
        var cues: [SubtitleCue] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") {
                inEvents = trimmed.lowercased().contains("events")
                continue
            }
            guard inEvents else { continue }
            if trimmed.lowercased().hasPrefix("format:") {
                let fields = trimmed.dropFirst("format:".count)
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
                for (index, field) in fields.enumerated() {
                    if field == "start" { startIndex = index }
                    if field == "end" { endIndex = index }
                    if field == "text" { textIndex = index }
                }
                continue
            }
            guard trimmed.lowercased().hasPrefix("dialogue:") else { continue }
            let payload = trimmed.dropFirst("dialogue:".count)
            let parts = payload.split(separator: ",", maxSplits: max(textIndex, startIndex, endIndex),
                                      omittingEmptySubsequences: false).map(String.init)
            guard parts.count > max(startIndex, endIndex, textIndex) else { continue }
            guard let start = parseASSTime(parts[startIndex]),
                  let end = parseASSTime(parts[endIndex]) else { continue }
            let body = cleanASSText(parts[textIndex])
            guard !body.isEmpty, end > start else { continue }
            cues.append(SubtitleCue(id: cues.count, start: start, end: end, text: body))
        }
        return cues
    }

    /// ASS 时间形如 `0:01:23.45`（百分秒）。
    private static func parseASSTime(_ raw: String) -> Double? {
        let value = raw.trimmingCharacters(in: .whitespaces)
        let pieces = value.split(separator: ":")
        guard pieces.count == 3 else { return nil }
        guard let hours = Double(pieces[0]),
              let minutes = Double(pieces[1]),
              let seconds = Double(pieces[2]) else { return nil }
        return hours * 3600 + minutes * 60 + seconds
    }

    /// 去掉 `{\pos(...)}` 这类覆盖标签，还原换行。
    private static func cleanASSText(_ raw: String) -> String {
        var text = raw.replacingOccurrences(of: #"\{[^}]*\}"#, with: "",
                                            options: .regularExpression)
        text = text.replacingOccurrences(of: "\\N", with: "\n")
            .replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\\h", with: " ")
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// SRT/VTT 里偶尔混 `<i>`、`{\an8}`，一并清掉。
    static func cleanMarkup(_ raw: String) -> String {
        var text = raw.replacingOccurrences(of: #"<[^>]+>"#, with: "",
                                            options: .regularExpression)
        text = text.replacingOccurrences(of: #"\{[^}]*\}"#, with: "",
                                         options: .regularExpression)
        text = text.replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: 自动寻找同名字幕

    /// 本地视频旁边的同名字幕（`.srt` / `.ass` / `.vtt` / `.ssa`），
    /// 以及 `Subs/` 目录下同名前缀的字幕。
    static func sidecarURL(for videoURL: URL) -> URL? {
        let manager = FileManager.default
        let directory = videoURL.deletingLastPathComponent()
        let base = videoURL.deletingPathExtension().lastPathComponent
        let candidates = ["srt", "ass", "ssa", "vtt"]
        for ext in candidates {
            let url = directory.appendingPathComponent(base).appendingPathExtension(ext)
            if manager.fileExists(atPath: url.path) { return url }
        }
        // 语言后缀：xxx.zh.srt / xxx.chs.ass
        if let items = try? manager.contentsOfDirectory(at: directory,
                                                        includingPropertiesForKeys: nil) {
            for item in items where candidates.contains(item.pathExtension.lowercased()) {
                if item.deletingPathExtension().lastPathComponent.hasPrefix(base) {
                    return item
                }
            }
        }
        let subs = directory.appendingPathComponent("Subs", isDirectory: true)
        if let items = try? manager.contentsOfDirectory(at: subs,
                                                        includingPropertiesForKeys: nil) {
            for item in items where candidates.contains(item.pathExtension.lowercased()) {
                if item.lastPathComponent.lowercased().contains(base.lowercased()) {
                    return item
                }
            }
        }
        return nil
    }
}
