import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import 'package:XL/utils/motion.dart';

/// 一个导航目标。
class KazumiTabItem {
  const KazumiTabItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

/// 悬浮玻璃导航条。
///
/// 这是整个界面里唯一常驻的"玻璃"元素（方案 A 的点缀）：内容从它下面
/// 滚过去，模糊 + 1px 高光边 + 投影叠出厚度感；选中指示器用带过冲的曲线
/// 滑过去，而不是直接跳。
///
/// 性能上只保留**一层** BackdropFilter，外面套 RepaintBoundary，
/// 避免每帧重绘整页。
class KazumiTabBar extends StatelessWidget {
  const KazumiTabBar({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<KazumiTabItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  static const double height = 66;
  static const double _sideMargin = 14;
  static const double _bottomGap = 14;

  /// 内容区需要给导航条留出的高度，页面底部留白可以直接引用。
  static double reservedHeight(BuildContext context) =>
      height + _bottomGap + MediaQuery.paddingOf(context).bottom;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    final bool reduceMotion = KazumiMotion.reduceMotion(context);
    final double bottomInset = MediaQuery.paddingOf(context).bottom;

    final Color surfaceTint = dark
        ? const Color(0xFF16181E).withValues(alpha: 0.58)
        : const Color(0xFFFFFFFF).withValues(alpha: 0.62);
    final Color highlight =
        dark ? Colors.white.withValues(alpha: 0.14) : Colors.black.withValues(alpha: 0.06);
    final Color indicatorFill = dark
        ? Colors.white.withValues(alpha: 0.09)
        : Colors.black.withValues(alpha: 0.055);

    return Padding(
      padding: EdgeInsets.fromLTRB(
        _sideMargin,
        0,
        _sideMargin,
        _bottomGap + bottomInset,
      ),
      child: RepaintBoundary(
        child: SizedBox(
          height: height,
          child: Stack(
            // 必须关掉裁剪：Stack 默认 Clip.hardEdge，会把下面那层
            // 外扩 40px 的投影重新切掉，等于白改。
            clipBehavior: Clip.none,
            children: [
              // 静态模糊底：投影、裁剪、模糊都在这一层，不含任何动画子节点。
              //
              // 两处修正：
              // 1. boxShadow 必须放在 ClipRRect **外面**。原来它在 ClipRRect
              //    里面，同一个圆角把外扩的投影整块裁掉了 —— 下面留的那 14px
              //    空白等于白留，浮起来的厚度感其实一直没画出来。
              // 2. 选中指示器不能再待在 BackdropFilter 子树里。它每帧都在动，
              //    只要它在模糊层内部，sigma=24 的高斯模糊就得跟着每帧重算，
              //    低端机上切 tab 会明显掉帧。挪出来之后这层是完全静态的，
              //    合成器可以整块缓存。
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      // 投影原来一直被裁掉，等于没画；补回来之后按"能看出浮起
                      // 但压不住内容"的力度调：28px 模糊、10px 下沉。
                      // 觉得还重就把 blurRadius 往下调（20 左右基本只剩一圈淡影）。
                      BoxShadow(
                        color: Colors.black.withValues(alpha: dark ? 0.42 : 0.10),
                        blurRadius: 28,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: surfaceTint,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: highlight, width: 0.5),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              // 动画层：指示器 + 按钮，全部在模糊层之上。
              Positioned.fill(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    // 每个 tab 的槽位宽度：整条等分。
                    //
                    // 原来算的是 `(maxWidth - innerPadding * 2) / n`，
                    // 但这条栏外面并没有 padding，等于凭空减掉 12px；
                    // 再叠加 `left: innerPadding + ...`，指示器就整体右移
                    // 约 5px，越靠右的 tab 偏得越多（第 5 个左偏 5px）。
                    // 现在按真实槽位算，指示器用固定内缩量居中。
                    final double slot = constraints.maxWidth / items.length;
                    return Stack(
                      children: [
                        AnimatedPositioned(
                          duration: reduceMotion
                              ? Duration.zero
                              : KazumiMotion.slow,
                          curve: KazumiMotion.spring,
                          left: slot * selectedIndex + 4,
                          top: 6,
                          bottom: 6,
                          width: slot - 8,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: indicatorFill,
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                color: highlight,
                                width: 0.5,
                              ),
                            ),
                          ),
                        ),
                        Row(
                          children: [
                            for (var index = 0; index < items.length; index++)
                              Expanded(
                                child: _TabButton(
                                  item: items[index],
                                  selected: index == selectedIndex,
                                  onTap: () {
                                    if (index == selectedIndex) return;
                                    KazumiHaptics.select();
                                    onSelected(index);
                                  },
                                ),
                              ),
                          ],
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final KazumiTabItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    final Color activeColor = theme.colorScheme.onSurface;
    final Color inactiveColor = dark
        ? Colors.white.withValues(alpha: 0.42)
        : Colors.black.withValues(alpha: 0.38);
    final Duration duration = KazumiMotion.scale(context, KazumiMotion.base);

    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedSlide(
              duration: duration,
              curve: KazumiMotion.spring,
              offset: Offset(0, selected ? -0.08 : 0),
              child: AnimatedScale(
                duration: duration,
                curve: KazumiMotion.spring,
                scale: selected ? 1.08 : 1.0,
                child: Icon(
                  selected ? item.selectedIcon : item.icon,
                  size: 19,
                  color: selected ? activeColor : inactiveColor,
                ),
              ),
            ),
            const SizedBox(height: 4),
            // 字重固定 w500，只让颜色动。
            //
            // 原来选中态是 w500、未选中 w400，交给 AnimatedDefaultTextStyle
            // 去插值 —— 但 FontWeight 是能逐级 lerp 的，于是 240ms 里文字
            // 每一帧都在 w400→w500 之间重新排版：一是字形宽度跟着变，标签
            // 会左右轻微抖动；二是每帧都要重新做一次文字 shaping。选中态
            // 已经有色块、缩放和颜色三重提示，字重这点差别不值这个代价。
            AnimatedDefaultTextStyle(
              duration: duration,
              curve: KazumiMotion.standard,
              style: TextStyle(
                fontSize: 11,
                height: 1.1,
                fontWeight: FontWeight.w500,
                color: selected ? activeColor : inactiveColor,
              ),
              child: Text(item.label),
            ),
          ],
        ),
      ),
    );
  }
}
