import 'package:flutter/material.dart';

import 'package:XL/bean/widget/clay_neu.dart';

/// 拟态对话框。
///
/// 和 [ClayDialog]（粘土）是同一套结构、两种材质：粘土靠渐变做体积，拟态靠
/// 「底色 + 双向阴影 + 1px 硬描边」。桌面端和现在的整体界面都是拟态，所以
/// 更新提示这类「系统级」弹窗走这套，跟页面观感一致。
class NeuDialog extends StatelessWidget {
  const NeuDialog({
    super.key,
    required this.title,
    this.message,
    this.content,
    this.icon,
    this.actions = const <Widget>[],
    this.maxWidth = 440,
    this.scrollable = false,
  });

  final String title;
  final String? message;
  final Widget? content;
  final IconData? icon;
  final List<Widget> actions;
  final double maxWidth;

  /// 内容比屏幕高时打开：标题以下可滚动，动作区钉在底部。
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;

    final Widget body = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (icon != null) ...[
          Center(
            child: NeuSurface(
              mode: NeuMode.recess,
              radius: 18,
              width: 56,
              height: 56,
              child: Center(
                child: Icon(icon, size: 26, color: colors.primary),
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
        Text(
          title,
          textAlign: TextAlign.center,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w600,
            color: colors.onSurface,
          ),
        ),
        if (message != null) ...[
          const SizedBox(height: 8),
          Text(
            message!,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.onSurfaceVariant,
              height: 1.5,
            ),
          ),
        ],
        if (content != null) ...[
          const SizedBox(height: 18),
          content!,
        ],
      ],
    );

    return Dialog(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: NeuSurface(
          radius: 26,
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              if (scrollable)
                Flexible(child: SingleChildScrollView(child: body))
              else
                body,
              if (actions.isNotEmpty) ...[
                const SizedBox(height: 20),
                Row(
                  children: <Widget>[
                    for (int i = 0; i < actions.length; i++) ...[
                      if (i > 0) const SizedBox(width: 10),
                      Expanded(child: actions[i]),
                    ],
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 拟态对话框里的按钮：凸起面板 + 文字，按下去由 [NeuSurface] 自己接管手势。
class NeuDialogButton extends StatelessWidget {
  const NeuDialogButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.primary = false,
    this.danger = false,
    this.height = 46,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool primary;
  final bool danger;
  final double height;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    final Color foreground = onPressed == null
        ? colors.onSurfaceVariant.withValues(alpha: 0.5)
        : danger
            ? colors.error
            : primary
                ? colors.primary
                : colors.onSurface;

    return Opacity(
      opacity: onPressed == null ? 0.6 : 1,
      child: NeuSurface(
        radius: 14,
        height: height,
        onTap: onPressed,
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (icon != null) ...[
                Icon(icon, size: 17, color: foreground),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: foreground,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
