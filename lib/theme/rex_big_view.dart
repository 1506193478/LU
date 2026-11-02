import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'package:XL/bean/widget/clay_neu.dart';
import 'package:XL/theme/rex_design.dart';

/// 通栏大视图轮播（Rex 形态）。
///
/// 「推荐」页和 Emby 媒体库页共用的主视觉：
/// - 通栏大图直接顶到状态栏底下，页面内容从图片底边开始；
/// - 标题 / 评分行 / 两行简介 / 圆点全部压在图片底部的渐隐区上，
///   渐隐色就是页面底色（[fadeColor]），所以图片是"融"进页面而不是被裁掉；
/// - 左右滑切换，圆点跟着走，选中的圆点变成长条。
///
/// 和 [RexHeroBanner] 的区别：那个是圆角卡片，这个是全出血（edge-to-edge），
/// 用在页面第一屏当"门面"。桌面宽屏仍然建议用卡片版，通栏图在宽窗口下
/// 会把一行标题拉得太长。
class RexBigViewItem {
  const RexBigViewItem({
    required this.imageUrl,
    required this.title,
    required this.onTap,
    this.headers,
    this.score,
    this.year,
    this.badge,
    this.genres,
    this.desc,
    this.placeholderColor,
  });

  final String imageUrl;
  final String title;
  final VoidCallback onTap;

  /// Emby 需要带 token 头，bangumi 不需要。
  final Map<String, String>? headers;

  /// ★ 后面的评分，空则不显示整段评分行。
  final String? score;
  final String? year;

  /// 分级 / 标签胶囊，例如「SG-NC16」。
  final String? badge;
  final String? genres;
  final String? desc;

  /// 图没回来时占位块的底色，传 null 用主题的 surfaceSunken。
  final Color? placeholderColor;
}

class RexBigViewCarousel extends StatefulWidget {
  const RexBigViewCarousel({
    super.key,
    required this.items,
    required this.fadeColor,
    this.height,
    this.topOverlay,
    this.onPageChanged,
    this.emptyBuilder,
  });

  final List<RexBigViewItem> items;

  /// 页面底色，用于图片底部的渐隐。
  final Color fadeColor;

  /// 固定高度；不传时按屏幕高度自适应（手机约 0.55 屏，桌面 380）。
  final double? height;

  /// 浮在图片上方的顶部操作行（搜索 / 收藏 / 窗口控制…）。
  /// 外层要自己带 SafeArea。
  final Widget? topOverlay;

  final ValueChanged<int>? onPageChanged;

  /// items 为空时的占位（保持页面结构不塌）。
  final Widget? emptyBuilder;

  @override
  State<RexBigViewCarousel> createState() => _RexBigViewCarouselState();
}

class _RexBigViewCarouselState extends State<RexBigViewCarousel> {
  final PageController _controller = PageController();
  int _index = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double _height(BuildContext context) {
    if (widget.height != null) return widget.height!;
    if (isDesktopWideLayout(context)) return 380;
    final h = MediaQuery.sizeOf(context).height;
    return (h * 0.55).clamp(380.0, 520.0);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) {
      return SizedBox(
        height: _height(context),
        child: widget.emptyBuilder ?? const SizedBox.shrink(),
      );
    }
    return SizedBox(
      height: _height(context),
      child: Stack(
        fit: StackFit.expand,
        children: [
          PageView.builder(
            controller: _controller,
            itemCount: widget.items.length,
            onPageChanged: (i) {
              setState(() => _index = i);
              widget.onPageChanged?.call(i);
            },
            itemBuilder: (context, i) => _slide(context, widget.items[i]),
          ),
          // 顶部操作行浮在图上。
          if (widget.topOverlay != null)
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: widget.topOverlay!,
            ),
        ],
      ),
    );
  }

  Widget _slide(BuildContext context, RexBigViewItem item) {
    final desktop = isDesktopWideLayout(context);
    return GestureDetector(
      onTap: item.onTap,
      child: Stack(
        fit: StackFit.expand,
        children: [
          _image(context, item),
          // 底部渐隐：从透明到页面底色，标题区坐在渐隐带上。
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: const [0.30, 0.62, 0.88, 1.0],
                colors: [
                  Colors.transparent,
                  widget.fadeColor.withValues(alpha: 0.22),
                  widget.fadeColor.withValues(alpha: 0.88),
                  widget.fadeColor,
                ],
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: EdgeInsets.fromLTRB(22, 0, 22, desktop ? 20 : 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _ink(item),
                        fontSize: 30,
                        fontWeight: FontWeight.w800,
                        height: 1.14,
                        letterSpacing: -0.9,
                        shadows: _shadows(item),
                      ),
                    ),
                    const SizedBox(height: 9),
                    _rateRow(context, item),
                    if (item.desc != null && item.desc!.isNotEmpty) ...[
                      const SizedBox(height: 7),
                      Text(
                        item.desc!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: _ink(item).withValues(alpha: 0.82),
                          fontSize: 12,
                          height: 1.5,
                          shadows: _shadows(item, alpha: 0.3),
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    _dots(context, item),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 文字颜色跟着图走：浅色占位图（Emby 媒体库常没图）用深字，
  /// 真海报一律白字。有真图时以白字为准，靠文字阴影兜可读性。
  Color _ink(RexBigViewItem item) =>
      item.imageUrl.isEmpty ? const Color(0xFF17171B) : Colors.white;

  List<Shadow> _shadows(RexBigViewItem item, {double alpha = 0.5}) =>
      item.imageUrl.isEmpty
          ? const []
          : [
              Shadow(
                color: Colors.black.withValues(alpha: alpha),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ];

  Widget _rateRow(BuildContext context, RexBigViewItem item) {
    final parts = <Widget>[
      if (item.score != null && item.score!.isNotEmpty) ...[
        const Text('★',
            style: TextStyle(color: Color(0xFFFF5A4E), fontSize: 13)),
        const SizedBox(width: 3),
        Text(item.score!,
            style: TextStyle(
                color: _ink(item), fontSize: 12.5, fontWeight: FontWeight.w600)),
      ],
      if (item.year != null && item.year!.isNotEmpty)
        Text(item.year!,
            style: TextStyle(
                color: _ink(item), fontSize: 12.5, fontWeight: FontWeight.w600)),
      if (item.badge != null && item.badge!.isNotEmpty)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
          decoration: BoxDecoration(
            border: Border.all(
              color: _ink(item).withValues(alpha: 0.7),
              width: 1.1,
            ),
            borderRadius: BorderRadius.circular(5),
          ),
          child: Text(
            item.badge!,
            style: TextStyle(
              color: _ink(item),
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      if (item.genres != null && item.genres!.isNotEmpty)
        Text(item.genres!,
            style: TextStyle(
                color: _ink(item), fontSize: 12.5, fontWeight: FontWeight.w600)),
    ];
    if (parts.isEmpty) return const SizedBox.shrink();

    final children = <Widget>[];
    for (var i = 0; i < parts.length; i++) {
      if (i > 0) {
        children.add(Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text('·',
              style: TextStyle(
                  color: _ink(item).withValues(alpha: 0.55), fontSize: 12)),
        ));
      }
      children.add(parts[i]);
    }
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 0,
      runSpacing: 4,
      children: children,
    );
  }

  Widget _dots(BuildContext context, RexBigViewItem item) {
    // 预览稿 .bv-dots：固定黑系圆点（渐隐带是浅色页面底色）；
    // 深色模式页面底色深，换白系保证可见。
    final bool dark = Theme.of(context).brightness == Brightness.dark;
    final Color idle = dark
        ? Colors.white.withValues(alpha: 0.24)
        : Colors.black.withValues(alpha: 0.20);
    final Color active = dark
        ? Colors.white.withValues(alpha: 0.62)
        : Colors.black.withValues(alpha: 0.46);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < widget.items.length; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: i == _index ? 16 : 5,
            height: 5,
            decoration: BoxDecoration(
              color: i == _index ? active : idle,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
      ],
    );
  }

  Widget _image(BuildContext context, RexBigViewItem item) {
    if (item.imageUrl.isEmpty) {
      final p = RexPalette.of(context);
      return ColoredBox(
        color: item.placeholderColor ?? p.surfaceSunken,
        child: Center(
          child: Icon(
            Icons.movie_filter_outlined,
            size: 64,
            color: p.inkTertiary.withValues(alpha: 0.5),
          ),
        ),
      );
    }
    return CachedNetworkImage(
      imageUrl: item.imageUrl,
      httpHeaders: item.headers,
      fit: BoxFit.cover,
      alignment: Alignment.topCenter,
      placeholder: (_, _) => ColoredBox(
        color: item.placeholderColor ??
            RexPalette.of(context).surfaceSunken,
      ),
      errorWidget: (_, _, _) => ColoredBox(
        color: item.placeholderColor ??
            RexPalette.of(context).surfaceSunken,
        child: Center(
          child: Icon(
            Icons.movie_filter_outlined,
            size: 64,
            color: RexPalette.of(context).inkTertiary.withValues(alpha: 0.5),
          ),
        ),
      ),
    );
  }
}
