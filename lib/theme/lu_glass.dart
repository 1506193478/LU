import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';


/// 玻璃拟态的材质层与背景层。
///
/// 只有这两个东西，所有页面都从这里取，避免又出现「每个控件各调一套透明度」
/// 的老问题（3.9.58 之前 `_GlassPlate`、`RexIconButton`、播放器 `_ToolChip`
/// 就是三套参数，所以看起来不像是同一个材质）。
///
/// ## 关于 `blur` 的一个重要取舍
///
/// 卡片默认 **不做 `BackdropFilter`**，只叠半透明白 + 渐变 + 高光边。
///
/// 原因：背景是 [LuBackdrop] 画的柔和光球，本身没有任何高频细节可以糊，
/// 再对一片纯渐变做高斯模糊，视觉收益是零、代价是每个卡片一层离屏缓冲。
/// 一屏六张卡就是六层，滚动时每帧重算一次——这正是「加了玻璃就掉帧」的
/// 来源。
///
/// 真正需要模糊的只有**背后有实际内容**的浮层：底栏、弹出菜单、表单 sheet、
/// HUD。这些地方传 `blur: true`。
enum LuGlassTone {
  /// 底栏、弹出菜单这类必须压住背后内容的。
  strong,

  /// 卡片、胶囊的默认档。
  medium,

  /// 大面积面板，透一点即可。
  weak,
}

/// 一档玻璃的全部参数。
@immutable
class LuGlassSpec {
  const LuGlassSpec({
    required this.top,
    required this.bottom,
    required this.base,
    required this.edge,
    required this.ring,
    required this.shadows,
  });

  /// 渐变的两端：左上亮 → 右下滑。
  final Color top;
  final Color bottom;

  /// 垫在渐变下面的底色（深色模式要压一层暗底，不然会变成彩色玻璃片）。
  final Color base;

  /// 顶部 1px 高光。
  final Color edge;

  /// 四周极淡的内圈，做出「材质厚度」而不是「画了个框」。
  final Color ring;
  final List<BoxShadow> shadows;
}

/// 材质与背景的取值入口。
abstract final class LuGlass {
  LuGlass._();

  static bool isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  /// 浅色：整体偏蓝紫，卡片走「白 50% → 23%」。
  /// 深色：刻意压低饱和（3.9.59 之前那版紫红太艳），走中性深蓝灰。
  static LuGlassSpec spec(BuildContext context, LuGlassTone tone) {
    final bool dark = isDark(context);
    if (dark) {
      switch (tone) {
        case LuGlassTone.strong:
          return const LuGlassSpec(
            top: Color(0x29FFFFFF), // 16%
            bottom: Color(0x0DFFFFFF), // 5%
            base: Color(0x800A0C12), // 50% 暗底
            edge: Color(0x38FFFFFF),
            ring: Color(0x1CFFFFFF),
            shadows: <BoxShadow>[
              BoxShadow(
                color: Color(0x66000000),
                blurRadius: 28,
                offset: Offset(0, 12),
              ),
            ],
          );
        case LuGlassTone.medium:
          return const LuGlassSpec(
            top: Color(0x24FFFFFF), // 14%
            bottom: Color(0x0AFFFFFF), // 4%
            base: Color(0x730A0C12), // 45%
            edge: Color(0x33FFFFFF),
            ring: Color(0x17FFFFFF),
            shadows: <BoxShadow>[
              BoxShadow(
                color: Color(0x52000000),
                blurRadius: 22,
                offset: Offset(0, 9),
              ),
            ],
          );
        case LuGlassTone.weak:
          return const LuGlassSpec(
            top: Color(0x1AFFFFFF),
            bottom: Color(0x0AFFFFFF),
            base: Color(0x400A0C12),
            edge: Color(0x26FFFFFF),
            ring: Color(0x12FFFFFF),
            shadows: <BoxShadow>[
              BoxShadow(
                color: Color(0x3D000000),
                blurRadius: 16,
                offset: Offset(0, 6),
              ),
            ],
          );
      }
    }
    switch (tone) {
      case LuGlassTone.strong:
        return const LuGlassSpec(
          top: Color(0xF0FFFFFF), // 94%
          bottom: Color(0xDBFFFFFF), // 86%
          base: Color(0x00000000),
          edge: Color(0xF2FFFFFF),
          ring: Color(0x4DFFFFFF),
          shadows: <BoxShadow>[
            BoxShadow(
              color: Color(0x14262A5C),
              blurRadius: 26,
              offset: Offset(0, 10),
            ),
            BoxShadow(
              color: Color(0x0A262A5C),
              blurRadius: 3,
              offset: Offset(0, 1),
            ),
          ],
        );
      case LuGlassTone.medium:
        return const LuGlassSpec(
          top: Color(0x80FFFFFF), // 50%
          bottom: Color(0x3BFFFFFF), // 23%
          base: Color(0x00000000),
          edge: Color(0xF2FFFFFF),
          ring: Color(0x4DFFFFFF),
          shadows: <BoxShadow>[
            BoxShadow(
              color: Color(0x17262A5C),
              blurRadius: 24,
              offset: Offset(0, 8),
            ),
            BoxShadow(
              color: Color(0x0D262A5C),
              blurRadius: 2,
              offset: Offset(0, 1),
            ),
          ],
        );
      case LuGlassTone.weak:
        return const LuGlassSpec(
          top: Color(0x66FFFFFF),
          bottom: Color(0x2EFFFFFF),
          base: Color(0x00000000),
          edge: Color(0xCCFFFFFF),
          ring: Color(0x33FFFFFF),
          shadows: <BoxShadow>[
            BoxShadow(
              color: Color(0x12262A5C),
              blurRadius: 16,
              offset: Offset(0, 5),
            ),
          ],
        );
    }
  }

  /// 一块玻璃。
  ///
  /// [blur] 只在背后有真实内容（图片、文字）时才打开，理由见文件头。
  /// 卡片、列表行一律关闭。
  static Widget box({
    required BuildContext context,
    required Widget child,
    LuGlassTone tone = LuGlassTone.medium,
    BorderRadius? radius,
    bool blur = false,
    double sigma = 24,
  }) {
    final LuGlassSpec s = spec(context, tone);
    final BorderRadius r = radius ?? BorderRadius.circular(12);

    final Widget inner = DecoratedBox(
      decoration: BoxDecoration(
        color: s.base,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[s.top, s.bottom],
        ),
      ),
      child: DecoratedBox(
        // 边框画在内容之上：用 Border 会占据布局 1px，行高会整体漂移。
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          borderRadius: r,
          border: Border.all(color: s.ring, width: 1),
        ),
        child: child,
      ),
    );

    final Widget clipped = ClipRRect(
      borderRadius: r,
      child: blur
          ? BackdropFilter(
              filter: ImageFilter.blur(
                sigmaX: sigma,
                sigmaY: sigma,
                tileMode: TileMode.clamp,
              ),
              child: inner,
            )
          : inner,
    );

    return DecoratedBox(
      decoration: BoxDecoration(borderRadius: r, boxShadow: s.shadows),
      child: DecoratedBox(
        // 顶部高光：只画上面 1px，不是整圈描边。整圈会变成「贴图上的框」。
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          borderRadius: r,
          border: Border(top: BorderSide(color: s.edge, width: 0.8)),
        ),
        child: clipped,
      ),
    );
  }
}

/// 一颗光球。
class _Orb {
  const _Orb(this.dx, this.dy, this.radius, this.color, this.strength);

  /// 圆心（相对宽高的比例）。
  final double dx;
  final double dy;

  /// 半径（相对短边的比例）。
  final double radius;
  final Color color;

  /// 中心不透明度。
  final double strength;
}

/// 浅色一套：蓝 / 紫 / 粉 / 青。
///
/// 饱和度是玻璃能不能「被看见」的前提——背景接近纯白时，玻璃后面是白、
/// 模糊完还是白，再怎么调卡片透明度都只会得到一张白卡。这是上一版失败的
/// 根本原因，不是配色偏好。
const List<_Orb> _lightOrbs = <_Orb>[
  _Orb(0.24, 0.10, 0.52, Color(0xFF688CFF), 0.52),
  _Orb(0.86, 0.32, 0.50, Color(0xFFC67CFF), 0.44),
  _Orb(0.10, 0.66, 0.54, Color(0xFFFF8CB6), 0.38),
  _Orb(0.90, 0.84, 0.52, Color(0xFF4AE0F6), 0.34),
  _Orb(0.52, 0.44, 0.46, Color(0xFFFFFFFF), 0.26),
];

/// 深色一套：刻意降饱和。
///
/// 用高饱和紫红 + 低不透明玻璃，会得到「彩色玻璃片」而不是深色磨砂；
/// 这里把色相收到灰蓝/灰紫，卡片再垫 45% 暗底，才压得住文字。
const List<_Orb> _darkOrbs = <_Orb>[
  _Orb(0.24, 0.10, 0.52, Color(0xFF566CA8), 0.42),
  _Orb(0.86, 0.32, 0.50, Color(0xFF685C96), 0.35),
  _Orb(0.10, 0.66, 0.54, Color(0xFF466E8C), 0.32),
  _Orb(0.90, 0.84, 0.52, Color(0xFF786084), 0.28),
  _Orb(0.52, 0.44, 0.46, Color(0xFFC8D2EB), 0.10),
];

/// 页面背景：底色渐变 + 五颗光球。
///
/// **背景是静态的，不做动画。**
///
/// 3.9.59 第一版给光球加了 34 秒的往复漂移，结果 Emby 模块整体滑动掉帧：
/// 那层是满屏的 `CustomPaint`，五颗光球都是 radial gradient shader，
/// 动画期间每帧都要重新生成 shader 并重绘整块画布——`RepaintBoundary`
/// 只保证「内容变化时背景不重绘」，挡不住「背景自己在动」。
///
/// 静态之后整块背景只在首次布局时画一次，之后合成器直接缓存，
/// 滚动零成本；视觉上少了一个几乎察觉不到的缓慢移动，换来的是稳帧。
class LuBackdrop extends StatelessWidget {
  const LuBackdrop({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final bool dark = LuGlass.isDark(context);
    final List<Color> base = dark
        ? const <Color>[
            Color(0xFF0D1017),
            Color(0xFF141824),
            Color(0xFF171523),
            Color(0xFF0A0D13),
          ]
        : const <Color>[
            Color(0xFFD6E0FF),
            Color(0xFFE7DAF9),
            Color(0xFFFFDFE8),
            Color(0xFFD6EEF7),
          ];

    return Stack(
      children: <Widget>[
        Positioned.fill(
          child: RepaintBoundary(
            child: Stack(
              children: <Widget>[
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: const Alignment(-0.35, -1),
                        end: const Alignment(0.35, 1),
                        colors: base,
                        stops: const <double>[0, 0.34, 0.66, 1],
                      ),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: CustomPaint(painter: _OrbPainter(dark: dark)),
                ),
              ],
            ),
          ),
        ),
        child,
      ],
    );
  }
}

class _OrbPainter extends CustomPainter {
  const _OrbPainter({required this.dark});

  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) {
      return;
    }
    final List<_Orb> orbs = dark ? _darkOrbs : _lightOrbs;
    final double unit = size.shortestSide;

    for (final _Orb o in orbs) {
      final Offset center = Offset(
        size.width * o.dx,
        size.height * o.dy,
      );
      final double radius = unit * o.radius;
      final Color c = o.color.withValues(alpha: o.strength);
      final Paint paint = Paint()
        ..shader = RadialGradient(
          colors: <Color>[c, c.withValues(alpha: 0)],
          stops: const <double>[0, 1],
        ).createShader(Rect.fromCircle(center: center, radius: radius));
      canvas.drawCircle(center, radius, paint);
    }
  }

  @override
  bool shouldRepaint(_OrbPainter old) => old.dark != dark;
}
