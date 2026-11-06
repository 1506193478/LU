import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:flutter/services.dart';
import 'package:XL/utils/motion.dart';
import 'package:XL/bean/dialog/dialog_helper.dart';
import 'package:XL/bean/navigation/glass_tab_bar.dart';
import 'package:XL/bean/widget/clay_neu.dart';
import 'package:XL/bean/widget/embedded_native_control_area.dart';
import 'package:XL/navigation.dart';
import 'package:XL/pages/download/download_controller.dart';
import 'package:XL/pages/emby/emby_preview_style.dart';
import 'package:XL/theme/lu_glass.dart';
import 'package:XL/pages/menu/route_visibility.dart';
import 'package:XL/pages/router.dart';
import 'package:XL/utils/device.dart';

/// 底部导航的 5 个目标，顺序与 `menu.getPath` 一致。
const List<KazumiTabItem> kKazumiTabs = [
  KazumiTabItem(
    icon: Icons.home_outlined,
    selectedIcon: Icons.home,
    label: '推荐',
  ),
  KazumiTabItem(
    icon: Icons.favorite_outline,
    selectedIcon: Icons.favorite,
    label: '追番',
  ),
  KazumiTabItem(
    icon: Icons.groups_outlined,
    selectedIcon: Icons.groups,
    label: '一起看',
  ),
  KazumiTabItem(
    icon: Icons.dns_outlined,
    selectedIcon: Icons.dns,
    label: 'Emby',
  ),
  KazumiTabItem(
    // 齿轮等于设置，但这页装的是个人资料、历史、下载。齿轮留给页内右上角
    // 那颗真正的设置入口。
    icon: Icons.person_outline_rounded,
    selectedIcon: Icons.person_rounded,
    label: '我的',
  ),
];

class ScaffoldMenu extends StatefulWidget {
  const ScaffoldMenu({super.key, required this.location});

  final String location;

  @override
  State<ScaffoldMenu> createState() => _ScaffoldMenu();
}

class _ScaffoldMenu extends State<ScaffoldMenu> with RouteAware {
  final _outletKey = GlobalKey<RouterOutletState>();
  late int _selectedIndex = menu.indexForPath(widget.location);
  DateTime? _lastExitPromptAt;

  /// The shell sits at the bottom of the root stack and stays mounted while
  /// other pages cover it, so it publishes that state for its subtree.
  bool _isCovered = false;

  @override
  void didUpdateWidget(covariant ScaffoldMenu oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.location != widget.location) {
      _selectedIndex = menu.indexForPath(widget.location);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute<void>) {
      rootRouteObserver.subscribe(this, route);
    }
  }

  @override
  void dispose() {
    rootRouteObserver.unsubscribe(this);
    super.dispose();
  }

  @override
  void didPushNext() => _setCovered(true);

  @override
  void didPopNext() => _setCovered(false);

  void _setCovered(bool value) {
    if (!mounted || _isCovered == value) {
      return;
    }
    setState(() => _isCovered = value);
  }

  void _selectDestination(int index) {
    _lastExitPromptAt = null;
    if (index == _selectedIndex) {
      return;
    }
    final outlet = _outletKey.currentState;
    if (outlet == null) return;
    outlet.navigate('/tab${menu.getPath(index)}/');
    setState(() => _selectedIndex = index);
    // iOS 的 tab 切换有一记很轻的 selection feedback，是"跟手"的一部分。
    KazumiHaptics.select();
  }

  void _openDownloads() {
    context.pushNamed('/settings/download/');
  }

  void _handleSystemBack(BuildContext context) {
    if (_outletKey.currentState?.maybePop() ?? false) {
      _lastExitPromptAt = null;
      return;
    }

    if (_selectedIndex != 0) {
      _selectDestination(0);
      return;
    }

    final now = DateTime.now();
    final lastPromptAt = _lastExitPromptAt;
    if (lastPromptAt == null ||
        now.difference(lastPromptAt) > const Duration(seconds: 2)) {
      _lastExitPromptAt = now;
      KazumiDialog.showToast(message: '再按一次退出应用', context: context);
      return;
    }

    _lastExitPromptAt = null;
    SystemNavigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    return RouteVisibility(
      isCovered: _isCovered,
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) {
            _handleSystemBack(context);
          }
        },
        child: OrientationBuilder(
          builder: (context, orientation) {
            // 手机端一律用底部导航：横屏时侧栏会挤掉太多宽度，而且拟态底
            // 配 Material 侧栏不搭。桌面端才按方向切侧栏。
            final bool useSideMenu =
                isDesktop() && orientation == Orientation.landscape;
            return useSideMenu
                ? _sideMenu(context, _selectedIndex)
                : _bottomMenu(context, _selectedIndex);
          },
        ),
      ),
    );
  }

  Widget _outlet(
    BuildContext context, {
    BorderRadius? borderRadius,
    Color? background,
  }) {
    Widget child = NotificationListener<NavigationNotification>(
      // A non-poppable outlet must not override the shell's PopScope state.
      onNotification: (notification) => !notification.canHandlePop,
      child: RouterOutlet(key: _outletKey),
    );
    if (borderRadius != null) {
      child = ClipRRect(borderRadius: borderRadius, child: child);
    }
    return Container(
      decoration: BoxDecoration(
        color: background ?? Theme.of(context).colorScheme.primaryContainer,
        borderRadius: borderRadius,
      ),
      child: child,
    );
  }

  Widget _bottomMenu(BuildContext context, int selectedIndex) {
    return Scaffold(
      // 底栏是浮起来的：内容从下面滚过去。
      // 页面底部留白统一按 immersiveTabBarInset 算。
      backgroundColor: Colors.transparent,
      extendBody: true,
      // 内容容器的底也要跟着拟态走，否则切页时会闪一下 primaryContainer 色带。
      // 背景由壳层统一画（MaterialApp.builder 里的 LuBackdrop）。
      // 这里只管透明出口，不要再叠一层——叠了就是两份全屏渐变。
      body: _outlet(context, background: Colors.transparent),
      // 底部导航统一走「胶囊玻璃条」。
      //
      // 原来手机端一律用拟态那条（`isNeuLayout` 在手机上恒为 true），
      // 玻璃条只在桌面窄窗口才出现，等于用户根本看不到。现在玻璃胶囊
      // 是唯一形态：它浮在内容之上，背后内容被模糊透上来，和页面
      // 用什么皮肤无关。
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 下载中给一条细进度条：下载管理在「我的」第二层，原来没有任何
          // 常驻指示，正在下什么、下到哪了完全看不见。
          _DownloadActivityStrip(onTap: _openDownloads),
          KazumiTabBar(
            items: kKazumiTabs,
            selectedIndex: selectedIndex,
            onSelected: _selectDestination,
          ),
        ],
      ),
    );
  }

  /// 桌面端宽屏：拟态侧栏 + 圆角内容区。
  ///
  /// 竖屏/手机端完全不走这里，仍然用底部 [KazumiTabBar]。
  /// 横屏但不够宽（手机横屏、桌面窗口被拖窄）时退回原来的
  /// [NavigationRail] 侧栏——拟态排版要求内容区四边内缩，窄窗口下
  /// 会挤掉太多空间，而且页面底色是按宽度断点切的，退回才不会有
  /// 「拟态侧栏 + 主题底色」的错配。
  Widget _sideMenu(BuildContext context, int selectedIndex) {
    if (!isDesktopWideLayout(context)) {
      return _legacySideMenu(context, selectedIndex);
    }
    // Pv 是唯一语言之后，壳层也走 Pv 的页面底色 + 白卡，不再用拟态的中灰。
    final Color pageColor = PvColors.page(context);
    final BorderRadius borderRadius = BorderRadius.circular(14);
    return Scaffold(
      backgroundColor: pageColor,
      body: Row(
        children: <Widget>[
          _pvRail(context, selectedIndex),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(right: 14, top: 14, bottom: 14),
              child: _outlet(
                context,
                borderRadius: borderRadius,
                background: pageColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 窄横屏兜底：保留上游的 NavigationRail 侧栏。
  Widget _legacySideMenu(BuildContext context, int selectedIndex) {
    const BorderRadius borderRadius = BorderRadius.only(
      topLeft: Radius.circular(16),
      bottomLeft: Radius.circular(16),
    );
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
      body: Row(
        children: <Widget>[
          EmbeddedNativeControlArea(
            child: NavigationRail(
              backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
              groupAlignment: 1,
              leading: FloatingActionButton(
                elevation: 0,
                heroTag: null,
                onPressed: () => context.pushNamed('/search/'),
                child: const Icon(Icons.search),
              ),
              labelType: NavigationRailLabelType.selected,
              destinations: const <NavigationRailDestination>[
                NavigationRailDestination(
                  selectedIcon: Icon(Icons.home),
                  icon: Icon(Icons.home_outlined),
                  label: Text('推荐'),
                ),
                NavigationRailDestination(
                  selectedIcon: Icon(Icons.favorite),
                  icon: Icon(Icons.favorite_border),
                  label: Text('追番'),
                ),
                NavigationRailDestination(
                  selectedIcon: Icon(Icons.groups),
                  icon: Icon(Icons.groups_outlined),
                  label: Text('一起看'),
                ),
                NavigationRailDestination(
                  selectedIcon: Icon(Icons.dns),
                  icon: Icon(Icons.dns_outlined),
                  label: Text('Emby'),
                ),
                NavigationRailDestination(
                  selectedIcon: Icon(Icons.person),
                  icon: Icon(Icons.person_outline),
                  label: Text('我的'),
                ),
              ],
              selectedIndex: selectedIndex,
              onDestinationSelected: _selectDestination,
            ),
          ),
          Expanded(child: _outlet(context, borderRadius: borderRadius)),
        ],
      ),
    );
  }

  /// 桌面侧栏：Pv 白卡 + 蓝色选中胶囊。
  Widget _pvRail(BuildContext context, int selectedIndex) {
    return SizedBox(
      width: 236,
      // macOS 的红绿灯按钮浮在 Flutter 视图上，得给它让出位置。
      child: EmbeddedNativeControlArea(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Container(
            decoration: BoxDecoration(
              color: PvColors.card(context),
              borderRadius: BorderRadius.circular(18),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        gradient: const LinearGradient(
                          colors: <Color>[PvColors.blue, Color(0xFF4FA0FF)],
                        ),
                      ),
                      alignment: Alignment.center,
                      child: const Text(
                        'LU',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.4,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            'LU',
                            style: PvText.section(
                              context,
                            ).copyWith(fontSize: 15),
                          ),
                          Text(
                            '番剧 · 桌面版',
                            style: PvText.rowSub(
                              context,
                            ).copyWith(fontSize: 11.5),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => context.pushNamed('/search/'),
                  child: Container(
                    height: 40,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: PvColors.searchFill(context),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Row(
                      children: <Widget>[
                        Icon(
                          Icons.search_rounded,
                          size: 16,
                          color: PvColors.searchHint(context),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '搜索番剧、角色、标签…',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12.5,
                              color: PvColors.searchHint(context),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _PvRailItem(
                  selected: selectedIndex == 0,
                  icon: Icons.home_outlined,
                  activeIcon: Icons.home,
                  label: '推荐',
                  onTap: () => _selectDestination(0),
                ),
                _PvRailItem(
                  selected: selectedIndex == 1,
                  icon: Icons.favorite_border,
                  activeIcon: Icons.favorite,
                  label: '追番',
                  onTap: () => _selectDestination(1),
                ),
                _PvRailItem(
                  selected: selectedIndex == 2,
                  icon: Icons.groups_outlined,
                  activeIcon: Icons.groups,
                  label: '一起看',
                  onTap: () => _selectDestination(2),
                ),
                _PvRailItem(
                  selected: selectedIndex == 3,
                  icon: Icons.dns_outlined,
                  activeIcon: Icons.dns,
                  label: 'Emby',
                  onTap: () => _selectDestination(3),
                ),
                _PvRailItem(
                  selected: selectedIndex == 4,
                  // 齿轮等于设置，但这页主要是个人资料和历史。齿轮留给
                  // 真正的设置入口（页内右上角那颗）。
                  icon: Icons.person_outline_rounded,
                  activeIcon: Icons.person_rounded,
                  label: '我的',
                  onTap: () => _selectDestination(4),
                ),
                const Spacer(),
                Text(
                  'LU 桌面版',
                  style: PvText.rowSub(context).copyWith(fontSize: 11),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 侧栏单个导航项：选中是淡蓝胶囊 + 蓝字，hover 只提亮一点。
class _PvRailItem extends StatefulWidget {
  const _PvRailItem({
    required this.selected,
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.onTap,
  });

  final bool selected;
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final VoidCallback onTap;

  @override
  State<_PvRailItem> createState() => _PvRailItemState();
}

class _PvRailItemState extends State<_PvRailItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final bool on = widget.selected;
    final bool hover = !on && _hovered;
    final Color fg = on ? PvColors.subInk(context) : PvColors.ink2(context);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOut,
          height: 42,
          margin: const EdgeInsets.only(bottom: 2),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(11),
            color: on
                ? PvColors.subCap(context)
                : (hover
                      ? PvColors.ink(context).withValues(alpha: 0.04)
                      : Colors.transparent),
          ),
          child: Row(
            children: <Widget>[
              Icon(on ? widget.activeIcon : widget.icon, size: 18, color: fg),
              const SizedBox(width: 11),
              Expanded(
                child: Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: on ? FontWeight.w600 : FontWeight.w400,
                    color: fg,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 底栏上方的下载活动条。
///
/// 只在真的有事在做的时候出现（正在下 / 排队中），做完自动消失 ——
/// 常驻一条 0% 的横条比没有更烦人。
class _DownloadActivityStrip extends StatelessWidget {
  const _DownloadActivityStrip({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final DownloadController controller = inject<DownloadController>();
    return Observer(
      builder: (BuildContext context) {
        final int active = controller.activeDownloads;
        final int queued = controller.queuedDownloads;
        if (active == 0 && queued == 0) {
          return const SizedBox.shrink();
        }
        final double progress = controller.downloadProgress.clamp(0.0, 1.0);
        final bool dark = PvColors.isDark(context);
        final String text = active > 0
            ? '正在下载 $active 集 · ${(progress * 100).round()}%'
            : '排队中 $queued 集';

        return Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 6),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: Container(
              height: 30,
              decoration: BoxDecoration(
                color: dark ? const Color(0xFF1F1E22) : Colors.white,
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: PvColors.hair(context), width: 0.8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: dark ? 0.30 : 0.08),
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                children: [
                  // 进度底：一条从左往右长的浅蓝，比数字更快看出来「在动」。
                  Positioned.fill(
                    child: FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: active > 0 ? progress.clamp(0.02, 1.0) : 0,
                      child: ColoredBox(
                        color: PvColors.blue.withValues(
                          alpha: dark ? 0.24 : 0.14,
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      children: [
                        Icon(
                          Icons.downloading_rounded,
                          size: 15,
                          color: PvColors.blue,
                        ),
                        const SizedBox(width: 7),
                        Expanded(
                          child: Text(
                            text,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: PvColors.ink(context),
                            ),
                          ),
                        ),
                        Text(
                          '查看',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: PvColors.blue,
                          ),
                        ),
                        Icon(
                          Icons.chevron_right_rounded,
                          size: 15,
                          color: PvColors.blue,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
