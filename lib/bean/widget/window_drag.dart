import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'package:XL/utils/device.dart';

/// 让一块区域“可以拖着走窗口”。
///
/// 无边框窗口（`DesktopWindowConfig.frameless`）去掉系统标题栏之后，只有
/// `WindowShell` 顶端那 8px 能拖——鼠标很难压准，用户的原话是「窗口挪动很
/// 不方便」。`SysAppBar` 自己有一套 Listener 拖动逻辑，但「我的」、Emby 首页
/// 这类页面用的是页内大标题（[PvPageHead]），根本没有标题栏可抓。
///
/// 这个组件把那套逻辑抽出来，套在任意标题区上：
///   * 用 [Listener] 而不是 GestureDetector：不参与手势竞技场，页面里的
///     滚动、点击、InkWell 都照常工作，只有位移超过阈值才进拖动循环；
///   * 双击回到上一状态（最大化 ↔ 还原），跟系统标题栏一致；
///   * 只在桌面 + 无边框时生效，移动端/有系统标题栏时完全不拦截。
class WindowDragRegion extends StatefulWidget {
  const WindowDragRegion({
    super.key,
    required this.child,
    this.enabled = true,
  });

  final Widget child;

  /// 想在某处禁用（比如全屏播放器）时传 false。
  final bool enabled;

  bool get _active => enabled && isDesktop();

  @override
  State<WindowDragRegion> createState() => _WindowDragRegionState();
}

class _WindowDragRegionState extends State<WindowDragRegion> {
  Offset? _start;
  bool _dragging = false;

  /// 位移超过这个值才认作“拖窗口”。太小会把点击误判成拖动，
  /// 太大又显得窗口“粘手”。
  static const double _threshold = 5;

  void _down(PointerDownEvent event) {
    _start = event.position;
    _dragging = false;
  }

  void _move(PointerMoveEvent event) {
    final start = _start;
    if (_dragging || start == null) return;
    if ((event.position - start).distance < _threshold) return;
    _dragging = true;
    windowManager.startDragging();
  }

  void _end() {
    _start = null;
    _dragging = false;
  }

  @override
  Widget build(BuildContext context) {
    if (!widget._active) return widget.child;
    // 这里刻意不用 GestureDetector 做双击最大化：手势识别器会把单击
    // 拖到 ~300ms 的双击判定窗口里，标题栏上的按钮会明显“变迟钝”。
    // 拖动用 Listener 就够了，双击最大化交给 `WindowShell` 顶部那一条。
    return Listener(
      onPointerDown: _down,
      onPointerMove: _move,
      onPointerUp: (_) => _end(),
      onPointerCancel: (_) => _end(),
      child: widget.child,
    );
  }
}
