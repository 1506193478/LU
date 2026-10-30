import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'package:XL/services/platform/desktop_window_config.dart';

/// 无边框窗口的外壳。
///
/// 窗口本身是透明的（`main.dart` 里设了 `backgroundColor: transparent` +
/// `setAsFrameless()`），这里负责三件事：
///
/// 1. 把内容裁成 26px 圆角，四周留 8px 透明边距——这层边距就是"窗口浮在桌面上"
///    的那圈空隙；
/// 2. 在边距里铺八向缩放热区。frameless 之后系统不再给隐形边框，
///    不自己接管的话窗口就只能最大化、不能拖大小；
/// 3. 最大化 / 全屏时把边距和圆角收掉，避免内容被裁。
class WindowShell extends StatefulWidget {
  const WindowShell({super.key, required this.child});

  final Widget child;

  /// 只有 Windows 且设置里开着才启用。
  static bool get supported => DesktopWindowConfig.frameless;

  /// 四周的透明边距，同时也是缩放热区宽度。
  static const double gutter = 8;

  /// 窗口圆角。跟预览里调的 26 一致。
  static const double radius = 26;

  @override
  State<WindowShell> createState() => _WindowShellState();
}

class _WindowShellState extends State<WindowShell> with WindowListener {
  bool _maximized = false;
  bool _fullScreen = false;

  @override
  void initState() {
    super.initState();
    if (!WindowShell.supported) return;
    windowManager.addListener(this);
    _syncWindowState();
  }

  @override
  void dispose() {
    if (WindowShell.supported) windowManager.removeListener(this);
    super.dispose();
  }

  Future<void> _syncWindowState() async {
    try {
      final bool maximized = await windowManager.isMaximized();
      final bool fullScreen = await windowManager.isFullScreen();
      if (!mounted) return;
      setState(() {
        _maximized = maximized;
        _fullScreen = fullScreen;
      });
    } catch (_) {
      // 读不到就按窗口化处理，最坏是多留一圈边距。
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

  @override
  void onWindowEnterFullScreen() {
    if (mounted) setState(() => _fullScreen = true);
  }

  @override
  void onWindowLeaveFullScreen() {
    if (mounted) setState(() => _fullScreen = false);
  }

  @override
  Widget build(BuildContext context) {
    if (!WindowShell.supported) return widget.child;

    final bool flush = _maximized || _fullScreen;
    final Color backdrop = Theme.of(context).scaffoldBackgroundColor;

    return Stack(
      children: [
        Positioned.fill(
          child: Padding(
            padding: EdgeInsets.all(flush ? 0 : WindowShell.gutter),
            child: ClipRRect(
              borderRadius:
                  BorderRadius.circular(flush ? 0 : WindowShell.radius),
              child: ColoredBox(color: backdrop, child: widget.child),
            ),
          ),
        ),
        if (!flush) ..._resizeZones(),
      ],
    );
  }

  List<Widget> _resizeZones() {
    const double g = WindowShell.gutter;
    const double corner = 18;

    Widget zone({
      required ResizeEdge edge,
      required MouseCursor cursor,
      double? left,
      double? top,
      double? right,
      double? bottom,
      double? width,
      double? height,
      VoidCallback? onDoubleTap,
    }) {
      return Positioned(
        left: left,
        top: top,
        right: right,
        bottom: bottom,
        width: width,
        height: height,
        child: MouseRegion(
          cursor: cursor,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: (_) => windowManager.startResizing(edge),
            onDoubleTap: onDoubleTap,
          ),
        ),
      );
    }

    Future<void> toggleMaximize() async {
      try {
        if (await windowManager.isMaximized()) {
          await windowManager.unmaximize();
        } else {
          await windowManager.maximize();
        }
      } catch (_) {
        // 不支持就算了，右上角还有按钮。
      }
    }

    return <Widget>[
      // 四条边
      zone(
        edge: ResizeEdge.top,
        cursor: SystemMouseCursors.resizeUpDown,
        left: corner,
        right: corner,
        top: 0,
        height: g,
        // 顶上这 8px 是唯一一条"像标题栏"的空白，双击最大化跟系统行为一致。
        onDoubleTap: toggleMaximize,
      ),
      zone(
        edge: ResizeEdge.bottom,
        cursor: SystemMouseCursors.resizeUpDown,
        left: corner,
        right: corner,
        bottom: 0,
        height: g,
      ),
      zone(
        edge: ResizeEdge.left,
        cursor: SystemMouseCursors.resizeLeftRight,
        left: 0,
        top: corner,
        bottom: corner,
        width: g,
      ),
      zone(
        edge: ResizeEdge.right,
        cursor: SystemMouseCursors.resizeLeftRight,
        right: 0,
        top: corner,
        bottom: corner,
        width: g,
      ),
      // 四个角
      zone(
        edge: ResizeEdge.topLeft,
        cursor: SystemMouseCursors.resizeUpLeftDownRight,
        left: 0,
        top: 0,
        width: corner,
        height: corner,
      ),
      zone(
        edge: ResizeEdge.topRight,
        cursor: SystemMouseCursors.resizeUpRightDownLeft,
        right: 0,
        top: 0,
        width: corner,
        height: corner,
      ),
      zone(
        edge: ResizeEdge.bottomLeft,
        cursor: SystemMouseCursors.resizeUpRightDownLeft,
        left: 0,
        bottom: 0,
        width: corner,
        height: corner,
      ),
      zone(
        edge: ResizeEdge.bottomRight,
        cursor: SystemMouseCursors.resizeUpLeftDownRight,
        right: 0,
        bottom: 0,
        width: corner,
        height: corner,
      ),
    ];
  }
}
