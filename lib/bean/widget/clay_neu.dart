/// 桌面端拟态（Neumorphism）设计层。
///
/// 和 `clay.dart` 的粘土质感是两套东西：粘土靠「左上亮右下暗的渐变」做体积，
/// 拟态靠「底色 + 极浅的双向阴影 + 1px 硬描边」做体积。桌面端大屏、鼠标操作、
/// 内容以卡片墙为主，拟态的层次比粘土更耐看，所以桌面端走这套。
///
/// 参数来自 HTML 预览页里用户手调的那一组：
/// 拟态强度 35% / 阴影偏移 2 / 阴影模糊 4 / 提亮 深色 5%·浅色 0%。
///
/// 三条硬规则（踩过的坑，改之前先看）：
/// 1. 底色必须是中灰，不能是纯黑或纯白——纯黑上阴影完全看不见（OLED 模式
///    下这套直接失效，所以 [NeuTokens.base] 是固定值，不吃主题）。
/// 2. 深影绝不能用近纯黑高饱和色，否则叠在彩色封面上就是一圈脏灰雾；
///    这里统一用低透明度的黑（深色）/ 柔蓝灰（浅色）。
/// 3. 彩色媒体（封面、缩略图、头像）**不参与拟态**，只给 1px 内描边 +
///    极轻投影，见 [NeuMedia]。
library;

import 'package:flutter/material.dart';

import 'package:XL/pages/emby/emby_preview_style.dart';

import 'package:XL/utils/device.dart';

/// 桌面宽屏判定：手机/竖屏一律走原布局，桌面端才切拟态排版。
const double kNeuDesktopWidth = 900;

/// 拟态**样式**是否启用（决定配色、卡片、底部导航长什么样）。
///
/// 和 [isDesktopWideLayout] 是两件事，别混：
/// - 这里只管「外观语言」——手机端也走拟态。
/// - [isDesktopWideLayout] 管「排版密度」——多列、侧栏、页面标题。
///
/// 拆开的原因：手机竖屏不可能用桌面那套侧栏，但拟态这套光影在手机上
/// 一样成立，甚至更合适（小屏元素少，双阴影不会糊）。
bool isNeuLayout(BuildContext context) {
  if (isDesktop()) {
    return MediaQuery.sizeOf(context).width >= kNeuDesktopWidth;
  }
  // 手机端（含平板、横屏）默认全量拟态。
  return true;
}

/// 桌面宽屏排版：多列网格、侧栏、页面标题。
bool isDesktopWideLayout(BuildContext context) =>
    isDesktop() && MediaQuery.sizeOf(context).width >= kNeuDesktopWidth;

/// 页面底色；拟态没启用时返回 `null`，也就是继续沿用主题自己的 scaffold 色。
///
/// 每个 tab 页都有自己的 `Scaffold`，光在壳里铺底色没用，页面得自己跟上。
Color? neuScaffoldBackground(BuildContext context) =>
    isNeuLayout(context) ? NeuTokens.of(context).base : null;

/// 拟态的圆角与间距。
abstract final class NeuRadius {
  /// 卡片、面板。
  static const double card = 22;

  /// 窗口 / 内容区外框。
  static const double window = 26;

  /// 搜索框、分段控件这类小控件。
  static const double control = 14;

  /// 媒体（封面）内圆角。
  static const double media = 14;
}

abstract final class NeuSpacing {
  /// 卡片间距。
  static const double gap = 18;

  /// 内容区四周留白。
  static const double pagePadding = 20;

  /// 桌面端侧栏宽度。
  static const double railWidth = 232;
}

/// 某一亮度下的拟态色板。
///
/// 所有阴影的 alpha 都已经乘过「拟态强度」，所以 [NeuSurface] 不需要再算一遍。
class NeuTokens {
  const NeuTokens({
    required this.base,
    required this.raised,
    required this.recess,
    required this.shadowDark,
    required this.shadowLight,
    required this.insetDark,
    required this.insetLight,
    required this.edgeTop,
    required this.edgeBottom,
    required this.mediaLine,
  });

  /// 拟态强度：0 是干净的现代扁平，1 是完整拟态。用户定在 0.35。
  static const double intensity = 0.35;

  /// 阴影偏移与模糊。之前 7/16 会糊出脏边，这组是用户调过的。
  static const double offset = 2;
  static const double blur = 4;

  /// 页面底色。固定值：拟态必须有中灰底，跟主题的 seed 色无关。
  final Color base;

  /// 凸起面：底色往白提一点（深色 5%，浅色 0%）。
  final Color raised;

  /// 凹陷面：底色往黑压 5%。
  final Color recess;

  /// 凸起方向的背光阴影。
  final Color shadowDark;

  /// 凸起方向的受光阴影。
  final Color shadowLight;

  /// 凹陷的内阴影（背光端）。
  final Color insetDark;

  /// 凹陷的内阴影（受光端）。
  final Color insetLight;

  /// 顶部 1px 硬描边：没有它边缘就是一团模糊，显得廉价。
  final Color edgeTop;

  /// 底部 1px 硬描边。
  final Color edgeBottom;

  /// 彩色媒体的内描边。
  final Color mediaLine;

  static const NeuTokens dark = NeuTokens(
    base: Color(0xFF292C33),
    // 5% 提亮：层次主要靠填色差，阴影只做辅助，这样才不会糊。
    raised: Color(0xFF33363D),
    recess: Color(0xFF272A30),
    // 0.50 * 0.35
    shadowDark: Color(0x2D000000),
    // 0.11 * 0.35
    shadowLight: Color(0x0AFFFFFF),
    insetDark: Color(0x33000000),
    insetLight: Color(0x08FFFFFF),
    edgeTop: Color(0x0EFFFFFF),
    edgeBottom: Color(0x29000000),
    mediaLine: Color(0x14FFFFFF),
  );

  static const NeuTokens light = NeuTokens(
    base: Color(0xFFE8EAF0),
    // 用户原本调的是 0%（凸起面和底色同色），桌面大卡片靠阴影还能撑住，
    // 但手机上底部导航条和 3 列小卡片只有 ~110px 宽，纯靠阴影会「看不见」。
    // 这里给到约 3% 提亮：肉眼能分出「这是块浮起来的板」，又不破坏干净感。
    raised: Color(0xFFEFF1F6),
    recess: Color(0xFFDDDFE5),
    // 柔蓝灰，不能用偏硬的 #C3C9D6，不然会糊出脏边。
    shadowDark: Color(0x3196A1B5),
    shadowLight: Color(0x4CFFFFFF),
    insetDark: Color(0x3896A1B5),
    insetLight: Color(0x3DFFFFFF),
    edgeTop: Color(0x8CFFFFFF),
    edgeBottom: Color(0x0B141828),
    mediaLine: Color(0x99FFFFFF),
  );

  static NeuTokens of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? dark : light;
}

/// 面的形态。
enum NeuMode {
  /// 凸起：卡片、面板、侧栏、按钮。
  raised,

  /// 凹陷：搜索框、分段控件、进度轨、输入框。
  recess,
}

/// 拟态面。
///
/// 凸起用 `BoxShadow` 做双向投影（Flutter 的 `BoxShadow` 没有 inset，
/// 凹陷那半由 [_NeuEdgePainter] 画裁剪后的模糊描边补上）。
class NeuSurface extends StatelessWidget {
  const NeuSurface({
    super.key,
    required this.child,
    this.mode = NeuMode.raised,
    this.radius = NeuRadius.card,
    this.padding,
    this.margin,
    this.width,
    this.height,
    this.hairline = true,
    this.onTap,
  });

  final Widget child;
  final NeuMode mode;

  /// 圆角，默认 [NeuRadius.card]。
  final double radius;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double? width;
  final double? height;

  /// 1px 硬描边。关掉就退回"纯阴影"的老版观感（会糊）。
  final bool hairline;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final bool recess = mode == NeuMode.recess;
    final BorderRadius borderRadius = BorderRadius.circular(radius);

    // Pv 全铺之后这个「拟态面板」只剩一个壳子：凸起 = 一张白卡，
    // 凹陷 = 一层浅灰底。双阴影那套在 Pv 上读起来像脏，换成一档极轻的
    // 投影 + 底色差，视觉上才和旁边的 PvGroup / PvRow 是一家人。
    final Widget content = Container(
      width: width,
      height: height,
      margin: margin,
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        color: recess ? PvColors.searchFill(context) : PvColors.card(context),
        border: recess
            ? null
            : Border.all(
                color: PvColors.isDark(context)
                    ? Colors.white.withValues(alpha: 0.06)
                    : const Color(0x0F000000),
                width: 0.8,
              ),
        boxShadow: recess || !hairline
            ? null
            : const [
                BoxShadow(color: Color(0x0A000000), blurRadius: 6),
              ],
      ),
      clipBehavior: Clip.antiAlias,
      child: padding == null
          ? child
          : Padding(padding: padding!, child: child),
    );

    if (onTap != null) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: content,
      );
    }
    return content;
  }
}

/// 彩色媒体的外框。
///
/// 封面、缩略图、头像一律走这里：**不叠双向阴影**。之前把拟态阴影压在
/// 彩色渐变上，糊出一圈灰雾，问题就出在这。
class NeuMedia extends StatelessWidget {
  const NeuMedia({
    super.key,
    required this.child,
    this.radius = NeuRadius.media,
    this.width,
    this.height,
  });

  final Widget child;
  final double radius;
  final double? width;
  final double? height;

  @override
  Widget build(BuildContext context) {
    final NeuTokens t = NeuTokens.of(context);
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: t.mediaLine, width: 1),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.22),
            offset: const Offset(0, 1),
            blurRadius: 3,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: child,
      ),
    );
  }
}

/// 拟态分段控件：凹陷轨道 + 滑动的凸起指示条。
///
/// 指示条是"移动"而不是"重绘"——用 [AnimatedPositioned] 走位，
/// 切页签时不会有闪烁。
class NeuSegmented<T> extends StatelessWidget {
  const NeuSegmented({
    super.key,
    required this.segments,
    required this.value,
    required this.onChanged,
    this.height = 38,
  });

  /// 顺序即显示顺序，key 是值，value 是标签。
  final Map<T, String> segments;
  final T value;
  final ValueChanged<T> onChanged;
  final double height;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final List<T> keys = segments.keys.toList(growable: false);
    final int index = keys.indexOf(value);
    final int selected = index < 0 ? 0 : index;
    const Duration duration = Duration(milliseconds: 260);

    return NeuSurface(
      mode: NeuMode.recess,
      radius: height / 2,
      padding: const EdgeInsets.all(4),
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final double itemWidth =
              (constraints.maxWidth - 8) / keys.length;
          return SizedBox(
            height: height - 8,
            child: Stack(
              children: <Widget>[
                AnimatedPositioned(
                  duration: duration,
                  curve: Curves.easeOutCubic,
                  left: 4 + itemWidth * selected,
                  top: 0,
                  bottom: 0,
                  width: itemWidth,
                  child: NeuSurface(
                    radius: (height - 8) / 2,
                    child: const SizedBox.expand(),
                  ),
                ),
                Row(
                  children: keys.map((T key) {
                    final bool on = key == keys[selected];
                    return Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => onChanged(key),
                        child: Center(
                          child: AnimatedDefaultTextStyle(
                            duration: duration,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight:
                                  on ? FontWeight.w600 : FontWeight.w400,
                              color: on
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.onSurfaceVariant,
                            ),
                            child: Text(segments[key]!),
                          ),
                        ),
                      ),
                    );
                  }).toList(growable: false),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// 拟态进度轨：凹陷轨道 + 强调色填充。
class NeuProgress extends StatelessWidget {
  const NeuProgress({
    super.key,
    required this.value,
    this.height = 6,
    this.trackColor,
    this.fillColor,
  }) : assert(value >= 0 && value <= 1);

  final double value;
  final double height;
  final Color? trackColor;
  final Color? fillColor;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return NeuSurface(
      mode: NeuMode.recess,
      radius: height / 2,
      height: height,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          return Align(
            alignment: Alignment.centerLeft,
            child: Container(
              width: constraints.maxWidth * value,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(height / 2),
                gradient: LinearGradient(
                  colors: <Color>[
                    fillColor ?? theme.colorScheme.primary,
                    (fillColor ?? theme.colorScheme.primary).withValues(
                      alpha: 0.72,
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
