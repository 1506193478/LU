import 'package:flutter/material.dart';

import 'package:XL/utils/motion.dart';

/// 播放器控制条的统一按压图标按钮。
///
/// 按下缩到 0.88（100ms easeOut），松手弹性回弹（350ms elasticOut），
/// 并给一次轻触感——反馈对齐 impeccable 的 100–150ms 即时档。
/// 参数与 [IconButton] 对齐，可以逐个替换；[Listener] 只旁观指针，
/// 不参与手势仲裁，不会抢上下层的手势。
class PlayerIconButton extends StatefulWidget {
  const PlayerIconButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.tooltip,
    this.color,
    this.iconSize,
    this.haptic = true,
  });

  final Widget icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final Color? color;
  final double? iconSize;

  /// 纯展示切换（如音量条）可关掉触感。
  final bool haptic;

  @override
  State<PlayerIconButton> createState() => _PlayerIconButtonState();
}

class _PlayerIconButtonState extends State<PlayerIconButton> {
  double _scale = 1;

  void _down(PointerEvent _) {
    if (widget.onPressed == null) return;
    if (widget.haptic) KazumiHaptics.tap();
    setState(() => _scale = 0.88);
  }

  void _up(PointerEvent _) {
    if (_scale == 1) return;
    setState(() => _scale = 1);
  }

  @override
  Widget build(BuildContext context) {
    final button = IconButton(
      onPressed: widget.onPressed,
      icon: widget.icon,
      color: widget.color,
      iconSize: widget.iconSize,
      tooltip: widget.tooltip,
      // 缩放反馈已经足够，关掉水波纹避免两层动画打架
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
    );
    return Listener(
      onPointerDown: _down,
      onPointerUp: _up,
      onPointerCancel: _up,
      child: AnimatedScale(
        scale: _scale,
        duration: _scale < 1
            ? const Duration(milliseconds: 100)
            : const Duration(milliseconds: 350),
        curve: _scale < 1 ? Curves.easeOut : Curves.elasticOut,
        child: button,
      ),
    );
  }
}
