import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 播放器里的 iOS 风格弹出菜单（对标 `UIMenu`）。
///
/// 为什么不用 bottom sheet：播放器是横屏全屏画面，从底部升起来一张大板子，
/// 既挡画面又和「点哪个按钮就在哪弹」的心理预期对不上。这里的做法是：
///
///   * 从被点的按钮（anchor）长出来，右边缘对齐、落在按钮下方；
///   * 卡片是 iOS 深色外观的 `.systemMaterialDark`（圆角 13 / 发丝分隔线 /
///     选中项在行尾打勾），也就是全黑播放器里 UIMenu 本来的样子；
///   * 展开用 spring 感（easeOutBack 轻微过冲）+ 淡入，焦点对准锚点那一角，
///     收起快而干脆；
///   * 打开、选中各给一次触觉。

/// 菜单材质。
///
/// 这里以前是浅色卡片（#F7F7F7），理由是「浅色浮在暗画面上更容易分辨」。
/// 实际观感正好相反：全黑的播放器画面里突然铺一块近乎纯白的板子，白得刺眼；
/// 而 iOS 自己的 UIMenu 是**跟随系统外观**的，深色外观下就是
/// `.systemMaterialDark` —— 一块约 95% 不透明的 #1C1C1E。浅色卡片恰恰是
/// 最不 iOS 的那个选择。
///
/// 下面这几个色值直接对着 HIG 的语义色取：
///   label / secondaryLabel / tertiaryLabel / separator / systemBlue / systemRed
/// 的深色外观值，所以换主题不用再单独调一遍。
const Color embyMenuBg = Color(0xF21C1C1E);
const Color embyMenuInk = Color(0xFFFFFFFF);
const Color embyMenuInkSecondary = Color(0x99EBEBF5);
const Color embyMenuInkTertiary = Color(0x66EBEBF5);
const Color embyMenuLine = Color(0x2EFFFFFF);
const Color embyMenuPressed = Color(0x14FFFFFF);
const Color embyMenuAccent = Color(0xFF0A84FF);
const Color embyMenuDanger = Color(0xFFFF453A);

/// 菜单卡片的圆角，和 UIMenu 一致。
const double _menuRadius = 13;

/// 一行菜单。
///
/// 度量对着 UIMenu：行高 44 起、左右 16、正文 16.5pt、选中项**在行尾打勾**
/// 且不改变行底色。以前是「左边常驻勾位 + 选中整行压深 + 文字加粗」，那是
/// Material 的 CheckboxListTile 语汇，iOS 从来不是这么选的。
class EmbyMenuRow extends StatelessWidget {
  const EmbyMenuRow({
    super.key,
    required this.label,
    this.detail,
    this.icon,
    this.checked = false,
    this.chevron = false,
    this.destructive = false,
    this.enabled = true,
    this.onTap,
    this.showDivider = true,
    this.trailing,
  });

  final String label;

  /// 副标题（编码信息、当前值这类），单独一行、字号小一号。
  final String? detail;

  /// 行尾的值（章节时间、音量档位这种）。
  ///
  /// 和 [detail] 的区别就是 iOS 的两种排版：detail 是标题下面的灰色小字
  /// （「解码 / 硬解码」这种主从关系），trailing 是同一行贴右边的值
  /// （「章节 1 ───── 00:00」这种键值关系）。
  final String? trailing;
  final IconData? icon;
  final bool checked;

  /// 右侧 `>`，表示还会再弹一层。
  final bool chevron;
  final bool destructive;
  final bool enabled;
  final VoidCallback? onTap;

  /// 组内最后一行不画分隔线，否则会和卡片圆角切出一道缺口。
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final Color ink = !enabled
        ? embyMenuInkSecondary
        : (destructive ? embyMenuDanger : embyMenuInk);
    return _MenuPress(
      onTap: enabled ? onTap : null,
      child: Container(
        constraints: const BoxConstraints(minHeight: 44),
        padding: const EdgeInsets.fromLTRB(16, 11, 16, 11),
        decoration: BoxDecoration(
          border: showDivider
              ? const Border(
                  bottom: BorderSide(color: embyMenuLine, width: 0.5),
                )
              : null,
        ),
        child: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 18, color: ink),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: ink,
                      fontSize: 16.5,
                      height: 1.2,
                      // iOS 的正文字距是轻微收紧的，不写这一条看起来会「散」。
                      letterSpacing: -0.2,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                  if (detail != null && detail!.trim().isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      detail!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: embyMenuInkSecondary,
                        fontSize: 12.5,
                        height: 1.3,
                        letterSpacing: -0.1,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null && trailing!.trim().isNotEmpty) ...[
              const SizedBox(width: 10),
              Text(
                trailing!,
                style: TextStyle(
                  color: ink.withValues(alpha: 0.55),
                  fontSize: 14,
                  letterSpacing: -0.1,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
            if (checked) ...[
              const SizedBox(width: 10),
              const Icon(
                Icons.check_rounded,
                size: 18,
                color: embyMenuAccent,
              ),
            ] else if (chevron) ...[
              const SizedBox(width: 8),
              const Icon(
                Icons.chevron_right_rounded,
                size: 16,
                color: embyMenuInkTertiary,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 分组标题。
///
/// 两种形态，对应 iOS 的两种真实用法：
///   * 默认（页面标题）：卡片顶部一行居中的小字，下面一条发丝线 ——
///     iOS 分享面板的头部就是这样；
///   * [inline]（组与组之间）：**左对齐**的小字 + 上方一条发丝线。
///
/// 以前两种都用「整条灰底横幅」，那是 Material 的 section header，iOS 里
/// 没有这个元素——截图里那两块灰条就是它。
class EmbyMenuHeader extends StatelessWidget {
  const EmbyMenuHeader(
    this.label, {
    super.key,
    this.inline = false,
    this.topLine = true,
  });

  final String label;
  final bool inline;

  /// 组标题上面那条发丝线。页面第一组不画——上面已经有页面标题的分隔线了，
  /// 两条贴在一起会变成一条粗线。
  final bool topLine;

  @override
  Widget build(BuildContext context) {
    const TextStyle style = TextStyle(
      color: embyMenuInkSecondary,
      fontSize: 13,
      fontWeight: FontWeight.w400,
      letterSpacing: -0.05,
    );
    if (inline) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (topLine) Container(height: 0.5, color: embyMenuLine),
          Padding(
            padding: EdgeInsets.fromLTRB(16, topLine ? 12 : 10, 16, 4),
            child: Text(label, textAlign: TextAlign.left, style: style),
          ),
        ],
      );
    }
    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: embyMenuLine, width: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
        child: Text(label, textAlign: TextAlign.center, style: style),
      ),
    );
  }
}

/// 只读信息行（媒体信息面板用）。
class EmbyMenuInfoRow extends StatelessWidget {
  const EmbyMenuInfoRow({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 9, 16, 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 62,
            child: Text(
              label,
              style: const TextStyle(
                color: embyMenuInkSecondary,
                fontSize: 12.5,
                height: 1.4,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: const TextStyle(
                color: embyMenuInk,
                fontSize: 13,
                height: 1.4,
                letterSpacing: -0.1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 按下反馈：底色压深一档 + 轻微缩放，比 InkWell 的涟漪更接近 iOS。
class _MenuPress extends StatefulWidget {
  const _MenuPress({required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  State<_MenuPress> createState() => _MenuPressState();
}

class _MenuPressState extends State<_MenuPress> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: widget.onTap == null
          ? null
          : (_) => setState(() => _down = true),
      onTapUp: widget.onTap == null
          ? null
          : (_) => setState(() => _down = false),
      onTapCancel: widget.onTap == null
          ? null
          : () => setState(() => _down = false),
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: Duration(milliseconds: _down ? 80 : 180),
        curve: Curves.easeOut,
        color: _down ? embyMenuPressed : Colors.transparent,
        child: widget.child,
      ),
    );
  }
}

/// 当前打开的菜单控制器。
///
/// 播放器同一时刻只有一个菜单（和 [embyLastAnchor] 一样是单例假设）。二级
/// 跳转走 [EmbyMenuController.push]，在同一张卡片里换页——不再「关掉重开」，
/// 卡片高度也跟着内容平滑过渡，这是 iOS UIMenu 子菜单的样子。
EmbyMenuController? embyMenu;

/// 菜单里的一页。
class EmbyMenuPage {
  const EmbyMenuPage({required this.title, required this.builder});

  final String title;
  final WidgetBuilder builder;
}

class EmbyMenuController extends ChangeNotifier {
  EmbyMenuController(this.root);

  final EmbyMenuPage root;
  final List<EmbyMenuPage> _stack = <EmbyMenuPage>[];

  EmbyMenuPage get current => _stack.isEmpty ? root : _stack.last;

  /// 返回行上要显示的名字（上一页的标题）。
  String? get parentTitle {
    if (_stack.isEmpty) return null;
    return _stack.length == 1 ? root.title : _stack[_stack.length - 2].title;
  }

  bool get canPop => _stack.isNotEmpty;
  int get depth => _stack.length;

  void push(String title, WidgetBuilder builder) {
    _stack.add(EmbyMenuPage(title: title, builder: builder));
    notifyListeners();
  }

  void pop() {
    if (_stack.isEmpty) return;
    _stack.removeLast();
    notifyListeners();
  }
}

/// 最近一次点击的按钮矩形。
///
/// 播放器同一时刻只会有一个菜单，用这个全局记录就够了：按钮在 onTap 里先
/// 把自己写到这儿，紧接着打开面板，面板拿它当锚点。这样 14 个调用点一行
/// 都不用改，也不会出现「菜单从屏幕右边凭空冒出来」。
Rect? embyLastAnchor;

/// 打开一个弹出菜单。
///
/// [anchor] 是触发按钮在屏幕上的矩形，菜单右边缘对齐它、落在它下方；下方
/// 放不下就整体上移。
Future<T?> showEmbyPopover<T>(
  BuildContext context, {
  required Rect anchor,
  required WidgetBuilder builder,
  String? header,
  double width = 272,
}) {
  final Size screen = MediaQuery.sizeOf(context);
  final double maxWidth = (screen.width - 24).clamp(160.0, width);

  // 右边缘贴住按钮；越界就夹回来。
  double left = anchor.right - maxWidth;
  if (left < 12) left = 12;
  if (left + maxWidth > screen.width - 12) {
    left = screen.width - maxWidth - 12;
  }

  // 上下各剩多少空间。菜单只在有空间的那一侧展开，并且**贴着按钮**：
  // 向上展开时用 bottom 定位，内容多高就往上长多高，不会在画面中间飘着。
  final double spaceBelow = screen.height - anchor.bottom - 18;
  final double spaceAbove = anchor.top - 18;
  final bool opensUpward = spaceBelow < 300 && spaceAbove > spaceBelow;
  // 上限不能超过屏幕本身（横屏时 460 会顶出屏幕），内容超了由内部
  // 滚动兜住——选集十几集、更多菜单这类长列表全靠这一条。
  final double maxHeight = (opensUpward ? spaceAbove : spaceBelow).clamp(
    160.0,
    math.min(520.0, screen.height - 96),
  );

  final double? top = opensUpward ? null : anchor.bottom + 8;
  final double? bottom = opensUpward ? (screen.height - anchor.top + 8) : null;

  // 焦点对准离按钮最近的那个角，缩放时看起来是从按钮里「长」出来的。
  final Alignment origin = opensUpward
      ? (left + maxWidth / 2 < anchor.center.dx
            ? Alignment.bottomLeft
            : Alignment.bottomRight)
      : (left + maxWidth / 2 < anchor.center.dx
            ? Alignment.topLeft
            : Alignment.topRight);

  unawaitedHaptic();

  final EmbyMenuController controller = EmbyMenuController(
    EmbyMenuPage(title: header ?? '', builder: builder),
  );
  embyMenu = controller;

  final Future<T?> done = showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: '关闭菜单',
    // iOS 菜单外面只压一点点，不是那种把画面压黑的遮罩。
    barrierColor: const Color(0x14000000),
    transitionDuration: const Duration(milliseconds: 280),
    pageBuilder: (ctx, animation, secondary) {
      return _PopoverHost(
        animation: animation,
        origin: origin,
        left: left,
        top: top,
        bottom: bottom,
        width: maxWidth,
        maxHeight: maxHeight,
        controller: controller,
      );
    },
    transitionBuilder: (ctx, animation, secondary, child) => child,
  );
  // 菜单关掉后把全局引用摘掉，不然下一个面板会误以为自己还在旧菜单里。
  return done.whenComplete(() {
    if (identical(embyMenu, controller)) embyMenu = null;
  });
}

void unawaitedHaptic() {
  // 打开菜单给一次轻触觉；失败无所谓（部分安卓机型没有马达）。
  HapticFeedback.selectionClick();
}

class _PopoverHost extends StatelessWidget {
  const _PopoverHost({
    required this.animation,
    required this.origin,
    required this.left,
    required this.top,
    required this.bottom,
    required this.width,
    required this.maxHeight,
    required this.controller,
  });

  final Animation<double> animation;
  final Alignment origin;
  final double left;
  final double? top;
  final double? bottom;
  final double width;
  final double maxHeight;
  final EmbyMenuController controller;

  @override
  Widget build(BuildContext context) {
    // 展开：先快后慢、轻微过冲（iOS 菜单的 spring 感）；收起：干脆的加速淡出。
    final Animation<double> scale = animation.drive(
      Tween<double>(
        begin: 0.86,
        end: 1,
      ).chain(CurveTween(curve: Curves.easeOutBack)),
    );
    final Animation<double> fade = animation.drive(
      CurveTween(curve: const Interval(0, 0.7, curve: Curves.easeOut)),
    );

    return Stack(
      // 对话框给的是紧约束，这里显式铺满，免得某些平台下 Stack 缩成 0 尺寸。
      fit: StackFit.expand,
      children: [
        Positioned(
          left: left,
          top: top,
          bottom: bottom,
          width: width,
          child: FadeTransition(
            opacity: fade,
            child: ScaleTransition(
              scale: scale,
              alignment: origin,
              child: _MenuCard(controller: controller, maxHeight: maxHeight),
            ),
          ),
        ),
      ],
    );
  }
}

class _MenuCard extends StatelessWidget {
  const _MenuCard({required this.controller, required this.maxHeight});

  final EmbyMenuController controller;
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(_menuRadius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 44,
            spreadRadius: 0,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(_menuRadius),
        // 不做 BackdropFilter：视频是原生纹理，模糊对它无效，只会白掉一层
        // layer 的重绘开销。iOS 菜单的质感靠高不透明度底色 + 强投影就够。
        child: Material(
          color: embyMenuBg,
          child: AnimatedBuilder(
            animation: controller,
            builder: (context, _) {
              final page = controller.current;
              final parentTitle = controller.parentTitle;
              return ConstrainedBox(
                constraints: BoxConstraints(maxHeight: maxHeight),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (parentTitle != null)
                      _MenuBackRow(
                        title: parentTitle,
                        onTap: () {
                          HapticFeedback.selectionClick();
                          controller.pop();
                        },
                      )
                    else if (page.title.isNotEmpty)
                      EmbyMenuHeader(page.title),
                    // 换页：内容轻淡入 + 高度平滑过渡。iOS 的 UIMenu 子页没有
                    // 明显横滑，重点是「高度变的时候卡片不跳」。
                    //
                    // 外面必须包一层可滚动容器：选集 / 更多这类长菜单高度
                    // 超过 maxHeight 时，之前是被直接裁掉（第 6 集之后点不到）。
                    Flexible(
                      child: SingleChildScrollView(
                        physics: const ClampingScrollPhysics(),
                        child: AnimatedSize(
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeOutCubic,
                          alignment: Alignment.topCenter,
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 170),
                            switchInCurve: Curves.easeOut,
                            switchOutCurve: Curves.easeIn,
                            transitionBuilder: (child, anim) => FadeTransition(
                              opacity: anim,
                              child: SlideTransition(
                                position: Tween<Offset>(
                                  begin: const Offset(0, 0.02),
                                  end: Offset.zero,
                                ).animate(anim),
                                child: child,
                              ),
                            ),
                            child: KeyedSubtree(
                              key: ValueKey<int>(controller.depth),
                              child: Builder(builder: page.builder),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// 子页顶部的返回行（对标 iOS 子菜单的「‹ 上一级」）。
class _MenuBackRow extends StatelessWidget {
  const _MenuBackRow({required this.title, required this.onTap});

  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _MenuPress(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 44),
        padding: const EdgeInsets.fromLTRB(10, 10, 16, 10),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: embyMenuLine, width: 0.5)),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.chevron_left_rounded,
              size: 22,
              color: embyMenuAccent,
            ),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: embyMenuAccent,
                  fontSize: 16.5,
                  letterSpacing: -0.2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
