import 'package:flutter/material.dart';

import 'package:XL/utils/motion.dart';

/// 按下时轻微缩小、松手回弹的包装层。
///
/// 素材卡片、按钮、列表项都用它，保证"按下去有反应"这件事在全 App 里
/// 是同一个手感：按下 90ms 收紧到 0.96，松手 240ms 带一点过冲弹回。
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.pressedScale = 0.96,
    this.haptic = true,
    this.borderRadius,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// 按下时的缩放比例。大块区域用 0.98，小按钮用 0.94 更有弹性。
  final double pressedScale;

  /// 是否在按下时给一次轻震动。
  final bool haptic;

  /// 只用于裁剪水波纹，不影响缩放。
  final BorderRadius? borderRadius;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  void _handleTapDown(TapDownDetails _) => _setPressed(true);

  void _handleTapCancel() => _setPressed(false);

  void _handleTap() {
    _setPressed(false);
    if (widget.haptic) KazumiHaptics.tap();
    widget.onTap?.call();
  }

  void _handleLongPress() {
    _setPressed(false);
    if (widget.haptic) KazumiHaptics.success();
    widget.onLongPress?.call();
  }

  @override
  Widget build(BuildContext context) {
    final bool enabled = widget.onTap != null || widget.onLongPress != null;
    final Widget content = AnimatedScale(
      scale: _pressed ? widget.pressedScale : 1.0,
      duration: KazumiMotion.scale(
        context,
        _pressed ? KazumiMotion.instant : KazumiMotion.base,
      ),
      curve: _pressed ? KazumiMotion.emphasized : KazumiMotion.spring,
      child: widget.child,
    );

    if (!enabled) return content;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: _handleTapDown,
      onTapCancel: _handleTapCancel,
      onTapUp: (_) => _setPressed(false),
      onTap: widget.onTap == null ? null : _handleTap,
      onLongPress: widget.onLongPress == null ? null : _handleLongPress,
      child: content,
    );
  }
}
