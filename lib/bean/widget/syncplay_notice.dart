import 'package:flutter/material.dart';

import 'package:XL/bean/widget/clay.dart';

/// 一起看房间里的系统提示：进房 / 离房 / 开始播放。
///
/// 做成一条居中的小胶囊，不跟正文聊天气泡抢注意力。颜色跟主题走：
/// 进房用强调色，离房用中性灰；用户换了主色，这条提示一起变。
class SyncPlayNotice extends StatelessWidget {
  const SyncPlayNotice({
    super.key,
    required this.text,
    this.highlight = false,
  });

  final String text;

  /// 暖色（强调色）底：用于「想你啦~」这类正向事件。
  final bool highlight;

  /// 系统消息里只有进房那条是暖色的，文案在 controller 里统一生成。
  static bool isJoin(String text) => text.endsWith('想你啦~');

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool darkMode = theme.brightness == Brightness.dark;
    final ColorScheme scheme = theme.colorScheme;
    final ClayToneColors accent = ClayToneColors.of(context, ClayTone.accent);

    final Color background = highlight
        ? (darkMode
            ? accent.dark.withValues(alpha: 0.26)
            // 浅色模式用"染色面"而不是半透明强调色：正文色压上去还够黑。
            : accent.tintSurface(context))
        : scheme.surfaceContainerHigh.withValues(alpha: darkMode ? 0.55 : 0.9);
    final Color foreground = highlight
        // 深色模式强调色粘土是浅紫，配浅紫字；浅色模式的粘土同样是浅紫，
        // 文字必须换成够饱和的那一支，否则白底浅紫字等于没写。
        ? (darkMode ? accent.light : accent.strong)
        : scheme.onSurfaceVariant;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 4),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: theme.textTheme.labelSmall?.copyWith(
              color: foreground,
              fontWeight: FontWeight.w500,
              height: 1.25,
            ),
          ),
        ),
      ),
    );
  }
}
