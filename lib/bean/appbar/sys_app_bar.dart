import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:XL/bean/widget/clay_neu.dart';
import 'package:XL/bean/widget/desktop_window_controls.dart';
import 'package:XL/bean/widget/embedded_native_control_area.dart';
import 'package:XL/services/platform/desktop_window_config.dart';
import 'package:window_manager/window_manager.dart';
import 'package:XL/utils/device.dart';

class SysAppBar extends StatefulWidget implements PreferredSizeWidget {
  final double? toolbarHeight;
  final Widget? title;
  final Color? backgroundColor;
  final List<Widget>? actions;
  final Widget? leading;
  final bool needTopOffset;

  const SysAppBar({
    super.key,
    this.toolbarHeight,
    this.title,
    this.backgroundColor,
    this.actions,
    this.leading,
    this.needTopOffset = true,
  });

  @override
  Size get preferredSize {
    // Reserve space for native macOS window controls.
    final topOffset =
        Platform.isMacOS &&
            needTopOffset &&
            DesktopWindowConfig.showWindowButton
        ? 22.0
        : 0.0;
    return Size.fromHeight((toolbarHeight ?? kToolbarHeight) + topOffset);
  }

  @override
  State<SysAppBar> createState() => _SysAppBarState();
}

class _SysAppBarState extends State<SysAppBar> {
  /// 按下时的全局坐标；非空表示指针正按在标题栏上。
  Offset? _dragStartPosition;

  /// 是否已经进入了系统拖动循环（startDragging 是模态的，
  /// 进入后 Flutter 收不到后续指针事件，不会再触发本回调）。
  bool _dragStarted = false;

  /// 位移超过这个值才认作「拖窗口」，纯点击（按按钮、返回键）不受影响。
  static const double _dragThreshold = 8.0;

  void _handlePointerDown(PointerDownEvent event) {
    _dragStartPosition = event.position;
    _dragStarted = false;
  }

  void _handlePointerMove(PointerMoveEvent event) {
    final Offset? start = _dragStartPosition;
    if (_dragStarted || start == null) return;
    if ((event.position - start).distance < _dragThreshold) return;
    _dragStarted = true;
    windowManager.startDragging();
  }

  void _handlePointerEnd() {
    _dragStartPosition = null;
    _dragStarted = false;
  }

  @override
  Widget build(BuildContext context) {
    final bool desktop = isDesktop();
    final appBarActions = <Widget>[...?widget.actions];
    if (desktop) {
      if (DesktopWindowConfig.frameless) {
        // 无边框模式下系统标题栏没了，三个按钮得自己画。
        appBarActions.add(const DesktopWindowControls());
      } else if (!DesktopWindowConfig.showWindowButton) {
        appBarActions.add(CloseButton(onPressed: () => windowManager.close()));
      }
      appBarActions.add(const SizedBox(width: 8));
    }
    final appBarLeading =
        widget.leading ??
        ((ModalRoute.of(context)?.impliesAppBarDismissal ?? false)
            ? IconButton(
                onPressed: () => context.maybePop(),
                icon: const Icon(Icons.arrow_back),
              )
            : null);

    // 拖动窗口不用 GestureDetector：标题栏经常套在 CustomScrollView /
    // SliverAppBar 这类可滚动容器里，pan 手势会被滚动抢走竞技场，
    // 表现为「窗口拖不动」。Listener 在命中测试分发阶段就能拿到指针事件，
    // 不参与手势竞技场，位移超阈值直接进系统拖动循环，谁也抢不走。
    return Listener(
      onPointerDown: desktop ? _handlePointerDown : null,
      onPointerMove: desktop ? _handlePointerMove : null,
      onPointerUp: desktop ? (_) => _handlePointerEnd() : null,
      onPointerCancel: desktop ? (_) => _handlePointerEnd() : null,
      child: AppBar(
        toolbarHeight: widget.preferredSize.height,
        scrolledUnderElevation: 0.0,
        title: widget.title != null
            ? EmbeddedNativeControlArea(
                requireOffset: widget.needTopOffset,
                child: widget.title!,
              )
            : null,
        centerTitle: Platform.isIOS,
        actions: appBarActions.map((action) {
          return EmbeddedNativeControlArea(
            requireOffset: widget.needTopOffset,
            child: action,
          );
        }).toList(),
        leading: appBarLeading != null
            ? EmbeddedNativeControlArea(
                requireOffset: widget.needTopOffset,
                child: appBarLeading,
              )
            : null,
        backgroundColor:
            widget.backgroundColor ?? neuScaffoldBackground(context),
        automaticallyImplyLeading: false,
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness:
              Theme.of(context).brightness == Brightness.light
              ? Brightness.dark
              : Brightness.light,
          systemNavigationBarColor: Colors.transparent,
          systemNavigationBarDividerColor: Colors.transparent,
        ),
      ),
    );
  }
}
