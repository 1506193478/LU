/// Rex 设计系统
///
/// 逆向自 Rex 1.0.2 (b4) 的 `RexDesign` 模块。原始实现是 SwiftUI + UIKit，
/// 这里把它还原成 Flutter 的一套 token 和基础组件，供新页面直接复用。
///
/// 依据（都来自 IPA 里的符号与源文件名，不是猜的）：
///   * `RexDesign/SurfaceStyles.swift` —— 表面材质
///   * `RexDesign/PressScale.swift` / `PressShadow.swift` —— 按压动效
///   * `RexDesign/SheetDetentBackground.swift` —— 抽屉背景
///   * `RexDesign/CellPlate.swift` / `ListPlate.swift` / `ProcessPlate.swift` —— 卡片 / 列表 / 进度
///   * 语义色属性名：`canvasFill` / `inkPrimary` / `inkSecondary` / `surface` / `pillBackground`
///   * 圆角属性名：`cardCornerRadius` / `posterCornerRadius` / `badgeCornerRadius`
///   * 排版属性名：`headerPrimaryText` / `headerSecondaryText`
///
/// 设计取向：**黑白为骨、彩色为氛**。界面本身几乎不出现彩色，颜色只从
/// 封面 / 背景图里透出来（Rex 的 `MediaDetailsTintExtractor`、`ShelfCoverTintCache`
/// 就是干这个的），所以这里的表面色都是中性灰阶，强调色留给「当前状态」。
library;

import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';


/// 语义色板。
///
/// 命名沿用 Rex 的 `canvasFill` / `inkPrimary` / `surface` / `pillBackground`，
/// 读代码时能直接对上原设计稿。
class RexPalette {
  const RexPalette({
    required this.canvas,
    required this.surface,
    required this.surfaceRaised,
    required this.surfaceSunken,
    required this.inkPrimary,
    required this.inkSecondary,
    required this.inkTertiary,
    required this.inkInverse,
    required this.hairline,
    required this.hairlineStrong,
    required this.pill,
    required this.pillBorder,
    required this.scrim,
    required this.accent,
    required this.accentInk,
    required this.danger,
    required this.isDark,
  });

  /// 页面底色。
  final Color canvas;

  /// 卡片 / 分组块。
  final Color surface;

  /// 浮在卡片之上的层（弹窗、悬浮条）。
  final Color surfaceRaised;

  /// 比 canvas 更沉一档的凹槽（进度轨、输入框）。
  final Color surfaceSunken;

  final Color inkPrimary;
  final Color inkSecondary;
  final Color inkTertiary;

  /// 压在 [inkPrimary] 上的反色文字。
  final Color inkInverse;

  /// 1px 分隔线。
  final Color hairline;

  /// 需要更明显一点的分隔线 / 描边。
  final Color hairlineStrong;

  /// 胶囊按钮底色（半透明，配合毛玻璃）。
  final Color pill;
  final Color pillBorder;

  /// 遮罩。
  final Color scrim;

  /// 强调色：只用于「当前选中 / 正在播放 / 主操作」。
  final Color accent;
  final Color accentInk;

  final Color danger;

  final bool isDark;

  static const RexPalette light = RexPalette(
    canvas: Color(0xFFF4F3F6),
    surface: Color(0xFFFFFFFF),
    surfaceRaised: Color(0xFFFFFFFF),
    surfaceSunken: Color(0xFFE9E8ED),
    inkPrimary: Color(0xFF1A1A1C),
    inkSecondary: Color(0xFF6B6B73),
    inkTertiary: Color(0xFF9C9CA5),
    inkInverse: Color(0xFFF7F7F9),
    hairline: Color(0x14000000),
    hairlineStrong: Color(0x24000000),
    pill: Color(0xE6FFFFFF),
    pillBorder: Color(0x1A000000),
    scrim: Color(0x66000000),
    accent: Color(0xFF1A1A1C),
    accentInk: Color(0xFFFFFFFF),
    danger: Color(0xFFD14343),
    isDark: false,
  );

  static const RexPalette dark = RexPalette(
    canvas: Color(0xFF0A0A0C),
    surface: Color(0xFF16161A),
    surfaceRaised: Color(0xFF1F1F24),
    surfaceSunken: Color(0xFF232329),
    inkPrimary: Color(0xFFF4F4F7),
    inkSecondary: Color(0xFFA2A2AC),
    inkTertiary: Color(0xFF6E6E78),
    inkInverse: Color(0xFF101013),
    hairline: Color(0x1FFFFFFF),
    hairlineStrong: Color(0x33FFFFFF),
    pill: Color(0xB31F1F24),
    pillBorder: Color(0x24FFFFFF),
    scrim: Color(0x99000000),
    accent: Color(0xFFF4F4F7),
    accentInk: Color(0xFF101013),
    danger: Color(0xFFE06666),
    isDark: true,
  );

  /// 取当前主题的色板。
  ///
  /// 强调色跟随 LU 的主题色（用户可在设置里换），其余保持中性 ——
  /// Rex 原版的强调色是黑白，但那样用户换主题色就没反应了，
  /// 这里让 accent 走 `colorScheme.primary`，只在对比度不够时才退回黑白。
  static RexPalette of(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool darkMode = theme.brightness == Brightness.dark;
    final RexPalette base = darkMode ? RexPalette.dark : RexPalette.light;

    final Color seed = theme.colorScheme.primary;
    // 强调色要求：在 canvas 上至少 3:1，否则当按钮底色会糊。
    final double contrast = _contrast(seed, base.canvas);
    if (contrast < 3.0) return base;

    return RexPalette(
      canvas: base.canvas,
      surface: base.surface,
      surfaceRaised: base.surfaceRaised,
      surfaceSunken: base.surfaceSunken,
      inkPrimary: base.inkPrimary,
      inkSecondary: base.inkSecondary,
      inkTertiary: base.inkTertiary,
      inkInverse: base.inkInverse,
      hairline: base.hairline,
      hairlineStrong: base.hairlineStrong,
      pill: base.pill,
      pillBorder: base.pillBorder,
      scrim: base.scrim,
      accent: seed,
      accentInk: seed.computeLuminance() > 0.45
          ? const Color(0xFF101013)
          : Colors.white,
      danger: base.danger,
      isDark: base.isDark,
    );
  }

  static double _contrast(Color a, Color b) {
    final double la = a.computeLuminance();
    final double lb = b.computeLuminance();
    final double hi = la > lb ? la : lb;
    final double lo = la > lb ? lb : la;
    return (hi + 0.05) / (lo + 0.05);
  }
}

/// 圆角。
///
/// Rex 的属性名是 `cardCornerRadius` / `posterCornerRadius` / `badgeCornerRadius`，
/// 三者不是随手给的三个数，是「容器 / 图像 / 标签」三档。
class RexRadius {
  const RexRadius._();

  /// 海报、剧照这类图像。
  static const double poster = 12;

  /// 卡片、分组块。
  static const double card = 18;

  /// 大容器：横幅、主视觉。
  static const double hero = 22;

  /// 小标签、徽章。
  static const double badge = 6;

  /// 输入框、小按钮。
  static const double control = 12;

  /// 抽屉顶部。
  static const double sheet = 28;

  /// 胶囊。
  static const double pill = 999;
}

/// 间距。4 的倍数，只用这几档。
class RexSpace {
  const RexSpace._();

  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 20;
  static const double xl = 24;
  static const double xxl = 32;
  static const double huge = 44;

  /// 页面左右安全边距。
  static const double page = 20;

  /// 滑轨卡片之间的间隔。
  static const double rail = 12;
}

/// 排版。
///
/// Rex 的层级很少：大标题 / 区块标题 / 正文 / 说明 / 标签，五档。
/// 字重只用 400 / 500 / 600 / 700 四个，不用 300。
class RexText {
  const RexText._();

  static const TextStyle display = TextStyle(
    fontSize: 30,
    height: 1.18,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.6,
  );

  static const TextStyle title = TextStyle(
    fontSize: 22,
    height: 1.24,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.3,
  );

  static const TextStyle headline = TextStyle(
    fontSize: 17,
    height: 1.3,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.1,
  );

  static const TextStyle body = TextStyle(
    fontSize: 15,
    height: 1.42,
    fontWeight: FontWeight.w400,
  );

  static const TextStyle bodyStrong = TextStyle(
    fontSize: 15,
    height: 1.42,
    fontWeight: FontWeight.w500,
  );

  static const TextStyle caption = TextStyle(
    fontSize: 13,
    height: 1.35,
    fontWeight: FontWeight.w400,
  );

  static const TextStyle label = TextStyle(
    fontSize: 12,
    height: 1.25,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.2,
  );

  static const TextStyle micro = TextStyle(
    fontSize: 11,
    height: 1.2,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.3,
  );
}

/// 毛玻璃容器。
///
/// 对应 Rex 的 `SurfaceStyles` / `appliedGlassRadius`：半透明底 + 背景模糊 +
/// 一道极细的高光边。桌面端（Windows）`BackdropFilter` 会走软件回退，
/// 所以模糊半径给得克制（18），并且允许关掉。
class RexGlass extends StatelessWidget {
  const RexGlass({
    super.key,
    required this.child,
    this.radius = RexRadius.card,
    this.padding,
    this.blur = 18,
    this.tint,
    this.border = true,
    this.enabled = true,
  });

  final Widget child;
  final double radius;
  final EdgeInsetsGeometry? padding;
  final double blur;
  final Color? tint;
  final bool border;

  /// 关掉模糊，只留半透明底（低性能设备 / 大面积滚动时用）。
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final RexPalette p = RexPalette.of(context);
    final BorderRadius br = BorderRadius.circular(radius);

    Widget body = DecoratedBox(
      decoration: BoxDecoration(
        color: tint ?? p.pill,
        borderRadius: br,
        border: border ? Border.all(color: p.pillBorder, width: 1) : null,
      ),
      child: padding == null ? child : Padding(padding: padding!, child: child),
    );

    if (enabled && blur > 0) {
      body = ClipRRect(
        borderRadius: br,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: body,
        ),
      );
    } else {
      body = ClipRRect(borderRadius: br, child: body);
    }

    return body;
  }
}

/// 按压缩放。
///
/// Rex 的 `PressScale`：按下缩到 0.97 并轻微提亮，松开回弹。
/// 这是它「手感」的主要来源，比 Material 的水波纹安静得多。
class RexPressable extends StatefulWidget {
  const RexPressable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.scale = 0.97,
    this.hoverLift = 0,
    this.cursor,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double scale;

  /// 鼠标悬停时上浮的像素（桌面端用，0 表示不动）。
  final double hoverLift;

  final MouseCursor? cursor;

  @override
  State<RexPressable> createState() => _RexPressableState();
}

class _RexPressableState extends State<RexPressable> {
  bool _down = false;
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final bool enabled = widget.onTap != null || widget.onLongPress != null;
    return MouseRegion(
      cursor: enabled
          ? (widget.cursor ?? SystemMouseCursors.click)
          : MouseCursor.defer,
      onEnter: (_) {
        if (widget.hoverLift != 0) setState(() => _hover = true);
      },
      onExit: (_) {
        if (_hover) setState(() => _hover = false);
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => setState(() => _down = true) : null,
        onTapCancel: enabled ? () => setState(() => _down = false) : null,
        onTapUp: enabled ? (_) => setState(() => _down = false) : null,
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        child: AnimatedScale(
          scale: _down ? widget.scale : 1.0,
          duration: const Duration(milliseconds: 110),
          curve: Curves.easeOutCubic,
          child: AnimatedSlide(
            offset: _hover && !_down
                ? Offset(0, -widget.hoverLift / 40)
                : Offset.zero,
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOutCubic,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

/// 胶囊按钮。
///
/// Rex 里所有「一行里的操作」都是这个形态：半透明底 + 图标 + 可选文字。
class RexPillButton extends StatelessWidget {
  const RexPillButton({
    super.key,
    required this.label,
    this.icon,
    this.onTap,
    this.selected = false,
    this.dense = false,
    this.trailing,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool selected;
  final bool dense;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final RexPalette p = RexPalette.of(context);
    final Color fg = selected ? p.accentInk : p.inkPrimary;
    return RexPressable(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: EdgeInsets.symmetric(
          horizontal: dense ? 12 : 14,
          vertical: dense ? 7 : 9,
        ),
        decoration: BoxDecoration(
          color: selected ? p.accent : p.surfaceSunken,
          borderRadius: BorderRadius.circular(RexRadius.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: dense ? 14 : 16, color: fg),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: (dense ? RexText.label : RexText.caption).copyWith(
                color: fg,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 6), trailing!],
          ],
        ),
      ),
    );
  }
}

/// 圆形图标按钮（播放器顶栏、卡片角上的那种）。
class RexIconButton extends StatelessWidget {
  const RexIconButton({
    super.key,
    required this.icon,
    this.onTap,
    this.size = 40,
    this.iconSize = 20,
    this.glass = true,
    this.tooltip,
    this.color,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final double size;
  final double iconSize;
  final bool glass;
  final String? tooltip;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final RexPalette p = RexPalette.of(context);
    final Widget button = RexPressable(
      onTap: onTap,
      scale: 0.92,
      child: SizedBox(
        width: size,
        height: size,
        child: DecoratedBox(
          decoration: BoxDecoration(
            // 玻璃按钮：渐变填充 + 极淡投影，**不描边**。
            //
            // 原来这里是 `pill` 实底 + 1px `pillBorder` 描边，画出来是一个
            // 「描了线的圆」——真实材质靠的是内部光衰和一层投影，一旦描边
            // 就变成贴图上的图形。深色下也不能用纯色，压在海报上会显平。
            gradient: glass
                ? LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: p.isDark
                        ? const [Color(0x40FFFFFF), Color(0x14FFFFFF)]
                        : const [Color(0xF2FFFFFF), Color(0xD9FFFFFF)],
                  )
                : null,
            shape: BoxShape.circle,
            boxShadow: glass
                ? const [
                    BoxShadow(
                      color: Color(0x14141E32),
                      blurRadius: 10,
                      offset: Offset(0, 3),
                    ),
                  ]
                : null,
          ),
          child: Center(
            child: Icon(icon, size: iconSize, color: color ?? p.inkPrimary),
          ),
        ),
      ),
    );
    if (tooltip == null) return button;
    return Tooltip(message: tooltip!, child: button);
  }
}

/// 卡片容器。
class RexCard extends StatelessWidget {
  const RexCard({
    super.key,
    required this.child,
    this.padding,
    this.radius = RexRadius.card,
    this.color,
    this.border = false,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final double radius;
  final Color? color;
  final bool border;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final RexPalette p = RexPalette.of(context);
    final Widget card = DecoratedBox(
      decoration: BoxDecoration(
        color: color ?? p.surface,
        borderRadius: BorderRadius.circular(radius),
        border: border ? Border.all(color: p.hairline, width: 1) : null,
      ),
      child: padding == null ? child : Padding(padding: padding!, child: child),
    );
    if (onTap == null) return card;
    return RexPressable(onTap: onTap, child: card);
  }
}

/// 分区标题：左侧标题 + 可选副标题 + 右侧「查看全部」。
class RexSectionHeader extends StatelessWidget {
  const RexSectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.onSeeAll,
    this.seeAllLabel = '查看全部',
    this.padding = const EdgeInsets.fromLTRB(
      RexSpace.page,
      RexSpace.xl,
      RexSpace.page,
      RexSpace.sm,
    ),
  });

  final String title;
  final String? subtitle;
  final VoidCallback? onSeeAll;
  final String seeAllLabel;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final RexPalette p = RexPalette.of(context);
    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, style: RexText.headline.copyWith(color: p.inkPrimary)),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: RexText.caption.copyWith(color: p.inkSecondary),
                  ),
                ],
              ],
            ),
          ),
          if (onSeeAll != null)
            RexPressable(
              onTap: onSeeAll,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      seeAllLabel,
                      style: RexText.caption.copyWith(color: p.inkSecondary),
                    ),
                    const SizedBox(width: 2),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 16,
                      color: p.inkSecondary,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 徽章：角标、画质标、集数标。
class RexBadge extends StatelessWidget {
  const RexBadge({
    super.key,
    required this.label,
    this.color,
    this.filled = true,
    this.icon,
  });

  final String label;
  final Color? color;
  final bool filled;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final RexPalette p = RexPalette.of(context);
    final Color fg = filled ? (color ?? p.inkPrimary) : (color ?? p.inkSecondary);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
      decoration: BoxDecoration(
        color: filled ? fg.withValues(alpha: 0.12) : Colors.transparent,
        borderRadius: BorderRadius.circular(RexRadius.badge),
        border: filled ? null : Border.all(color: p.hairlineStrong, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 10, color: fg),
            const SizedBox(width: 3),
          ],
          Text(
            label,
            style: RexText.micro.copyWith(
              color: fg,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// 细分隔线。
class RexDivider extends StatelessWidget {
  const RexDivider({super.key, this.indent = 0, this.height = 1});

  final double indent;
  final double height;

  @override
  Widget build(BuildContext context) {
    final RexPalette p = RexPalette.of(context);
    return Container(
      height: height,
      margin: EdgeInsets.only(left: indent, right: indent),
      color: p.hairline,
    );
  }
}

/// 抽屉：移动端从底部起，桌面端居中弹。
///
/// 对应 Rex 的 `SheetDetentBackground` / `PlayerPresentationSettingsSheetView`。
Future<T?> showRexSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool isDesktop = false,
  String? title,
  bool barrierDismissible = true,
  double desktopWidth = 460,
}) {
  final RexPalette p = RexPalette.of(context);
  final bool desktop =
      isDesktop || MediaQuery.sizeOf(context).width >= 900;

  if (desktop) {
    return showDialog<T>(
      context: context,
      barrierDismissible: barrierDismissible,
      barrierColor: p.scrim,
      builder: (ctx) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: desktopWidth),
            child: _RexSheetShell(
              title: title,
              desktop: true,
              child: builder(ctx),
            ),
          ),
        );
      },
    );
  }

  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: p.scrim,
    builder: (ctx) {
      return _RexSheetShell(title: title, desktop: false, child: builder(ctx));
    },
  );
}

class _RexSheetShell extends StatelessWidget {
  const _RexSheetShell({
    required this.child,
    required this.desktop,
    this.title,
  });

  final Widget child;
  final bool desktop;
  final String? title;

  @override
  Widget build(BuildContext context) {
    final RexPalette p = RexPalette.of(context);
    final Widget content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!desktop)
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 4),
            child: Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: p.inkTertiary.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
        if (title != null)
          Padding(
            padding: EdgeInsets.fromLTRB(
              RexSpace.lg,
              desktop ? RexSpace.lg : RexSpace.xs,
              RexSpace.lg,
              RexSpace.sm,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title!,
                    style: RexText.headline.copyWith(color: p.inkPrimary),
                  ),
                ),
                if (desktop)
                  RexIconButton(
                    icon: Icons.close_rounded,
                    size: 32,
                    iconSize: 18,
                    glass: false,
                    onTap: () => Navigator.of(context).maybePop(),
                  ),
              ],
            ),
          ),
        Flexible(
          child: Padding(
            padding: EdgeInsets.only(bottom: desktop ? RexSpace.lg : 0),
            child: child,
          ),
        ),
      ],
    );

    if (desktop) {
      return Material(
        color: p.surfaceRaised,
        borderRadius: BorderRadius.circular(RexRadius.sheet),
        clipBehavior: Clip.antiAlias,
        child: content,
      );
    }

    return Material(
      color: p.surfaceRaised,
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(RexRadius.sheet),
      ),
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.86,
          ),
          child: content,
        ),
      ),
    );
  }
}

/// 空状态。
class RexEmptyState extends StatelessWidget {
  const RexEmptyState({
    super.key,
    required this.title,
    this.message,
    this.icon = Icons.movie_outlined,
    this.action,
  });

  final String title;
  final String? message;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final RexPalette p = RexPalette.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(RexSpace.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: p.inkTertiary),
            const SizedBox(height: RexSpace.md),
            Text(
              title,
              textAlign: TextAlign.center,
              style: RexText.headline.copyWith(color: p.inkPrimary),
            ),
            if (message != null) ...[
              const SizedBox(height: RexSpace.xs),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: RexText.caption.copyWith(color: p.inkSecondary),
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: RexSpace.lg),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

/// 通栏主视觉（Rex 的 `BoardBannerCell` / `BoardTemplateBannerCell`）。
///
/// 一张大图打底，底部压一层黑渐变把文字托住，左下角是标题 + 一行 meta +
/// 一到两个胶囊按钮。整个 app 里「一屏只出现一次」的元素就是它。
class RexHeroBanner extends StatelessWidget {
  const RexHeroBanner({
    super.key,
    required this.imageUrl,
    required this.title,
    this.subtitle,
    this.eyebrow,
    this.primaryLabel,
    this.primaryIcon = Icons.play_arrow_rounded,
    this.onPrimary,
    this.secondaryLabel,
    this.secondaryIcon = Icons.info_outline_rounded,
    this.onSecondary,
    this.height,
    this.radius = RexRadius.hero,
    this.margin = const EdgeInsets.fromLTRB(
      RexSpace.page,
      RexSpace.xxs,
      RexSpace.page,
      0,
    ),
    this.progress,
  });

  final String imageUrl;
  final String title;
  final String? subtitle;

  /// 左上角小标签，例如「继续观看」。
  final String? eyebrow;
  final String? primaryLabel;
  final IconData primaryIcon;
  final VoidCallback? onPrimary;
  final String? secondaryLabel;
  final IconData secondaryIcon;
  final VoidCallback? onSecondary;

  /// 不传时按窗口宽度算（桌面 320 / 移动 216）。
  final double? height;
  final double radius;
  final EdgeInsets margin;

  /// 0~1，底部那条细进度。
  final double? progress;

  @override
  Widget build(BuildContext context) {
    final double w = MediaQuery.sizeOf(context).width;
    final double h = height ?? (w >= 900 ? 320 : 216);

    return Padding(
      padding: margin,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: SizedBox(
          height: h,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (imageUrl.isNotEmpty)
                Image.network(
                  imageUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const ColoredBox(
                    color: Color(0xFF1A1A1C),
                  ),
                )
              else
                const ColoredBox(color: Color(0xFF1A1A1C)),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: [0.15, 1],
                    colors: [Color(0x1A000000), Color(0xF2000000)],
                  ),
                ),
              ),
              Positioned(
                left: 20,
                right: 20,
                bottom: 20,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (eyebrow != null && eyebrow!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(RexRadius.badge),
                          ),
                          child: Text(
                            eyebrow!,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ),
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: w >= 900 ? 30 : 22,
                        fontWeight: FontWeight.w700,
                        height: 1.14,
                        letterSpacing: -0.6,
                      ),
                    ),
                    if (subtitle != null && subtitle!.isNotEmpty) ...[
                      const SizedBox(height: 7),
                      Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.68),
                          fontSize: 12,
                        ),
                      ),
                    ],
                    if (onPrimary != null) ...[
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          _HeroPill(
                            label: primaryLabel ?? '播放',
                            icon: primaryIcon,
                            filled: true,
                            onTap: onPrimary!,
                          ),
                          if (onSecondary != null) ...[
                            const SizedBox(width: 10),
                            _HeroPill(
                              label: secondaryLabel ?? '详情',
                              icon: secondaryIcon,
                              filled: false,
                              onTap: onSecondary!,
                            ),
                          ],
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              if (progress != null && progress! > 0)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    height: 3,
                    color: Colors.black.withValues(alpha: 0.5),
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor: progress!.clamp(0.0, 1.0),
                      child: const ColoredBox(color: Colors.white),
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

class _HeroPill extends StatelessWidget {
  const _HeroPill({
    required this.label,
    required this.icon,
    required this.filled,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool filled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return RexPressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: BoxDecoration(
          color: filled ? Colors.white : Colors.white.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(RexRadius.pill),
          border: filled
              ? null
              : Border.all(color: Colors.white.withValues(alpha: 0.28)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 17, color: filled ? Colors.black : Colors.white),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: filled ? Colors.black : Colors.white,
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
