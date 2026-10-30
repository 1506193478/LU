import 'package:flutter/material.dart';

import 'package:XL/bean/widget/clay.dart';
import 'package:XL/utils/motion.dart';

enum ExitDialogAction { exit, minimizeToTray }

class ExitDialogResult {
  const ExitDialogResult({
    required this.action,
    required this.rememberChoice,
  });

  final ExitDialogAction action;
  final bool rememberChoice;
}

/// 关闭窗口时的选择框。
///
/// 和设置页同一套粘土材质：两个选项是两块粘土砖，选中的那块换成强调色，
/// 右下角是粘土勾。底部动作区固定横排，两个按钮各占一半。
class ExitConfirmationDialog extends StatefulWidget {
  const ExitConfirmationDialog({super.key});

  @override
  State<ExitConfirmationDialog> createState() => _ExitConfirmationDialogState();
}

class _ExitConfirmationDialogState extends State<ExitConfirmationDialog> {
  ExitDialogAction _action = ExitDialogAction.minimizeToTray;
  bool _rememberChoice = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Dialog(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: ClayPanel(
          radius: 28,
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: ClayIconBadge(
                  icon: Icons.exit_to_app_rounded,
                  size: 54,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                '关闭 LU？',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '选择关闭窗口后的操作',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 18),
              _buildOption(ExitDialogAction.minimizeToTray),
              const SizedBox(height: 8),
              _buildOption(ExitDialogAction.exit),
              const SizedBox(height: 6),
              _buildRememberRow(theme, colors),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: ClayButton(
                      tone: ClayTone.subtle,
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('取消'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ClayButton(
                      tone: _action == ExitDialogAction.exit
                          ? ClayTone.danger
                          : ClayTone.accent,
                      onPressed: () => Navigator.of(context).pop(
                        ExitDialogResult(
                          action: _action,
                          rememberChoice: _rememberChoice,
                        ),
                      ),
                      child: Text(
                        switch (_action) {
                          ExitDialogAction.minimizeToTray => '最小化至托盘',
                          ExitDialogAction.exit => '退出',
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRememberRow(ThemeData theme, ColorScheme colors) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        KazumiHaptics.select();
        setState(() => _rememberChoice = !_rememberChoice);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        child: Row(
          children: [
            ClayCheck(value: _rememberChoice, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Text('记住我的选择', style: theme.textTheme.bodyMedium),
            ),
            Text(
              '下次不再询问',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOption(ExitDialogAction action) {
    final ThemeData theme = Theme.of(context);
    final bool selected = _action == action;
    final (IconData icon, String title, String description) = switch (action) {
      ExitDialogAction.minimizeToTray => (
          Icons.minimize_rounded,
          '最小化至托盘',
          '隐藏窗口，继续在后台运行',
        ),
      ExitDialogAction.exit => (
          Icons.power_settings_new_rounded,
          '退出 LU',
          '结束运行并关闭应用',
        ),
    };
    final Color foreground = selected
        ? ClayToneColors.of(context, ClayTone.accent).fg
        : theme.colorScheme.onSurface;

    return Semantics(
      selected: selected,
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (selected) return;
          KazumiHaptics.select();
          setState(() => _action = action);
        },
        child: ClayPanel(
          radius: 18,
          depth: 0,
          tone: selected ? ClayTone.accent : ClayTone.subtle,
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Row(
            children: [
              Icon(icon, size: 22, color: foreground),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: foreground,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      description,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: selected
                            ? foreground.withValues(alpha: 0.72)
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              ClayCheck(value: selected, size: 22),
            ],
          ),
        ),
      ),
    );
  }
}
