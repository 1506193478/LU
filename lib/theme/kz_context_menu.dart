import 'dart:async';
import 'dart:ui';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'package:XL/services/logging/logger.dart';
import 'package:XL/utils/motion.dart';

/// iOS 原生生态的长按预览菜单（Context Menu）。
///
/// 交互完全对齐 iOS 系统的 `UIContextMenuInteraction`：
///
/// 1. **长按抬起**：卡片本身「浮」起来（放大 6% + 大投影），其余页面
///    被模糊 + 压暗——iOS 是对整个页面截图做模糊，Flutter 里直接用
///    `BackdropFilter` 对下层真实内容做模糊，效果一致且是实时的；
/// 2. **手指拖动**：滑到菜单项上该项高亮（不是按下态，是悬停态），
///    滑出则取消高亮——全程跟手，松手即激活；
/// 3. **触感**：浮起 heavy / 高亮切换 selection / 激活 light，
///    对应 iOS 的 `.heavy`、`.selection`、`.light`；
/// 4. **点按**：也支持先点下再拖，或直接点某一项；
/// 5. **切换类条目**（启用/禁用聚合这类）：onTap 返回 [KzMenuAfter.keepOpen]
///    并通过 [KzContextMenuController.updateItems] 换一组条目，菜单不关闭、
///    内容原位刷新——和系统里「切换 Wi-Fi」那种菜单一致。
///
/// 预览不是截图：直接把卡片 widget 再渲染一份，放在浮起的位置。
/// 卡片都是轻量 widget（图标 + 文本），重复构建的成本可以忽略，
/// 而图片走 ImageProvider 内存缓存，不会重复下载。
class KzContextMenuItem {
  const KzContextMenuItem({
    required this.label,
    this.icon,
    this.destructive = false,
    this.keepOpen = false,
    this.onTap,
  });

  final String label;
  final IconData? icon;
  final bool destructive;

  /// 切换类条目（聚合开关、默认首页这类）：激活后菜单**不关闭**，
  /// 由 onTap 里 `controller.updateItems(...)` 原位换一组条目——
  /// 和系统里「切换 Wi-Fi」的菜单一致。
  ///
  /// 为什么是静态标记而不是 onTap 返回值：普通动作（编辑/删除）会推页面
  /// 或等网络，激活后必须**立即**关菜单——如果等动作完成再关，浮层会盖在
  /// 新推的页面上。所以关不关在构建条目时就定死，动作本身 fire-and-forget。
  final bool keepOpen;

  /// 激活回调，异步执行、异常只记日志不冒泡。
  final VoidCallback? onTap;
}

class KzContextMenuController {
  final ValueNotifier<List<KzContextMenuItem>> items = ValueNotifier(const []);

  void updateItems(List<KzContextMenuItem> value) => items.value = value;

  void close() => _closeCallback?.call();

  /// 由 [showKzContextMenu] 注入，指向当次弹层的关闭逻辑。
  VoidCallback? _closeCallback;
}

/// 从 [anchorKey] 对应的卡片上弹出 iOS 风格长按菜单。
///
/// [preview] 传**同一个卡片 widget**（或者包一层它的变体），菜单浮起时
/// 会把它放大渲染在原位。
Future<void> showKzContextMenu({
  required BuildContext context,
  required GlobalKey anchorKey,
  required Widget preview,
  required List<KzContextMenuItem> items,
  KzContextMenuController? controller,
}) async {
  final BuildContext? overlayContext = Navigator.of(
    context,
    rootNavigator: true,
  ).context;
  final RenderObject? anchorObject = anchorKey.currentContext
      ?.findRenderObject();
  if (overlayContext == null || anchorObject is! RenderBox) {
    KazumiLogger().w('KzContextMenu: anchor not ready');
    return;
  }
  final OverlayState overlay = Overlay.of(overlayContext, rootOverlay: true);
  final RenderBox overlayBox = overlay.context.findRenderObject()! as RenderBox;
  final Rect anchor =
      anchorObject.localToGlobal(Offset.zero, ancestor: overlayBox) &
      Size(anchorObject.size.width, anchorObject.size.height);

  final Completer<void> done = Completer<void>();
  late OverlayEntry entry;
  final KzContextMenuController ctrl = controller ?? KzContextMenuController()
    ..updateItems(items);

  entry = OverlayEntry(
    builder: (BuildContext ctx) => _KzContextMenuOverlay(
      anchor: anchor,
      preview: preview,
      controller: ctrl,
      initialItems: items,
      onDismiss: () {
        if (!done.isCompleted) done.complete();
      },
    ),
  );
  void closeThis() {
    if (!done.isCompleted) done.complete();
  }

  ctrl._closeCallback = closeThis;
  overlay.insert(entry);
  try {
    await done.future;
  } finally {
    ctrl._closeCallback = null;
    if (entry.mounted) entry.remove();
  }
}

class _KzContextMenuOverlay extends StatefulWidget {
  const _KzContextMenuOverlay({
    required this.anchor,
    required this.preview,
    required this.controller,
    required this.initialItems,
    required this.onDismiss,
  });

  final Rect anchor;
  final Widget preview;
  final KzContextMenuController controller;
  final List<KzContextMenuItem> initialItems;
  final VoidCallback onDismiss;

  @override
  State<_KzContextMenuOverlay> createState() => _KzContextMenuOverlayState();
}

class _KzContextMenuOverlayState extends State<_KzContextMenuOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
    reverseDuration: const Duration(milliseconds: 150),
  );
  late final CurvedAnimation _curve = CurvedAnimation(
    parent: _anim,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeIn,
  );

  late List<KzContextMenuItem> _items = widget.initialItems;
  final List<GlobalKey> _itemKeys = <GlobalKey>[];

  /// 手指当前悬停的条目序号；null = 不在任何条目上。
  int? _hoverIndex;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    widget.controller.items.addListener(_onItemsChanged);
    _anim.forward();
    // 等第一帧布局完成后再允许命中测试（item keys 需要 rect）。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncItemKeys();
    });
    // 关键：菜单弹出时长按手势**还按在屏幕上**，这个 pointer 的后续 move/up
    // 事件不会命中新的 overlay（命中测试在 pointer down 时就定了）。
    // 所以走全局 pointerRouter 接管这一根指针的后续事件——
    // 手指从卡片滑到菜单项上高亮、松手激活，就是靠它实现的。
    GestureBinding.instance.pointerRouter.addGlobalRoute(_handlePointer);
  }

  void _onItemsChanged() {
    if (!mounted) return;
    setState(() {
      _items = widget.controller.items.value;
      _hoverIndex = null;
    });
    _syncItemKeys();
  }

  void _syncItemKeys() {
    if (_itemKeys.length == _items.length) return;
    _itemKeys
      ..clear()
      ..addAll(List<GlobalKey>.generate(_items.length, (_) => GlobalKey()));
  }

  void _handlePointer(PointerEvent event) {
    // 关闭动画期间不再处理：否则 hover/up 会二次触发动作或重启关闭。
    if (!mounted || _closing) return;
    switch (event) {
      case PointerDownEvent():
        _updateHover(event.position);
      case PointerMoveEvent():
        _updateHover(event.position);
      case PointerUpEvent():
        final int? hit = _hoverIndex;
        if (hit != null) {
          _activate(hit);
        } else {
          _close();
        }
      case PointerCancelEvent():
        _close();
    }
  }

  @override
  void dispose() {
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_handlePointer);
    widget.controller.items.removeListener(_onItemsChanged);
    _curve.dispose();
    _anim.dispose();
    super.dispose();
  }

  Future<void> _close() async {
    if (_closing || !mounted) return;
    _closing = true;
    KazumiHaptics.tap();
    await _anim.reverse();
    widget.onDismiss();
  }

  void _activate(int index) {
    final KzContextMenuItem item = _items[index];
    KazumiHaptics.tap();
    if (item.keepOpen) {
      // 切换类条目：菜单留着，onTap 里 controller.updateItems 换内容。
      // hover 已经清掉（手指已抬起），再滑过来要重新命中。
      try {
        item.onTap?.call();
      } catch (e) {
        KazumiLogger().e('KzContextMenu: action failed', error: e);
      }
      return;
    }
    // 普通动作：**先关菜单再执行**。动作里经常有 push 页面 / 等网络，
    // 浮层是 rootOverlay 顶层条目，不同步关掉就会盖在新页面上。
    _close();
    Future<void>.sync(() {
      try {
        item.onTap?.call();
      } catch (e) {
        KazumiLogger().e('KzContextMenu: action failed', error: e);
      }
    });
  }

  // ---- 命中测试 -------------------------------------------------------

  void _updateHover(Offset global) {
    int? hit;
    for (int i = 0; i < _itemKeys.length; i++) {
      final BuildContext? ctx = _itemKeys[i].currentContext;
      if (ctx == null) continue;
      final RenderBox box = ctx.findRenderObject()! as RenderBox;
      final Rect rect = box.localToGlobal(Offset.zero) & box.size;
      if (rect.contains(global)) {
        hit = i;
        break;
      }
    }
    if (hit != _hoverIndex) {
      setState(() => _hoverIndex = hit);
      if (hit != null) KazumiHaptics.select();
    }
  }

  // ---- 几何 -----------------------------------------------------------

  /// 菜单卡片：放在预览下方（放不下就放上方），水平方向对齐预览并收进屏幕。
  ({Rect preview, Rect menu, bool menuBelow}) _layout(Size screen) {
    final Rect a = widget.anchor;
    const double scale = 1.06;
    final Size pSize = Size(a.width * scale, a.height * scale);
    final Offset pCenter = a.center;
    final Rect preview = Rect.fromCenter(
      center: pCenter,
      width: pSize.width,
      height: pSize.height,
    );

    const double gap = 12;
    final double menuWidth = (a.width * 0.98).clamp(230.0, 330.0);
    final double menuHeight =
        _items.length * _rowHeight + (_items.length + 1) * 2.0;

    const double hMargin = 14;
    double left = preview.center.dx - menuWidth / 2;
    left = left.clamp(hMargin, screen.width - menuWidth - hMargin);

    final double safeBottom = MediaQuery.paddingOf(context).bottom;
    bool below =
        preview.bottom + gap + menuHeight < screen.height - safeBottom - 24;
    // 预览本身就在屏幕下部时菜单放上面。
    if (!below &&
        preview.top - gap - menuHeight <
            MediaQuery.paddingOf(context).top + 8) {
      below = true; // 两头都放不下：宁可盖住底部。
    }
    final double top = below
        ? (preview.bottom + gap)
        : (preview.top - gap - menuHeight);
    return (
      preview: preview,
      menu: Rect.fromLTWH(left, top, menuWidth, menuHeight),
      menuBelow: below,
    );
  }

  static const double _rowHeight = 44;

  // ---- 绘制 -----------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final Size screen = MediaQuery.sizeOf(context);
    final bool dark = Theme.of(context).brightness == Brightness.dark;
    final ({Rect preview, Rect menu, bool menuBelow}) layout = _layout(screen);
    final Rect preview = layout.preview;

    return Stack(
      children: [
        // 模糊 + 压暗。模糊是 AnimatedBuild 的一部分：进出场时 sigma 跟着
        // 动画走，不会出现「凭空糊一下」。
        Positioned.fill(
          child: AnimatedBuilder(
            animation: _curve,
            builder: (BuildContext context, Widget? child) {
              final double t = _curve.value;
              return GestureDetector(
                onTap: _close,
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 16 * t, sigmaY: 16 * t),
                  child: ColoredBox(
                    color: Colors.black.withValues(alpha: 0.24 * t),
                    child: const SizedBox.expand(),
                  ),
                ),
              );
            },
          ),
        ),
        // 卡片预览：原位放大浮起。
        AnimatedBuilder(
          animation: _curve,
          builder: (BuildContext context, Widget? child) {
            final double t = _curve.value;
            final Rect r = Rect.lerp(widget.anchor, preview, t)!;
            return Positioned.fromRect(
              rect: r,
              child: Opacity(
                opacity: t,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.35 * t),
                        blurRadius: 30,
                        offset: Offset(0, 12 * t),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: child,
                  ),
                ),
              ),
            );
          },
          child: IgnorePointer(child: widget.preview),
        ),
        // 菜单：预览下面（或上面）的玻璃条。
        ValueListenableBuilder<List<KzContextMenuItem>>(
          valueListenable: widget.controller.items,
          builder: (BuildContext context, List<KzContextMenuItem> items, _) {
            _syncItemKeys();
            final (:preview, :menu, :menuBelow) = _layout(screen);
            return Positioned.fromRect(
              rect: menu,
              child: AnimatedBuilder(
                animation: _curve,
                builder: (BuildContext context, Widget? child) {
                  final double t = _curve.value;
                  return Opacity(
                    opacity: t,
                    child: Transform.translate(
                      offset: Offset(0, menuBelow ? 8 * (1 - t) : -8 * (1 - t)),
                      child: Transform.scale(
                        scale: 0.96 + 0.04 * t,
                        alignment: menuBelow
                            ? Alignment.topCenter
                            : Alignment.bottomCenter,
                        child: child,
                      ),
                    ),
                  );
                },
                child: GestureDetector(
                  // 吸收点击：菜单上的 tap 不落到 backdrop（否则「切换类」
                  // 条目刚激活就被 backdrop 关掉）。
                  onTap: () {},
                  child: _MenuCard(
                    items: items,
                    itemKeys: _itemKeys,
                    hoverIndex: _hoverIndex,
                    dark: dark,
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _MenuCard extends StatelessWidget {
  const _MenuCard({
    required this.items,
    required this.itemKeys,
    required this.hoverIndex,
    required this.dark,
  });

  final List<KzContextMenuItem> items;
  final List<GlobalKey> itemKeys;
  final int? hoverIndex;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final Color fill = dark ? const Color(0xF02C2C2E) : const Color(0xF7FFFFFF);
    final Color ink = dark ? Colors.white : const Color(0xFF101013);
    final Color sub = dark
        ? Colors.white.withValues(alpha: 0.55)
        : const Color(0xFF8A8A8E);
    final Color hair = dark
        ? Colors.white.withValues(alpha: 0.12)
        : Colors.black.withValues(alpha: 0.10);
    final Color hover = dark
        ? Colors.white.withValues(alpha: 0.12)
        : Colors.black.withValues(alpha: 0.06);

    return ClipRRect(
      borderRadius: BorderRadius.circular(13),
      child: ColoredBox(
        color: fill,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (int i = 0; i < items.length; i++) ...[
              if (i > 0)
                Container(
                  height: 0.5,
                  margin: const EdgeInsets.fromLTRB(14, 0, 14, 0),
                  color: hair,
                ),
              _MenuRow(
                key: i < itemKeys.length ? itemKeys[i] : null,
                item: items[i],
                highlighted: hoverIndex == i,
                ink: ink,
                sub: sub,
                hover: hover,
                dark: dark,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({
    super.key,
    required this.item,
    required this.highlighted,
    required this.ink,
    required this.sub,
    required this.hover,
    required this.dark,
  });

  final KzContextMenuItem item;
  final bool highlighted;
  final Color ink;
  final Color sub;
  final Color hover;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final Color color = item.destructive ? const Color(0xFFFF3B30) : ink;
    return Container(
      height: 44,
      color: highlighted ? hover : Colors.transparent,
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 0),
      child: Row(
        children: [
          Expanded(
            child: Text(
              item.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: 16,
                letterSpacing: -0.3,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
          if (item.icon != null)
            Icon(item.icon, size: 18, color: item.destructive ? color : sub),
        ],
      ),
    );
  }
}
