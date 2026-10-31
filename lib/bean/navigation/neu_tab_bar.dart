import 'package:flutter/material.dart';

import 'package:XL/bean/navigation/glass_tab_bar.dart';
import 'package:XL/bean/widget/clay_neu.dart';
import 'package:XL/bean/widget/pressable.dart';
import 'package:XL/utils/immersive_theme.dart';
import 'package:XL/utils/motion.dart';

/// 手机端拟态底部导航。
///
/// 和 [KazumiTabBar]（悬浮玻璃条）是同一位置的两种语言：
/// 玻璃靠「模糊 + 高光边」，拟态靠「凸起面板 + 凹槽选中」。
///
/// 尺寸刻意和玻璃条保持一致（66 高 / 14 间距 / 14 边距），
/// 这样页面里的 `immersiveTabBarInset()` 不用改，底部留白不会错位。
///
/// 一条硬约束：**面板本身**必须是实色的。拟态是「同一块材料上压出来的
/// 凸起」，面板内部如果透出内容，光影逻辑立刻崩。
///
/// 但面板**外面**那圈（左右各 14、下方 gap + 安全区）不能再铺一层整条宽的
/// 实色底了。原来这里套了个全宽 `ColoredBox`，结果是内容滚到底部时被整块
/// 挡死，屏幕最下方留下一条和页面底色略有差异的横带 —— 也就是「底栏旁边
/// 那块空白很突兀」。去掉之后面板照样浮着，内容能从左右留白和下方穿过去。
class NeuTabBar extends StatelessWidget {
  const NeuTabBar({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<KazumiTabItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  /// 与 [KazumiTabBar.height] 对齐。
  static const double height = immersiveTabBarHeight;
  static const double _sideMargin = 14;

  /// 与玻璃条共用同一个离屏距离。
  static const double _bottomGap = immersiveTabBarGap;
  static const double _innerPadding = 6;

  @override
  Widget build(BuildContext context) {
    final double bottomInset = MediaQuery.paddingOf(context).bottom;
    final Duration duration = KazumiMotion.scale(context, KazumiMotion.base);

    return Padding(
      padding: EdgeInsets.fromLTRB(
        _sideMargin,
        0,
        _sideMargin,
        _bottomGap + bottomInset,
      ),
      child: NeuSurface(
        radius: 24,
        height: height,
        padding: const EdgeInsets.all(_innerPadding),
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            // constraints 已经是 NeuSurface 去掉 padding 之后的宽度，
            // 所以槽位直接等分，不能再减一次 _innerPadding（原来多减了 12px，
            // 指示器比槽位窄 2.4px，越靠右的项偏得越多）。
            final double slot = constraints.maxWidth / items.length;
            return SizedBox(
              height: height - _innerPadding * 2,
              child: Stack(
                children: <Widget>[
                  // 选中项是一块「压进去」的凹槽，跟着手指滑动。
                  AnimatedPositioned(
                    duration: duration,
                    curve: KazumiMotion.spring,
                    left: slot * selectedIndex + 4,
                    top: 2,
                    bottom: 2,
                    width: slot - 8,
                    child: const NeuSurface(
                      mode: NeuMode.recess,
                      radius: 18,
                      child: SizedBox.expand(),
                    ),
                  ),
                  Row(
                    children: <Widget>[
                      for (int index = 0; index < items.length; index++)
                        Expanded(
                          child: _NeuTabButton(
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
              ),
            );
          },
        ),
      ),
    );
  }
}

class _NeuTabButton extends StatelessWidget {
  const _NeuTabButton({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final KazumiTabItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color active = theme.colorScheme.primary;
    final Color inactive = theme.colorScheme.onSurfaceVariant;
    final Duration duration = KazumiMotion.scale(context, KazumiMotion.base);

    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      excludeSemantics: true,
      child: Pressable(
        haptic: false,
        pressedScale: 0.96,
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            AnimatedScale(
              duration: duration,
              curve: KazumiMotion.spring,
              scale: selected ? 1.06 : 1.0,
              child: Icon(
                selected ? item.selectedIcon : item.icon,
                size: 20,
                color: selected ? active : inactive,
              ),
            ),
            const SizedBox(height: 3),
            // 同玻璃导航条：字重固定，只动颜色。FontWeight 会被逐级 lerp，
            // 选中切换时文字每帧重排一次，标签宽度跟着变，看着会抖。
            AnimatedDefaultTextStyle(
              duration: duration,
              curve: KazumiMotion.standard,
              style: TextStyle(
                fontSize: 11,
                height: 1.1,
                fontWeight: FontWeight.w500,
                color: selected ? active : inactive,
              ),
              child: Text(item.label),
            ),
          ],
        ),
      ),
    );
  }
}
