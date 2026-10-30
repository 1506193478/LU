import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:flutter/services.dart';
import 'package:XL/bean/dialog/dialog_helper.dart';
import 'package:XL/bean/navigation/glass_tab_bar.dart';
import 'package:XL/bean/navigation/neu_tab_bar.dart';
import 'package:XL/bean/widget/clay_neu.dart';
import 'package:XL/bean/widget/embedded_native_control_area.dart';
import 'package:XL/bean/widget/pressable.dart';
import 'package:XL/navigation.dart';
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
    icon: Icons.timeline_outlined,
    selectedIcon: Icons.timeline,
    label: '时间表',
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
    icon: Icons.settings_outlined,
    selectedIcon: Icons.settings,
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
    final bool neu = isNeuLayout(context);
    return Scaffold(
      // 两种底栏都是浮起来的：内容从下面滚过去。拟态那条自己是实色的，
      // 滚到下面的内容会被它挡住，所以底不需要额外铺色。
      // 页面底部留白统一按 immersiveTabBarInset 算，两种栏高度一致。
      extendBody: true,
      // 内容容器的底也要跟着拟态走，否则切页时会闪一下 primaryContainer 色带。
      body: _outlet(context, background: neuScaffoldBackground(context)),
      bottomNavigationBar: neu
          ? NeuTabBar(
              items: kKazumiTabs,
              selectedIndex: selectedIndex,
              onSelected: _selectDestination,
            )
          : KazumiTabBar(
              items: kKazumiTabs,
              selectedIndex: selectedIndex,
              onSelected: _selectDestination,
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
    final NeuTokens tokens = NeuTokens.of(context);
    // 内容区四边都内缩 14，所以四个角都要圆。
    final BorderRadius borderRadius =
        BorderRadius.circular(NeuRadius.window);
    return Scaffold(
      // 拟态必须有统一的中灰底，不能用主题里的 surfaceContainer。
      backgroundColor: tokens.base,
      body: Row(
        children: <Widget>[
          _neuRail(context, selectedIndex),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(right: 14, top: 14, bottom: 14),
              child: _outlet(
                context,
                borderRadius: borderRadius,
                background: tokens.base,
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
                  selectedIcon: Icon(Icons.timeline),
                  icon: Icon(Icons.timeline_outlined),
                  label: Text('时间表'),
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
                  selectedIcon: Icon(Icons.settings),
                  icon: Icon(Icons.settings_outlined),
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

  Widget _neuRail(BuildContext context, int selectedIndex) {
    final ThemeData theme = Theme.of(context);
    return SizedBox(
      width: NeuSpacing.railWidth + 28,
      // macOS 的红绿灯按钮浮在 Flutter 视图上，得给它让出位置。
      child: EmbeddedNativeControlArea(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: NeuSurface(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        gradient: LinearGradient(
                          colors: <Color>[
                            theme.colorScheme.primary,
                            theme.colorScheme.primary.withValues(alpha: 0.72),
                          ],
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        'LU',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                          color: theme.colorScheme.onPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            'LU',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            '番剧 · 桌面版',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                NeuSurface(
                  mode: NeuMode.recess,
                  radius: NeuRadius.control,
                  height: 42,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  onTap: () => context.pushNamed('/search/'),
                  child: Row(
                    children: <Widget>[
                      Icon(
                        Icons.search,
                        size: 16,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '搜索番剧、角色、标签…',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                _railItem(
                  context,
                  0,
                  selectedIndex,
                  Icons.home_outlined,
                  Icons.home,
                  '推荐',
                ),
                _railItem(
                  context,
                  1,
                  selectedIndex,
                  Icons.timeline_outlined,
                  Icons.timeline,
                  '时间表',
                ),
                _railItem(
                  context,
                  2,
                  selectedIndex,
                  Icons.favorite_border,
                  Icons.favorite,
                  '追番',
                ),
                _railItem(
                  context,
                  3,
                  selectedIndex,
                  Icons.groups_outlined,
                  Icons.groups,
                  '一起看',
                ),
                _railItem(
                  context,
                  4,
                  selectedIndex,
                  Icons.settings_outlined,
                  Icons.settings,
                  '我的',
                ),
                const Spacer(),
                Text(
                  'LU 桌面版',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 侧栏项：选中态是「凹槽 + 强调色」，不是实色块——实色块会把
  /// 拟态的层次压平。
  ///
  /// 每一项都必须自己处理点击：这里不能只靠外层包一个手势检测器，
  /// 选中态是个 `NeuSurface`、未选中态是裸 `Padding`，命中区域和层级
  /// 都不一样，统一在外层套手势会让凹槽里的点击被裁掉。
  Widget _railItem(
    BuildContext context,
    int index,
    int selectedIndex,
    IconData icon,
    IconData activeIcon,
    String label,
  ) {
    return _NeuRailItem(
      index: index,
      selected: index == selectedIndex,
      icon: icon,
      activeIcon: activeIcon,
      label: label,
      onTap: () => _selectDestination(index),
    );
  }
}

/// 侧栏单个导航项。
///
/// 桌面端用鼠标，所以除了点击还要有 hover 反馈（底色提亮 + 手型光标），
/// 否则用户根本不知道这里能点。
class _NeuRailItem extends StatefulWidget {
  const _NeuRailItem({
    required this.index,
    required this.selected,
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.onTap,
  });

  final int index;
  final bool selected;
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final VoidCallback onTap;

  @override
  State<_NeuRailItem> createState() => _NeuRailItemState();
}

class _NeuRailItemState extends State<_NeuRailItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool on = widget.selected;
    final bool hover = !on && _hovered;

    final Widget content = Row(
      children: <Widget>[
        Icon(
          on ? widget.activeIcon : widget.icon,
          size: 18,
          color: on
              ? theme.colorScheme.primary
              : theme.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            widget.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 14,
              fontWeight: on ? FontWeight.w600 : FontWeight.w400,
              color: on
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );

    // 选中 = 凹槽 + 强调色；hover = 轻微提亮；其余 = 平的。
    final Widget body = on
        ? NeuSurface(
            mode: NeuMode.recess,
            radius: NeuRadius.control,
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: content,
          )
        : AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOut,
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(NeuRadius.control),
              color: hover
                  ? theme.colorScheme.onSurface.withValues(alpha: 0.05)
                  : Colors.transparent,
            ),
            child: content,
          );

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Pressable(
        pressedScale: 0.97,
        haptic: false,
        borderRadius: BorderRadius.circular(NeuRadius.control),
        onTap: widget.onTap,
        child: body,
      ),
    );
  }
}
