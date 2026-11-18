import SwiftUI
import UIKit

/// 设计令牌。对照 Flutter 侧 `lib/theme` 与 HIG 度量（17pt 行标题 / 13pt 标签 /
/// 0.5pt 发丝线 / 12pt 圆角 / 44pt 行高），不自行发明数字。
enum LuTheme {

    // MARK: - 颜色

    /// 强调色跟随设置（见 `LuAccent`）。RootView 用 `.id(accent)` 强制重建配色。
    static var accent: Color {
        (LuAccent(rawValue: AppSettings.shared.accent) ?? .blue).color
    }

    static let label = Color(uiColor: .label)
    static let secondary = Color(uiColor: .secondaryLabel)
    static let tertiary = Color(uiColor: .tertiaryLabel)

    /// 发丝线：浅色 0.5pt 黑 12%，深色 0.5pt 白 16%。
    static let hairline = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(white: 1, alpha: 0.16)
            : UIColor(white: 0, alpha: 0.12)
    })

    static let separator = Color(uiColor: .separator)

    /// 玻璃底衬色（material 之下的染色层）。
    static let glassTint = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(white: 0.11, alpha: 1)
            : UIColor(white: 0.98, alpha: 1)
    })

    /// 页面主背景（背景层最底）。
    static let canvas = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.055, green: 0.060, blue: 0.075, alpha: 1)
            : UIColor(red: 0.957, green: 0.965, blue: 0.980, alpha: 1)
    })

    // MARK: - 度量（对齐 HIG）

    /// 12pt 圆角——卡片与玻璃容器统一值。
    static let cardRadius: CGFloat = 12
    /// 列表行高。
    static let rowHeight: CGFloat = 44
    /// 页面水平安全内边距。
    static let pagePadding: CGFloat = 16
    /// 卡片间距。
    static let cardGap: CGFloat = 12
    /// 底栏高度（不含 Home Indicator）。
    static let tabBarHeight: CGFloat = 50

    // MARK: - 字体

    static func title(_ size: CGFloat = 17) -> Font { .system(size: size, weight: .semibold) }
    static func rowTitle() -> Font { .system(size: 17, weight: .regular) }
    static func caption() -> Font { .system(size: 13, weight: .regular) }
    static func label13() -> Font { .system(size: 13, weight: .semibold) }
    static func mono(_ size: CGFloat = 12) -> Font { .system(size: size, weight: .medium, design: .monospaced) }

    // MARK: - 动画

    /// 全局统一弹性。背景层永不使用。
    static let spring = Animation.spring(response: 0.34, dampingFraction: 0.86)
    static let quick = Animation.easeOut(duration: 0.18)
}

extension View {
    /// 页面级滚动内容内边距，附带底部给自定义底栏留白。
    func luPageInsets() -> some View {
        self.padding(.horizontal, LuTheme.pagePadding)
    }
}
