import Foundation

/// 全局 UA。Bangumi 与多数图床会拒绝空 UA 的请求，
/// 对照 Flutter 侧的 `http_headers.dart`。
enum LuUserAgent {
    static let value = "LU/5.0.0 (iOS) (like Kazumi)"
}
