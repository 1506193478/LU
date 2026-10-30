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

class SysAppBar extends StatelessWidget implements PreferredSizeWidget {
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
  Widget build(BuildContext context) {
    final desktop = isDesktop();
    final appBarActions = <Widget>[...?actions];
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
        leading ??
        ((ModalRoute.of(context)?.impliesAppBarDismissal ?? false)
            ? IconButton(
                onPressed: () => context.maybePop(),
                icon: const Icon(Icons.arrow_back),
              )
            : null);

    return GestureDetector(
      onPanStart: desktop ? (_) => windowManager.startDragging() : null,
      child: AppBar(
        toolbarHeight: preferredSize.height,
        scrolledUnderElevation: 0.0,
        title: title != null
            ? EmbeddedNativeControlArea(
                requireOffset: needTopOffset,
                child: title!,
              )
            : null,
        centerTitle: Platform.isIOS,
        actions: appBarActions.map((action) {
          return EmbeddedNativeControlArea(
            requireOffset: needTopOffset,
            child: action,
          );
        }).toList(),
        leading: appBarLeading != null
            ? EmbeddedNativeControlArea(
                requireOffset: needTopOffset,
                child: appBarLeading,
              )
            : null,
        backgroundColor: backgroundColor ?? neuScaffoldBackground(context),
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
}
