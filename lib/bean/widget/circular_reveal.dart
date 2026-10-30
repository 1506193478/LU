import 'dart:math' as math;

import 'package:flutter/material.dart';


/// 圆形扩散遮罩：从 [origin] 长出一个圆，铺满整屏。
///
/// 用法：放在页面最外层 `Stack` 的顶层。要转场时把 [origin] 设成按钮中心，
/// 等动画走完再 push 新页面——新页面底色与遮罩同色，看起来就是这个圆扩散
/// 成了整页。
///
/// **为什么不用 `PageRouteBuilder` 做整页裁剪**：那样会把页面包进
/// Transform/Clip，之前实测 `NestedScrollView` + `SliverAppBar` 在这套结构下
/// 会算错折叠状态，详情页头图直接消失。放在页面自己的 Stack 里最稳。
class CircularRevealOverlay extends StatefulWidget {
  const CircularRevealOverlay({
    super.key,
    this.origin,
    this.color = const Color(0xFF000000),
  });

  /// 扩散圆心（全局坐标）；null 表示不显示。
  final Offset? origin;
  final Color color;

  @override
  State<CircularRevealOverlay> createState() => _CircularRevealOverlayState();
}

class _CircularRevealOverlayState extends State<CircularRevealOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );

  Offset? _center;

  @override
  void didUpdateWidget(CircularRevealOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = widget.origin;
    if (next != null && _center == null) {
      _center = next;
      _controller.forward(from: 0);
    } else if (next == null && _center != null) {
      // 从下一页返回时立刻收掉，不留一帧黑屏。
      _controller.stop();
      setState(() => _center = null);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final center = _center;
    if (center == null) return const SizedBox.shrink();
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return CustomPaint(
            size: Size.infinite,
            painter: _CircleRevealPainter(
              center: center,
              progress: _controller.value,
              color: widget.color,
            ),
          );
        },
      ),
    );
  }
}

class _CircleRevealPainter extends CustomPainter {
  const _CircleRevealPainter({
    required this.center,
    required this.progress,
    required this.color,
  });

  final Offset center;
  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    // 半径取圆心到最远角的距离，保证铺满。
    final double dx = math.max(center.dx, size.width - center.dx);
    final double dy = math.max(center.dy, size.height - center.dy);
    final double maxRadius = math.sqrt(dx * dx + dy * dy);
    final double radius = maxRadius * progress;
    if (radius <= 0) return;
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = color
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(_CircleRevealPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.center != center ||
      oldDelegate.color != color;
}

/// 触发一次圆形扩散：返回扩散动画走完所需的等待时长。
const Duration kCircularRevealDuration = Duration(milliseconds: 440);

/// 从某个 widget 的 Key 取它中心的全局坐标，用作扩散圆心。
Offset? revealOriginOf(GlobalKey key) {
  final context = key.currentContext;
  if (context == null) return null;
  final object = context.findRenderObject();
  if (object is! RenderBox || !object.attached) return null;
  return object.localToGlobal(object.size.center(Offset.zero));
}
