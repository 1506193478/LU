import Foundation
import libxml2

/// 系统自带 libxml2 的薄封装。
///
/// 之前用 Foundation 的 `XMLDocument`，但 Xcode 26 起显式模块构建不再把
/// libxml2 的 Swift 绑定随 Foundation 暴露（`FoundationXML` 是 Linux 独有模块，
/// iOS SDK 里根本没有），所以直接走 C API。
///
/// 内存策略：文档指针由本类持有、deinit 时 `xmlFreeDoc`；
/// 取文本一律遍历节点树读 `content`（归文档所有，不需要 xmlFree），
/// 全程不触碰 `xmlFree` 全局函数指针，避免 Swift 侧导入不确定性。
///
/// 节点指针只在文档存活期间有效——调用方在同一作用域内用完即可。
final class LuXMLDocument {

    final class Node {
        let document: LuXMLDocument
        let pointer: UnsafeMutablePointer<xmlNode>

        init(document: LuXMLDocument, pointer: UnsafeMutablePointer<xmlNode>) {
            self.document = document
            self.pointer = pointer
        }

        /// 节点的可见文本（递归收集 text / CDATA）。
        var stringValue: String? {
            let text = Self.collectText(pointer)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text
        }

        /// 相对当前节点的 XPath（支持 `./*[local-name()='xxx']` 这类写法）。
        func nodes(_ expression: String) -> [Node] {
            document.evaluate(expression, contextNode: pointer, owner: self)
        }

        func string(_ expression: String) -> String? {
            nodes(expression).first?.stringValue
        }

        /// 按名字取属性值（遍历 properties 链，不产生需要释放的内存）。
        func attribute(_ name: String) -> String? {
            var attr = pointer.pointee.properties
            while let current = attr {
                if let raw = current.pointee.name,
                   String(cString: charPointer(raw)) == name {
                    let value = Self.collectText(current)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    return value.isEmpty ? nil : value
                }
                attr = current.pointee.next
            }
            return nil
        }

        // MARK: 文本收集

        private static func collectText(_ start: UnsafeMutablePointer<xmlNode>) -> String {
            var result = ""
            var cursor = start.pointee.children
            while let current = cursor {
                let kind = current.pointee.type.rawValue
                // XML_TEXT_NODE = 3, XML_CDATA_SECTION_NODE = 4
                if kind == 3 || kind == 4 {
                    if let content = current.pointee.content {
                        result += String(cString: charPointer(content))
                    }
                } else if kind == 1 {
                    // XML_ELEMENT_NODE：递归收集
                    result += collectText(current)
                }
                cursor = current.pointee.next
            }
            return result
        }

        private static func charPointer(_ raw: UnsafePointer<xmlChar>) -> UnsafePointer<CChar> {
            UnsafeRawPointer(raw).assumingMemoryBound(to: CChar.self)
        }
    }

    private let doc: UnsafeMutablePointer<xmlDoc>
    /// 文档根元素；XHTML 里可能是 <html>，纯 XML 里是最外层节点
    let root: Node?

    init?(data: Data, isHTML: Bool = true) {
        xmlInitParser()
        let bytes = [UInt8](data)
        let size = Int32(data.count)
        var doc: UnsafeMutablePointer<xmlDoc>?
        bytes.withUnsafeBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return }
            if isHTML {
                // HTML_PARSE_RECOVER | NOERROR | NOWARNING | NONET
                let options: Int32 = (1 << 0) | (1 << 5) | (1 << 6) | (1 << 11)
                doc = htmlReadMemory(base, size, nil, nil, options)
            } else {
                // XML_PARSE_RECOVER | NOERROR | NOWARNING | NONET
                let options: Int32 = (1 << 0) | (1 << 5) | (1 << 6) | (1 << 11)
                doc = xmlReadMemory(base, size, nil, nil, options)
            }
        }
        guard let doc else { return nil }
        self.doc = doc
        if let rootElement = xmlDocGetRootElement(doc) {
            root = Node(document: self, pointer: rootElement)
        } else {
            root = nil
        }
    }

    deinit {
        xmlFreeDoc(doc)
    }

    /// 从文档级上下文执行 XPath（`//xxx` / `/xxx` 都可用）。
    func nodes(_ expression: String) -> [Node] {
        evaluate(expression, contextNode: nil, owner: self)
    }

    // MARK: 内部

    private func evaluate(_ expression: String,
                          contextNode: UnsafeMutablePointer<xmlNode>?,
                          owner: Node) -> [Node] {
        let context = xmlXPathNewContext(doc)
        defer { xmlXPathFreeContext(context) }
        if let contextNode {
            context.pointee.node = contextNode
        }
        guard let object = xmlXPathEvalExpression(expression, context) else { return [] }
        defer { xmlXPathFreeObject(object) }

        guard let nodeSet = object.pointee.nodesetval,
              nodeSet.pointee.nodeNr > 0,
              let table = nodeSet.pointee.nodeTab else { return [] }

        var result: [Node] = []
        for index in 0..<Int(nodeSet.pointee.nodeNr) {
            if let node = table[index] {
                result.append(Node(document: self, pointer: node))
            }
        }
        return result
    }
}
