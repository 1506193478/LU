import 'dart:io';
import 'dart:ui' show ImageFilter;

import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

import 'package:XL/services/theme/lu_background.dart';

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

/// 页面背景。
///
/// 有自定义图片就用图片（压一层遮罩保证文字可读），否则用预设：
/// 四段底色渐变 + 几颗光球。预设与图片都存在 [LuBackground] 里，
/// 深浅模式各记一套。
///
/// **背景不做动画。**
///
/// 3.9.59 给光球加过 34 秒漂移，结果整模块滑动掉帧：那层是满屏
/// `CustomPaint`，光球都是 radial gradient shader，动画期间每帧重新生成
/// shader 并重绘整块画布——`RepaintBoundary` 只保证「内容变化时背景不重绘」，
/// 挡不住「背景自己在动」。静态之后首次布局画一次，之后合成器直接缓存。
class LuBackdrop extends StatelessWidget {
  const LuBackdrop({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    // 背景挂在 MaterialApp.builder 上，不会随页面 setState 重建，
    // 所以换背景必须走 notifier。
    return ValueListenableBuilder<int>(
      valueListenable: LuBackground.revision,
      builder: (BuildContext context, int _, Widget? __) {
        final bool dark = LuGlass.isDark(context);
        if (LuBackground.usingImage) {
          return _ImageBackdrop(dark: dark, child: child);
        }
        final LuBgPreset preset = LuBackground.presetFor(dark);
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
                            colors: preset.colors,
                            stops: const <double>[0, 0.34, 0.66, 1],
                          ),
                        ),
                      ),
                    ),
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _OrbPainter(orbs: preset.orbs),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            child,
          ],
        );
      },
    );
  }
}

/// 自定义图片背景。
///
/// 图片之上必须压一层遮罩：用户选的图可能是亮的天也可能是暗的夜，
/// 不压的话文字对比度完全不可控。深浅两种遮罩浓度不同，但目的相同——
/// 把背景压到「能看清字」的区间，同时留住图片的氛围。
class _ImageBackdrop extends StatelessWidget {
  const _ImageBackdrop({required this.dark, required this.child});

  final bool dark;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final double width = MediaQuery.sizeOf(context).width;
    return Stack(
      children: <Widget>[
        Positioned.fill(
          child: RepaintBoundary(
            child: Image.file(
              File(LuBackground.imagePath),
              fit: BoxFit.cover,
              // 原图可能是 4K，直接铺会把内存打满；按屏幕宽度的一倍半解码足够。
              cacheWidth: (width * 1.5).round().clamp(720, 2048),
              gaplessPlayback: true,
              errorBuilder: (_, __, ___) => ColoredBox(
                color: dark ? const Color(0xFF0D1017) : const Color(0xFFD6E0FF),
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: dark
                    ? const <Color>[Color(0x99101018), Color(0xCC0A0A10)]
                    : const <Color>[Color(0x66FFFFFF), Color(0x99FFFFFF)],
              ),
            ),
          ),
        ),
        child,
      ],
    );
  }
}

class _OrbPainter extends CustomPainter {
  const _OrbPainter({required this.orbs});

  final List<LuBgOrb> orbs;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) {
      return;
    }
    final double unit = size.shortestSide;

    for (final LuBgOrb o in orbs) {
      final Offset center = Offset(size.width * o.dx, size.height * o.dy);
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
  bool shouldRepaint(_OrbPainter old) => old.orbs != orbs;
}

/// 页面转场构建器：给每条路由**自己**垫一层不透明的 [LuBackdrop]。
///
/// 为什么背景要在这里垫，而不是靠壳层那一份：
///
/// 3.9.60 把页面底色改透明、背景统一交给 `MaterialApp.builder` 里的
/// 壳层 LuBackdrop 之后，出现「打开任何页面重影一下」——Cupertino 转场
/// 期间新旧两个路由**同时**绘制，新页面是透明的，旧页内容就从半透明的
/// 玻璃卡后面透出来。壳层背景救不了场：它在 Navigator 下面，而旧路由
/// 在壳层背景**上面**，新页面能透过去的正是旧路由这一层。
///
/// 所以把不透明背景下沉到每条路由：路由内容外面包一层 LuBackdrop
/// （渐变 + 光球，全部不透明），转场期间旧页再也透不出来。
///
/// 三件顺带的事：
///   * 转场完成后 Flutter 会跳过被不透明路由盖住的下层，壳层那份背景
///     在有路由盖着时根本不绘制，没有常驻双重绘制的开销；
///   * 背景是静态的（见 [LuBackdrop] 注释），每条路由只画一次并缓存；
///   * 弹窗 / 底部弹层不走 pageTransitionsTheme，不受影响。
///
/// `useCupertino` 与 `constants.dart` 里的平台分工一致：手机端保留
/// Cupertino 转场的边缘返回手势，桌面端用 FadeForwards。
class LuBackdropTransitionsBuilder extends PageTransitionsBuilder {
  const LuBackdropTransitionsBuilder({this.useCupertino = true});

  final bool useCupertino;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final Widget opaque = LuBackdrop(child: child);
    if (useCupertino) {
      return const CupertinoPageTransitionsBuilder().buildTransitions(
        route,
        context,
        animation,
        secondaryAnimation,
        opaque,
      );
    }
    return const FadeForwardsPageTransitionsBuilder().buildTransitions(
      route,
      context,
      animation,
      secondaryAnimation,
      opaque,
    );
  }
}
