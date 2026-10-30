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
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: surfaceTint,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: highlight, width: 0.5),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: dark ? 0.5 : 0.12),
                    blurRadius: 40,
                    offset: const Offset(0, 14),
                  ),
                ],
              ),
              child: SizedBox(
                height: height,
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
            ),
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
            AnimatedDefaultTextStyle(
              duration: duration,
              curve: KazumiMotion.standard,
              style: TextStyle(
                fontSize: 11,
                height: 1.1,
                fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
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
