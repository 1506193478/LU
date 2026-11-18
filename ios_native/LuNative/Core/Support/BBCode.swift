import SwiftUI
import UIKit

/// Bangumi 简介与评论里的 BBCode 渲染。
///
/// Flutter 侧用 antlr4 生成的 BBCode 词法/语法分析器（`lib/bbcode/generated`），
/// antlr 运行时无法直接搬到 Swift，这里按同一套标记做手写递归扫描，
/// 输出 `AttributedString` 交给 SwiftUI 的 `Text` 渲染。
/// 覆盖常用标签：b/i/u/s/del、color、size、url、img、quote、code、center、mask。
enum LuBBCode {

    private struct Style {
        var bold = false
        var italic = false
        var underline = false
        var strike = false
        var color: Color?
        var size: CGFloat?
        var link: URL?
    }

    private struct Segment {
        var text: String
        var style: Style
    }

    static func render(_ raw: String,
                       fontSize: CGFloat = 14,
                       color: Color = LuTheme.secondary) -> AttributedString {
        let prepared = replaceImages(raw)
        var output = AttributedString()
        for segment in segments(from: prepared) {
            var piece = AttributedString(segment.text)
            var font = Font.system(size: segment.style.size ?? fontSize,
                                   weight: segment.style.bold ? .semibold : .regular)
            if segment.style.italic { font = font.italic() }
            piece.font = font
            piece.foregroundColor = segment.style.color ?? color
            if segment.style.strike {
                piece.inlinePresentationIntent = .strikethrough
            }
            if let link = segment.style.link { piece.link = link }
            output += piece
        }
        return output
    }

    // MARK: - 预处理

    private static func replaceImages(_ raw: String) -> String {
        guard raw.contains("[img") else { return raw }
        guard let regex = try? NSRegularExpression(pattern: #"\[img[^\]]*\].*?\[/img\]"#,
                                                   options: [.caseInsensitive, .dotMatchesLineSeparators])
        else { return raw }
        let range = NSRange(raw.startIndex..., in: raw)
        return regex.stringByReplacingMatches(in: raw, range: range, withTemplate: "［图片］")
    }

    // MARK: - 扫描

    private static func segments(from raw: String) -> [Segment] {
        var result: [Segment] = []
        var style = Style()
        var stack: [Style] = []
        var buffer = ""

        func flush() {
            guard !buffer.isEmpty else { return }
            result.append(Segment(text: buffer, style: style))
            buffer = ""
        }

        var index = raw.startIndex
        while index < raw.endIndex {
            let char = raw[index]
            if char == "[", let close = raw[index...].firstIndex(of: "]") {
                let token = String(raw[raw.index(after: index)..<close])
                // 单标签（如 [br]）与成对标签都在这里处理
                if let outcome = apply(token: token, style: &style, stack: &stack) {
                    flush()
                    if outcome.insertsNewline { result.append(Segment(text: "\n", style: style)) }
                    index = raw.index(after: close)
                    continue
                }
            }
            buffer.append(char)
            index = raw.index(after: index)
        }
        flush()
        return result
    }

    private struct Outcome {
        var insertsNewline = false
    }

    /// 返回 nil 表示不认识这个标签，按原文保留。
    private static func apply(token: String,
                              style: inout Style,
                              stack: inout [Style]) -> Outcome? {
        guard !token.isEmpty else { return nil }
        var body = token
        let isClosing = body.hasPrefix("/")
        if isClosing { body.removeFirst() }

        var name = body
        var value = ""
        if let eq = body.firstIndex(of: "=") {
            name = String(body[body.startIndex..<eq])
            value = String(body[body.index(after: eq)...])
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
        }
        name = name.lowercased()

        switch name {
        case "b":
            if isClosing { pop(&style, &stack) } else { push(style, &stack); style.bold = true }
        case "i":
            if isClosing { pop(&style, &stack) } else { push(style, &stack); style.italic = true }
        case "u":
            if isClosing { pop(&style, &stack) } else { push(style, &stack); style.underline = true }
        case "s", "del", "strike":
            if isClosing { pop(&style, &stack) } else { push(style, &stack); style.strike = true }
        case "color":
            if isClosing {
                pop(&style, &stack)
            } else {
                push(style, &stack)
                style.color = color(from: value)
            }
        case "size":
            if isClosing {
                pop(&style, &stack)
            } else {
                push(style, &stack)
                if let size = Double(value) {
                    style.size = CGFloat(min(max(size, 9), 30))
                }
            }
        case "url":
            if isClosing {
                pop(&style, &stack)
            } else {
                push(style, &stack)
                if let url = URL(string: value), !value.isEmpty { style.link = url }
            }
        case "quote", "code", "center", "mask", "spoiler":
            if isClosing {
                pop(&style, &stack)
            } else {
                push(style, &stack)
                style.color = style.color ?? LuTheme.tertiary
            }
        case "br":
            return Outcome(insertsNewline: true)
        default:
            return nil
        }
        return Outcome()
    }

    private static func push(_ style: Style, _ stack: inout [Style]) {
        stack.append(style)
        if stack.count > 24 { stack.removeFirst() }   // 防御畸形嵌套
    }

    private static func pop(_ style: inout Style, _ stack: inout [Style]) {
        if let previous = stack.popLast() { style = previous }
    }

    // MARK: - 颜色

    private static func color(from raw: String) -> Color? {
        let value = raw.trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty else { return nil }
        if value.hasPrefix("#") {
            var hex = String(value.dropFirst())
            if hex.count == 3 {
                hex = hex.map { "\($0)\($0)" }.joined()
            }
            guard hex.count == 6, let number = Int(hex, radix: 16) else { return nil }
            return Color(red: Double((number >> 16) & 0xFF) / 255,
                         green: Double((number >> 8) & 0xFF) / 255,
                         blue: Double(number & 0xFF) / 255)
        }
        let named: [String: Color] = [
            "red": .red, "blue": .blue, "green": .green, "orange": .orange,
            "purple": .purple, "pink": .pink, "yellow": .yellow,
            "gray": .gray, "grey": .gray, "black": .black, "white": .white
        ]
        return named[value.lowercased()]
    }
}
