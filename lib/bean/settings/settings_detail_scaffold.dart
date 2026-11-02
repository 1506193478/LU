import 'package:flutter/material.dart';
import 'package:XL/bean/appbar/sys_app_bar.dart';
import 'package:XL/pages/emby/emby_preview_style.dart';

class SettingsPaneScope extends InheritedWidget {
  const SettingsPaneScope({
    super.key,
    required this.embedded,
    required this.showBackButton,
    required this.onBack,
    required super.child,
  });

  final bool embedded;
  final bool showBackButton;
  final VoidCallback onBack;

  static SettingsPaneScope? of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<SettingsPaneScope>();
  }

  @override
  bool updateShouldNotify(SettingsPaneScope oldWidget) {
    return embedded != oldWidget.embedded ||
        showBackButton != oldWidget.showBackButton ||
        onBack != oldWidget.onBack;
  }
}

class SettingsDetailScaffold extends StatelessWidget {
  const SettingsDetailScaffold({
    super.key,
    required this.title,
    required this.body,
    this.actions,
    this.leading,
    this.floatingActionButton,
    this.bottomNavigationBar,
  });

  final Widget title;
  final Widget body;
  final List<Widget>? actions;
  final Widget? leading;
  final Widget? floatingActionButton;
  final Widget? bottomNavigationBar;

  @override
  Widget build(BuildContext context) {
    final scope = SettingsPaneScope.of(context);
    final route = ModalRoute.of(context);

    // 返回按钮的判据要「宁可多给」。
    //
    // 之前只看 `scope.showBackButton` 和 `impliesAppBarDismissal`：设置页里
    // 分类是**推进 RouterOutlet** 的，此时 `_location` 已经被改成目标分类，
    // `showBackButton` 反而算成 false；而嵌套 navigator 里的路由又不一定
    // 被认作「会关掉页面」。两头都不成立，结果就是「我的 / 设置」里点开的
    // 每一页都只剩手势返回，Windows 上更是完全退不出去。
    //
    // 现在的顺序：显式 leading > 分类栏给的 onBack > 能 pop 就给返回键 >
    // 路由自己说能关。
    final bool canPop = Navigator.of(context).canPop();
    final bool showBack = leading != null ||
        (scope?.showBackButton ?? false) ||
        canPop ||
        (route?.impliesAppBarDismissal ?? false);

    final PreferredSizeWidget appBar = SysAppBar(
      title: title,
      actions: actions,
      leading: leading ??
          (showBack
              ? IconButton(
                  tooltip: '返回',
                  onPressed: scope?.onBack ?? () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
                )
              : null),
    );

    // Keep routed panes opaque during transitions.
    return Scaffold(
      backgroundColor: PvColors.page(context),
      appBar: appBar,
      body: body,
      floatingActionButton: floatingActionButton,
      bottomNavigationBar: bottomNavigationBar,
    );
  }
}
