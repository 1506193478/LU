import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'package:XL/services/platform/desktop_window_config.dart';

/// 无边框窗口的外壳。
///
/// 窗口是**不透明**的（`main.dart` 里刻意不再设透明背景）。这里负责三件事：
///
/// 1. 整窗先铺一层实色底，再让内容内缩 [gutter]——这层边距现在是实色的，
///    看上去就是窗口自己的留白，不再是"透出桌面的玻璃边"；
/// 2. 在边距里铺八向缩放热区。frameless 之后系统不再给隐形边框，
///    不自己接管的话窗口就只能最大化、不能拖大小；
/// 3. 最大化 / 全屏时把边距收掉，避免内容被裁。
///
/// 圆角分两层：窗口形状的圆角由 DWM 画（`main.dart` 的
/// `applyWindowRoundCorner`），内容四角的同心弧线在这里用 ClipRRect 裁出。
/// 历史上「透明窗口 + 整窗 ClipRRect」慢是因为透明窗口每帧要跟桌面做
/// alpha 合成；窗口改成不透明后，一层 antiAlias 的路径裁剪不再是大头。
class WindowShell extends StatefulWidget {
  const WindowShell({super.key, required this.child});

  final Widget child;

  /// 只有 Windows 且设置里开着才启用。
  static bool get supported => DesktopWindowConfig.frameless;

  /// 四周留白，同时也是缩放热区宽度。
  ///
  /// 这块**不是透明的**，铺的是主题的 scaffold 底色，所以看起来是窗口自己的
  /// 内边距，而不是"透出桌面的一圈玻璃"。最大化 / 全屏时收成 0。
  static const double gutter = 8;

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
    // scaffoldBackgroundColor 现在按设计是透明的（页面背景由壳层的
    // LuBackdrop 统一画），但这一块要涂满窗口四周的边距，必须是实色，
    // 否则桌面端拖窗口时那圈会闪白/露桌面。
    // 取背景渐变的起始色，和页面接得上。
    final bool shellDark = Theme.of(context).brightness == Brightness.dark;
    final Color backdrop =
        shellDark ? const Color(0xFF0D1017) : const Color(0xFFD6E0FF);

    // 整窗先铺实色底：窗口本身已经不透明了，这块负责把 [gutter] 那圈边距
    // 涂成主题底色，否则那块区域没人绘制，缩放时会闪白。
    // 窗口四角的圆角由 DWM 画（main.dart 的 applyWindowRoundCorner），
    // 内容这层把四角裁出同心弧线——不裁的话直角的内容贴在圆角窗口上，
    // 四个角会露出月牙状的加宽底色。
    // 之前去掉的 ClipRRect 慢在「透明窗口 + 整窗每帧合成」，现在窗口是
    // 不透明的；antiAlias 只是按路径裁剪，不会开 saveLayer，代价可以忽略。
    // 最大化 / 全屏时窗口是方的，圆角和留白一起收掉。
    return ColoredBox(
      color: backdrop,
      child: Stack(
        children: [
          Positioned.fill(
            child: Padding(
              padding: EdgeInsets.all(flush ? 0 : WindowShell.gutter),
              child: flush
                  ? widget.child
                  : ClipRRect(
                      borderRadius:
                          BorderRadius.circular(WindowShell.gutter),
                      child: widget.child,
                    ),
            ),
          ),
          if (!flush) ..._resizeZones(),
        ],
      ),
    );
  }

  List<Widget> _resizeZones() {
    const double g = WindowShell.gutter;
    // 热区比视觉留白宽一截：8px 的边用户在 4K 屏上根本压不准，
    // 伸手进去 2~3px 就滑走，「放大缩小很不方便」就是这儿来的。
    // 多出来的宽度压在内容边缘上，但只有 3px，不影响任何控件。
    const double edge = 11;
    const double corner = 26;

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

    // 顶边留白是整扇窗口里最像「标题栏」的一条，拿它当拖动手柄。
    // 这块区域在内容内缩的边距里，没有任何手势跟它抢竞技场，所以一定
    // 能触发 —— 之前只能靠各页面自带的标题栏拖动，标题栏一旦套在可滚动
    // 容器里，pan 手势就会被滚动抢走，表现为「窗口拖不动」。
    // 双击最大化跟系统行为一致。
    // 顶部这条同时是「拖动条」：高度给到 g + 6，压住内容最上面几像素，
    // 抓起来更像标题栏；双击仍然最大化 / 还原。
    final Widget dragHandle = Positioned(
      left: corner,
      right: corner,
      top: 0,
      height: g + 6,
      child: MouseRegion(
        cursor: SystemMouseCursors.move,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: (_) => windowManager.startDragging(),
          onDoubleTap: toggleMaximize,
        ),
      ),
    );

    return <Widget>[
      // 顶边：拖动窗口。缩放交给四角 + 其余三边。
      dragHandle,
      zone(
        edge: ResizeEdge.bottom,
        cursor: SystemMouseCursors.resizeUpDown,
        left: corner,
        right: corner,
        bottom: 0,
        height: edge,
      ),
      zone(
        edge: ResizeEdge.left,
        cursor: SystemMouseCursors.resizeLeftRight,
        left: 0,
        top: corner,
        bottom: corner,
        width: edge,
      ),
      zone(
        edge: ResizeEdge.right,
        cursor: SystemMouseCursors.resizeLeftRight,
        right: 0,
        top: corner,
        bottom: corner,
        width: edge,
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
