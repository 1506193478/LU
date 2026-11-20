import 'package:flutter/material.dart';

import 'package:XL/navigation.dart';
import 'package:XL/services/storage/settings_keys.dart';
import 'package:XL/services/storage/storage.dart';
import 'package:XL/utils/device.dart';
import 'package:XL/utils/motion.dart';

/// 全局边缘返回手势。
///
/// - `right`（默认）：iOS 式从左边缘右滑返回——Cupertino 转场已自带
///   跟手手势，这一层只兜非 Cupertino 转场的页面。
/// - `left`：从右边缘向左拖返回（用户可选的方向）。
/// - `off`：关闭。
///
/// 拖动超过阈值直接 pop，配一次触感；路由转场动画负责视觉收尾。
/// 手势层包在根 builder（Material 外），不影响任何页面布局。
class EdgeBackGestureArea extends StatefulWidget {
  const EdgeBackGestureArea({super.key, required this.child});

  final Widget child;

  @override
  State<EdgeBackGestureArea> createState() => _EdgeBackGestureAreaState();
}

class _EdgeBackGestureAreaState extends State<EdgeBackGestureArea> {
  Offset? _start;
  bool _triggered = false;
  String _mode = 'right';
  DateTime _modeReadAt = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    _mode = GStorage.getSetting(SettingsKeys.backGesture);
  }

  bool get _enabled => _mode == 'left' || _mode == 'right';

  bool _nearEdge(Offset global) {
    final double w = MediaQuery.sizeOf(context).width;
    if (_mode == 'right') return global.dx < 28;
    return global.dx > w - 28;
  }

  void _down(PointerDownEvent e) {
    // 读 Hive 做节流缓存：每次屏幕触摸都同步读 box 会在滚动中造成微卡。
    final DateTime now = DateTime.now();
    if (now.difference(_modeReadAt).inMilliseconds > 500) {
      _mode = GStorage.getSetting(SettingsKeys.backGesture);
      _modeReadAt = now;
    }
    _triggered = false;
    _start = _enabled && !isDesktop() && _nearEdge(e.position) ? e.position : null;
  }

  void _move(PointerMoveEvent e) {
    if (_start == null || _triggered) return;
    final double dx = (e.position.dx - _start!.dx).abs();
    final double dy = (e.position.dy - _start!.dy).abs();
    // 必须横向为主；纵向为主视为页面滚动。
    if (dy > dx && dy > 24) {
      _start = null;
      return;
    }
    if (dx > 72 && dx > dy * 1.6) {
      _triggered = true;
      _start = null;
      KazumiHaptics.heavy();
      final navigator = rootNavigatorKey.currentState;
      if (navigator != null && navigator.canPop()) {
        navigator.maybePop();
      }
    }
  }

  void _up(PointerEvent _) => _start = null;

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: _down,
      onPointerMove: _move,
      onPointerUp: _up,
      onPointerCancel: _up,
      behavior: HitTestBehavior.translucent,
      child: widget.child,
    );
  }
}
