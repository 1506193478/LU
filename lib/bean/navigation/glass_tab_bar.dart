import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import 'package:XL/utils/immersive_theme.dart';
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
/// 形态照 Rex 的 `GlassDockBarView`：**一整条胶囊**浮在内容之上，
/// 内容从它下面滚过去。区别是这里没有用「贴边全宽 + 小圆角」，
/// 而是真的做成胶囊——圆角取高度的一半，两侧各留 20，
/// 看上去是浮起来的一颗药丸，不是一条色带。
///
/// 玻璃感靠三样东西叠出来，缺一样就变成一块灰板：
/// 1. `BackdropFilter` 高斯模糊（只留一层，外面套 RepaintBoundary）
/// 2. 很淡的底色（浅色 40% 白 / 深色 45% 黑），让背后的内容透上来
/// 3. 1px 高光描边 + 一点外投影，撑出厚度
///
/// 选中项是一颗更小的胶囊 + 强调色，图标和文字一起变色（Rex 就是这样，
/// 不给图标做额外填充）。
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

  static const double height = immersiveTabBarHeight;

  /// 胶囊两端离屏幕边缘的距离。预览稿 `.dock` 是 `left:14;right:14`。
  static const double _sideMargin = 14;

  /// 离屏距离统一走 [immersiveTabBarGap]，别再各自写死。
  static const double _bottomGap = immersiveTabBarGap;

  /// 胶囊半径 = 高度的一半，这是"胶囊"的定义。
  static const double _radius = height / 2;

  /// 内容区需要给导航条留出的高度，页面底部留白可以直接引用。
  static double reservedHeight(BuildContext context) =>
      immersiveTabBarInset(context);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    final bool reduceMotion = KazumiMotion.reduceMotion(context);
    final double bottomInset = MediaQuery.paddingOf(context).bottom;

    // 底色刻意压得很淡：玻璃要能看见后面在动，太实就成了普通色带。
    // 预览稿 `.dock` 底色是 rgba(255,255,255,.62)。
    // 底色再叠一层渐变（左上亮、右下滑）：纯色玻璃看起来是「一块板」，
    // 有渐变才像材质。深色额外垫一层暗底，否则光球透上来会变成彩色玻璃片。
    final Color surfaceTint = dark
        ? const Color(0x800A0C12)
        : const Color(0xFFFFFFFF).withValues(alpha: 0.62);
    final LinearGradient surfaceGradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: dark
          ? const <Color>[Color(0x2BFFFFFF), Color(0x0DFFFFFF)]
          : const <Color>[Color(0xC2FFFFFF), Color(0x75FFFFFF)],
    );
    final Color highlight = dark
        ? Colors.white.withValues(alpha: 0.22)
        : Colors.white.withValues(alpha: 0.92);
    // 选中胶囊：一块更小的玻璃，不是一层半透明色块。
    final Color indicatorFill = dark
        ? Colors.white.withValues(alpha: 0.15)
        : Colors.white.withValues(alpha: 0.62);
    final Color indicatorEdge = dark
        ? Colors.white.withValues(alpha: 0.18)
        : Colors.white.withValues(alpha: 0.95);

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
                    borderRadius: BorderRadius.circular(_radius),
                    boxShadow: [
                      // 胶囊浮起来要有一圈"落地"的暗边，但别重到压住内容。
                      BoxShadow(
                        color: Colors.black.withValues(
                          alpha: dark ? 0.46 : 0.12,
                        ),
                        blurRadius: 26,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(_radius),
                    child: BackdropFilter(
                      // 预览稿是 `blur(30px) saturate(180%)`；当前 Flutter
                      // 版本没有 colorFilter 滤镜构造，先只做 blur(30)，
                      // 饱和度差异靠底色 alpha 补偿。
                      filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: surfaceTint,
                          gradient: surfaceGradient,
                          borderRadius: BorderRadius.circular(_radius),
                          // 只留顶部 1px 高光。整圈描边是「贴图上的框」，
                          // 真实材质的边是上面受光、下面背光。
                          border: Border(
                            top: BorderSide(color: highlight, width: 0.8),
                          ),
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
                    const double inset = 7;
                    return Stack(
                      children: [
                        AnimatedPositioned(
                          duration: reduceMotion
                              ? Duration.zero
                              : KazumiMotion.slow,
                          curve: KazumiMotion.spring,
                          left: slot * selectedIndex + inset,
                          top: 6,
                          bottom: 6,
                          width: slot - inset * 2,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: indicatorFill,
                              borderRadius: BorderRadius.circular(
                                (_radius - 6).clamp(0, double.infinity),
                              ),
                              border: Border(
                                top: BorderSide(
                                  color: indicatorEdge,
                                  width: 0.8,
                                ),
                              ),
                              boxShadow: <BoxShadow>[
                                BoxShadow(
                                  color: Colors.black.withValues(
                                    alpha: dark ? 0.30 : 0.06,
                                  ),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
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
                                    // 触觉只在 [_selectDestination] 里发一次。
                                    // 这里以前也发一次，于是点一下 tab 会连着
                                    // 震两下（selectionClick 两次），手感就是
                                    // 「点一下、抖两下」。
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
    // 选中态用系统蓝（iOS tab bar 的 tintColor 就是它）。
    // 原来是偏灰的 #3A5680，在玻璃底上几乎和未选中分不开。
    final Color activeColor =
        dark ? const Color(0xFF0A84FF) : const Color(0xFF007AFF);
    const Color inactiveColor = Color(0xFF8E8E93);
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
            AnimatedScale(
              duration: duration,
              curve: KazumiMotion.spring,
              scale: selected ? 1.06 : 1.0,
              child: Icon(
                selected ? item.selectedIcon : item.icon,
                size: 21,
                color: selected ? activeColor : inactiveColor,
              ),
            ),
            const SizedBox(height: 3),
            // 字重固定 w500，只让颜色动。
            //
            // 原来选中态是 w500、未选中 w400，交给 AnimatedDefaultTextStyle
            // 去插值 —— 但 FontWeight 是能逐级 lerp 的，于是 240ms 里文字
            // 每一帧都在 w400→w500 之间重新排版：一是字形宽度跟着变，标签
            // 会左右轻微抖动；二是每帧都要重新做一次文字 shaping。选中态
            // 已经有胶囊底、缩放和颜色三重提示，字重这点差别不值这个代价。
            AnimatedDefaultTextStyle(
              duration: duration,
              curve: KazumiMotion.standard,
              style: TextStyle(
                fontSize: 10.5,
                height: 1.05,
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
