import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:XL/bean/appbar/sys_app_bar.dart';

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

  /// 兜底返回：先让最近的 Navigator 退，退不动再交给 modular 的栈，
  /// 最后退回「我的」。Windows 没有手势返回，卡在二级页是最难受的。
  static void _fallbackBack(BuildContext context) {
    final NavigatorState nav = Navigator.of(context);
    if (nav.canPop()) {
      nav.maybePop();
      return;
    }
    if (context.maybePop()) return;
    context.navigate('/tab/my');
  }

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
    // 再后来改成「canPop 就给」还是漏：RouterOutlet 里的根路由被 navigate
    // 替换时 canPop 也是 false。所以别猜了，按布局判：
    //   · 窄屏（没有左侧分类栏）→ 这类页面一定是从别处点进来的，一律给返回；
    //   · 宽屏（embedded，左边分类栏还在）→ 只有开了二级路由才需要返回，
    //     否则左侧导航本来就摆在那儿。
    final bool canPop = Navigator.of(context).canPop();
    final bool embedded = scope?.embedded ?? false;
    final bool showBack =
        leading != null ||
        (scope?.showBackButton ?? false) ||
        canPop ||
        (route?.impliesAppBarDismissal ?? false) ||
        !embedded;

    final PreferredSizeWidget appBar = SysAppBar(
      title: title,
      actions: actions,
      // 透明：底色交给 [LuBackdrop] 的渐变，AppBar 只负责放按钮和标题。
      backgroundColor: Colors.transparent,
      leading:
          leading ??
          (showBack
              ? IconButton(
                  tooltip: '返回',
                  onPressed: scope?.onBack ?? () => _fallbackBack(context),
                  icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
                )
              : null),
    );

    // 背景只由壳层（MaterialApp.builder 里的 LuBackdrop）提供一次。
    // 这里以前又包了一层，结果设置页是两份全屏渐变叠着画。
    // Keep routed panes opaque during transitions.
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: appBar,
      body: body,
      floatingActionButton: floatingActionButton,
      bottomNavigationBar: bottomNavigationBar,
    );
  }
}
