import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:XL/bean/widget/desktop_window_controls.dart';
import 'package:XL/pages/emby/emby_preview_style.dart';
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
  static const double _dragThreshold = 5.0;

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
    final appBarLeading = widget.leading ??
        // 「能给返回键就给」。
        //
        // 之前只认 `impliesAppBarDismissal`：设置页的分类是推进 RouterOutlet 的
        // 嵌套 navigator，那里这条判据不成立，于是「我的 / 设置」里点开的页面
        // 全都没有返回键——Windows 上没有手势返回，等于退不出去。
        // 只要当前能 pop，就画一个；首页那种根路由 pop 不掉，自然不会出现。
        (Navigator.of(context).canPop() ||
                (ModalRoute.of(context)?.impliesAppBarDismissal ?? false)
            ? IconButton(
                onPressed: () => context.maybePop(),
                tooltip: '返回',
                icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
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
                child: DefaultTextStyle(
                  // Pv 全铺之后，所有走 SysAppBar 的页面标题统一成 Pv 的墨色
                  // 和字重，否则标题会跟着主题的 Clay 排版走，跟页面里的
                  // Pv 列表不是同一套。
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                    color: PvColors.ink(context),
                  ),
                  child: widget.title!,
                ),
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
        // 页面底色统一是 Pv 的 #F3F1F2 / 深色 #151417，AppBar 直接融进去，
        // 不再用拟态那个中灰。
        // 默认透明：页面底色由壳层的 [LuBackdrop] 统一提供，
        // AppBar 再铺一层实色就会在顶部切出一条色带。
        backgroundColor: widget.backgroundColor ?? Colors.transparent,
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
