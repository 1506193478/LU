import 'package:flutter/material.dart';

/// 加载中的占位卡片：和真实卡片同尺寸，带一层缓慢扫过的微光。
///
/// 为什么不放个转圈：转圈只说明「在等」，骨架屏还告诉你「等来的是什么形状」，
/// 内容出现时不会整块跳一下。10 张卡片的 ticker 开销可以忽略，而且列表一加载
/// 完它们就整批消失了。
class BangumiCardSkeleton extends StatelessWidget {
  const BangumiCardSkeleton({super.key, this.compact = false});

  /// 手机三列时的紧凑版（内边距和圆角都收一档，和拟态卡片对齐）。
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    final _SkeletonColors palette = _SkeletonColors.of(theme);
    final double pad = compact ? 7 : 10;

    final Widget bars = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 10),
        _SkeletonBar(palette.base, widthFactor: 0.86, height: 10),
        const SizedBox(height: 6),
        _SkeletonBar(palette.base, widthFactor: 0.52, height: 8),
      ],
    );

    final Widget content = Container(
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(compact ? 18 : 22),
      ),
      padding: EdgeInsets.all(pad),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: palette.base,
                borderRadius: BorderRadius.circular(compact ? 12 : 16),
              ),
            ),
          ),
          bars,
        ],
      ),
    );

    return _ShimmerMask(
      base: palette.base,
      highlight: palette.highlight,
      child: content,
    );
  }
}

/// 横向卡片的骨架（时间表用）：左边一块封面，右边两行字。
///
/// 尺寸由调用方用 `SizedBox` 约束成真实卡片的高度，这样内容到达时
/// 网格不会重新算行高。
class BangumiRowSkeleton extends StatelessWidget {
  const BangumiRowSkeleton({
    super.key,
    this.compact = false,
    this.coverWidth = 88,
  });

  final bool compact;
  final double coverWidth;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    final _SkeletonColors palette = _SkeletonColors.of(theme);
    const double pad = 12;

    final Widget content = Container(
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(28),
      ),
      padding: const EdgeInsets.all(pad),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: compact ? coverWidth - 8 : coverWidth,
            child: Container(
              decoration: BoxDecoration(
                color: palette.base,
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          SizedBox(width: compact ? 12 : 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 8),
                _SkeletonBar(palette.base, widthFactor: 0.82, height: 12),
                const SizedBox(height: 8),
                _SkeletonBar(palette.base, widthFactor: 0.48, height: 12),
                const SizedBox(height: 12),
                _SkeletonBar(palette.base, widthFactor: 0.38, height: 8),
                const Spacer(),
                _SkeletonBar(palette.base, widthFactor: 0.30, height: 10),
              ],
            ),
          ),
        ],
      ),
    );

    return _ShimmerMask(
      base: palette.base,
      highlight: palette.highlight,
      child: content,
    );
  }
}

class _SkeletonColors {
  const _SkeletonColors({required this.base, required this.highlight});

  final Color base;
  final Color highlight;

  static _SkeletonColors of(ThemeData theme) {
    final ColorScheme colors = theme.colorScheme;
    final bool dark = theme.brightness == Brightness.dark;
    return _SkeletonColors(
      base: dark ? colors.surfaceContainerHigh : colors.surfaceContainerHighest,
      highlight:
          dark ? colors.surfaceContainerHighest : colors.surfaceContainerLow,
    );
  }
}

class _SkeletonBar extends StatelessWidget {
  const _SkeletonBar(
    this.color, {
    required this.widthFactor,
    required this.height,
  });

  final Color color;
  final double widthFactor;
  final double height;

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      alignment: Alignment.centerLeft,
      widthFactor: widthFactor,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(height / 2),
        ),
      ),
    );
  }
}

/// 一层扫过的微光。系统开了「减少动画」就直接返回原图，静态灰块一样能表达
/// 「在加载」，还省掉一堆 ticker。
class _ShimmerMask extends StatefulWidget {
  const _ShimmerMask({
    required this.child,
    required this.base,
    required this.highlight,
  });

  final Widget child;
  final Color base;
  final Color highlight;

  @override
  State<_ShimmerMask> createState() => _ShimmerMaskState();
}

class _ShimmerMaskState extends State<_ShimmerMask>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shimmer = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void initState() {
    super.initState();
    _shimmer.repeat();
  }

  @override
  void dispose() {
    _shimmer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) {
      return widget.child;
    }
    return AnimatedBuilder(
      animation: _shimmer,
      builder: (context, child) {
        final double t = _shimmer.value;
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (Rect bounds) => LinearGradient(
            begin: Alignment(-1.4 + 2.8 * t, -0.3),
            end: Alignment(-0.4 + 2.8 * t, 0.3),
            colors: <Color>[widget.base, widget.highlight, widget.base],
            stops: const <double>[0.25, 0.5, 0.75],
          ).createShader(bounds),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}
