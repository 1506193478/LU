import 'dart:async';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'package:XL/bean/widget/window_shell.dart';
import 'package:XL/utils/device.dart';

/// 无边框窗口的最小化 / 最大化 / 关闭三连。
///
/// 只在外壳（[WindowShell]）启用时出现——否则系统标题栏已经有这三个按钮了，
/// 再画一遍等于两套控件打架。
class DesktopWindowControls extends StatefulWidget {
  const DesktopWindowControls({super.key, this.foreground});

  /// 播放器那种深色浮层上要传白色。
  final Color? foreground;

  @override
  State<DesktopWindowControls> createState() => _DesktopWindowControlsState();
}

class _DesktopWindowControlsState extends State<DesktopWindowControls>
    with WindowListener {
  bool _maximized = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    unawaited(_sync());
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  Future<void> _sync() async {
    try {
      final bool maximized = await windowManager.isMaximized();
      if (mounted) setState(() => _maximized = maximized);
    } catch (_) {
      // 读不到就按"窗口化"显示，点了会走 maximize 分支。
    }
  }

  @override
  void onWindowMaximize() {
    if (mounted) setState(() => _maximized = true);
  }

  @override
  void onWindowUnmaximize() {
    if (mounted) setState(() => _maximized = false);
  }

  Future<void> _toggleMaximize() async {
    try {
      if (await windowManager.isMaximized()) {
        await windowManager.unmaximize();
      } else {
        await windowManager.maximize();
      }
    } catch (_) {
      // 个别窗口管理器不支持，忽略。
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!isDesktop() || !WindowShell.supported) {
      return const SizedBox.shrink();
    }
    final ColorScheme colors = Theme.of(context).colorScheme;
    final Color foreground = widget.foreground ?? colors.onSurfaceVariant;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _button(
          icon: Icons.remove_rounded,
          tooltip: '最小化',
          foreground: foreground,
          onPressed: () => windowManager.minimize(),
        ),
        _button(
          icon: _maximized
              ? Icons.filter_none_rounded
              : Icons.crop_square_rounded,
          tooltip: _maximized ? '还原' : '最大化',
          foreground: foreground,
          onPressed: _toggleMaximize,
        ),
        _button(
          icon: Icons.close_rounded,
          tooltip: '关闭',
          foreground: foreground,
          hoverColor: colors.error.withValues(alpha: 0.14),
          hoverForeground: colors.error,
          onPressed: () => windowManager.close(),
        ),
      ],
    );
  }

  Widget _button({
    required IconData icon,
    required String tooltip,
    required Color foreground,
    required VoidCallback onPressed,
    Color? hoverColor,
    Color? hoverForeground,
  }) {
    final Color hover = hoverColor ?? foreground.withValues(alpha: 0.10);
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon, size: 15),
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints.tightFor(width: 34, height: 30),
      style: ButtonStyle(
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          if (hoverForeground != null && states.contains(WidgetState.hovered)) {
            return hoverForeground;
          }
          return foreground;
        }),
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.hovered) ||
              states.contains(WidgetState.pressed)) {
            return hover;
          }
          return Colors.transparent;
        }),
        overlayColor: const WidgetStatePropertyAll<Color>(Colors.transparent),
        shape: WidgetStatePropertyAll<OutlinedBorder>(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
        ),
        padding: const WidgetStatePropertyAll<EdgeInsetsGeometry>(
          EdgeInsets.zero,
        ),
      ),
    );
  }
}
