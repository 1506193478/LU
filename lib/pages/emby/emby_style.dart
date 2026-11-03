import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:XL/bean/widget/clay_neu.dart';
import 'package:XL/modules/emby/emby_models.dart';
import 'package:XL/services/logging/logger.dart';
import 'package:XL/theme/rex_design.dart';

/// Emby 模块的视觉层。
///
/// 走的是 Rex 那一套：**图多、壳薄、圆角大、几乎不用彩色**。
/// 内容主体是海报和剧照，所以除了「正在播放 / 已选中」这种状态，
/// 界面上不出现强调色，让封面自己说话。
///
/// 所有颜色都从 [RexPalette] 取，浅色深色都跟着走。

/// 圆角。海报 12、面板 18，桌面端各加 2。
double embyRadius(BuildContext context, {double base = RexRadius.poster}) =>
    isDesktopWideLayout(context) ? base + 2 : base;

/// 是否桌面（决定 hover 效果和更大的点击区）。
bool embyIsDesktop(BuildContext context) => isDesktopWideLayout(context);

/// 页面左右安全边距。
double embyPagePadding(BuildContext context) =>
    embyIsDesktop(context) ? RexSpace.xl : RexSpace.md;

/// Emby 图片。
///
/// 比直接用 `Image.network` / `NetworkImgLayer` 多做三件事，三件都是
/// 「封面全是灰块」的直接原因：
///
/// 1. **带 `X-Emby-Token` 头**。地址里的 `api_key` 在反向代理下经常被吃掉，
///    只靠查询串会整批 401。
/// 2. **失败时去掉 `tag` 重试一次**。`tag` 是 Emby 的缓存键，服务端重新扫库
///    之后旧 tag 就失效了，而 Emby 对失效 tag 的返回码是 **400**（不是 404），
///    客户端只会当成加载失败。去掉 tag 服务端会自己挑当前封面。
/// 3. **占位不是一块死灰**。加载中给一条淡淡的渐变，和海报区整体调子一致。
class EmbyImage extends StatefulWidget {
  const EmbyImage({
    super.key,
    required this.url,
    this.headers,
    this.fit = BoxFit.cover,
    this.fadeIn = const Duration(milliseconds: 180),
  });

  final String url;
  final Map<String, String>? headers;
  final BoxFit fit;
  final Duration fadeIn;

  @override
  State<EmbyImage> createState() => _EmbyImageState();
}

class _EmbyImageState extends State<EmbyImage> {
  /// 已经降级到第几级（0~2），到顶就不再重试，免得死循环。
  int _attempt = 0;
  late String _url = widget.url;

  @override
  void didUpdateWidget(covariant EmbyImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _attempt = 0;
      _url = widget.url;
    }
  }

  /// 逐级降级重试。
  ///
  /// 一张封面加载不出来，现实里只有三种原因，按代价从小到大退：
  ///   1. `tag` 过期——服务端重新生成过缩略图，旧 tag 会 400/404；
  ///   2. 尺寸参数被拒——个别反代把 `maxHeight` 改坏，或者老版本对
  ///      非 JPG 的图直接 500；
  ///   3. 图真的不存在——这时候再退也没用，交给占位图。
  ///
  /// 以前只做到第 1 步就停了，所以「大部分能出、少数灰块」的情况看起来
  /// 像是随机失败。现在一直退到只剩 `api_key`。
  static String _degrade(String url, int attempt) {
    final uri = Uri.tryParse(url);
    if (uri == null) return url;
    final kept = Map<String, String>.from(uri.queryParameters);
    if (attempt >= 1) kept.remove('tag');
    if (attempt >= 2) {
      kept.remove('maxHeight');
      kept.remove('maxWidth');
      kept.remove('quality');
    }
    return uri.replace(queryParameters: kept).toString();
  }

  void _onError(Object error) {
    KazumiLogger().w('EmbyImage: load failed ($_url)', error: error);
    if (_attempt >= 2) return;
    // 一级一级往下退。注意不能「退化后没变化就直接放弃」：地址里本来就没有
    // tag 时，第 1 级等于原地不动，得继续走到第 2 级去摘尺寸参数。
    int level = _attempt + 1;
    String next = _degrade(widget.url, level);
    while (next == _url && level < 2) {
      level++;
      next = _degrade(widget.url, level);
    }
    if (next == _url) return;
    // errorListener 可能在构建期间被调用，推迟一帧再 setState。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _attempt = level;
        _url = next;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_url.isEmpty) return const _EmbyImagePlaceholder();
    return CachedNetworkImage(
      imageUrl: _url,
      httpHeaders: widget.headers,
      fit: widget.fit,
      width: double.infinity,
      height: double.infinity,
      fadeInDuration: widget.fadeIn,
      fadeOutDuration: Duration.zero,
      placeholder: (_, _) => const _EmbyImagePlaceholder(),
      errorWidget: (_, _, _) => const _EmbyImagePlaceholder(),
      errorListener: _onError,
    );
  }
}

class _EmbyImagePlaceholder extends StatelessWidget {
  const _EmbyImagePlaceholder();

  @override
  Widget build(BuildContext context) {
    final RexPalette p = RexPalette.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [p.surface, p.surfaceSunken],
        ),
      ),
    );
  }
}

/// 图片请求要带的鉴权头。
///
/// `EmbyImage` 用。地址里已经有 `api_key`，但反代常常把查询串过滤掉，
/// 头是最稳的一条路。
Map<String, String> embyAuthHeaders(EmbyServer? server) {
  final token = server?.accessToken ?? '';
  if (token.isEmpty) return const {};
  return {'X-Emby-Token': token};
}

/// 页面外壳。
///
/// Rex 的页面没有 Material 的 AppBar：顶部就是一行「返回 + 标题 + 操作」，
/// 没有色带、没有 elevation。这里统一成这个形态，三个子页面都套它。
///
/// [overlay] 为 true 时顶栏浮在内容之上（详情页那种通栏大图要用），
/// 文字自动转白。
class EmbyPageShell extends StatelessWidget {
  const EmbyPageShell({
    super.key,
    required this.title,
    required this.body,
    this.subtitle,
    this.actions = const [],
    this.overlay = false,
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final Widget body;
  final bool overlay;

  @override
  Widget build(BuildContext context) {
    final RexPalette p = RexPalette.of(context);
    final double pad = embyPagePadding(context);
    final Color ink = overlay ? Colors.white : p.inkPrimary;
    final Color subInk = overlay
        ? Colors.white.withValues(alpha: 0.72)
        : p.inkSecondary;

    final Widget bar = Padding(
      padding: EdgeInsets.fromLTRB(pad - 6, RexSpace.xs, pad - 6, RexSpace.xs),
      child: Row(
        children: [
          RexIconButton(
            icon: Icons.arrow_back_ios_new_rounded,
            iconSize: 16,
            size: 34,
            glass: false,
            color: ink,
            onTap: () => Navigator.of(context).maybePop(),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: RexText.headline.copyWith(color: ink),
                ),
                if (subtitle != null && subtitle!.isNotEmpty)
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: RexText.micro.copyWith(
                      color: subInk,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
              ],
            ),
          ),
          ...actions,
        ],
      ),
    );

    return Scaffold(
      backgroundColor: overlay ? Colors.black : p.canvas,
      body: overlay
          ? Stack(
              children: [
                Positioned.fill(child: body),
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  child: SafeArea(bottom: false, child: bar),
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SafeArea(bottom: false, child: bar),
                Expanded(child: body),
              ],
            ),
    );
  }
}

/// 分区标题。
class EmbySectionHeader extends StatelessWidget {
  const EmbySectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.onMore,
    this.moreLabel = '查看全部',
  });

  final String title;
  final String? subtitle;
  final VoidCallback? onMore;
  final String moreLabel;

  @override
  Widget build(BuildContext context) {
    final RexPalette p = RexPalette.of(context);
    final double pad = embyPagePadding(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(pad, RexSpace.lg, pad, RexSpace.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: RexText.headline.copyWith(color: p.inkPrimary),
                ),
                if (subtitle != null && subtitle!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: RexText.caption.copyWith(color: p.inkSecondary),
                    ),
                  ),
              ],
            ),
          ),
          if (onMore != null)
            RexPressable(
              onTap: onMore,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      moreLabel,
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

/// 横向滑轨。子项宽度固定，滚动到边缘时不裁掉阴影。
class EmbyRail extends StatelessWidget {
  const EmbyRail({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.itemWidth,
    this.height,
    this.padding,
  });

  final int itemCount;
  final Widget Function(BuildContext context, int index) itemBuilder;
  final double? itemWidth;
  final double? height;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    final bool desktop = embyIsDesktop(context);
    final double width = itemWidth ?? (desktop ? 138 : 112);
    // 2:3 海报 + 两行标题 + 一行副标题
    final double railHeight = height ?? (width * 1.5 + 54);
    return SizedBox(
      height: railHeight,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding:
            padding ??
            EdgeInsets.symmetric(horizontal: embyPagePadding(context)),
        itemCount: itemCount,
        separatorBuilder: (_, _) => const SizedBox(width: RexSpace.rail),
        itemBuilder: (context, index) =>
            SizedBox(width: width, child: itemBuilder(context, index)),
      ),
    );
  }
}

/// 海报卡。
///
/// Rex 的 `BoardPosterCardCell` / `ShelfBoardViewController` 那一套：
/// 平时只有图 + 两行字，没有任何描边和底色；鼠标移上来才浮起 3px 并压一道
/// 极细的边。进度用贴底的细条，不盖封面。
class EmbyPosterTile extends StatefulWidget {
  const EmbyPosterTile({
    super.key,
    required this.item,
    required this.imageUrl,
    required this.onTap,
    this.subtitle,
    this.headers,
    this.showProgress = true,
    this.countBadge,
    this.score,
    this.onLongPress,
  });

  final EmbyItem item;
  final String imageUrl;
  final VoidCallback onTap;
  final String? subtitle;
  final Map<String, String>? headers;
  final bool showProgress;

  /// 右上角蓝色集数徽标（预览稿 `.poster .cnt`），空则不显示。
  final String? countBadge;

  /// 右下角评分白字（预览稿 `.poster .score`），空则不显示。
  final String? score;
  final VoidCallback? onLongPress;

  @override
  State<EmbyPosterTile> createState() => _EmbyPosterTileState();
}

class _EmbyPosterTileState extends State<EmbyPosterTile> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final RexPalette p = RexPalette.of(context);
    final bool desktop = embyIsDesktop(context);
    final double radius = embyRadius(context);
    final double progress = widget.showProgress ? widget.item.watchedRatio : 0;
    final String subtitle = widget.subtitle ?? _defaultSubtitle(widget.item);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) {
        if (desktop) setState(() => _hovering = true);
      },
      onExit: (_) {
        if (desktop) setState(() => _hovering = false);
      },
      child: GestureDetector(
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOutCubic,
          transform: Matrix4.translationValues(0, _hovering ? -3 : 0, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              AspectRatio(
                aspectRatio: 2 / 3,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(radius),
                    border: Border.all(
                      color: _hovering ? p.hairlineStrong : Colors.transparent,
                      width: 1,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(radius - 1),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        EmbyImage(
                          url: widget.imageUrl,
                          headers: widget.headers,
                        ),
                        if (progress > 0)
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: _ProgressStrip(ratio: progress),
                          ),
                        // 右上蓝色集数徽标（预览稿 .poster .cnt）。
                        if (widget.countBadge != null &&
                            widget.countBadge!.isNotEmpty)
                          Positioned(
                            top: 6,
                            right: 6,
                            child: Container(
                              constraints: const BoxConstraints(minWidth: 21),
                              height: 21,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                              ),
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: const Color(0xFF3E7BFA),
                                borderRadius: BorderRadius.circular(11),
                              ),
                              child: Text(
                                widget.countBadge!,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          )
                        else if (widget.item.played)
                          const Positioned(
                            top: 6,
                            right: 6,
                            child: _WatchedBadge(),
                          ),
                        // 右下评分白字（预览稿 .poster .score）。
                        if (widget.score != null && widget.score!.isNotEmpty)
                          Positioned(
                            right: 6,
                            bottom: 6,
                            child: Text(
                              widget.score!,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w800,
                                shadows: [
                                  Shadow(
                                    color: Color(0xB3000000),
                                    blurRadius: 4,
                                    offset: Offset(0, 1),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 7),
              // 预览稿 .poster .nm：一行截断。
              Text(
                widget.item.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: RexText.caption.copyWith(
                  color: p.inkPrimary,
                  fontWeight: FontWeight.w600,
                  height: 1.25,
                ),
              ),
              if (subtitle.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: RexText.micro.copyWith(
                      color: p.inkTertiary,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _defaultSubtitle(EmbyItem item) {
    if (item.isEpisode) return item.cardSubtitle;
    final parts = <String>[
      if (item.productionYear != null) '${item.productionYear}',
      if (item.isSeries && item.childCount != null && item.childCount! > 0)
        '${item.childCount} 集',
    ];
    return parts.join(' · ');
  }
}

class _ProgressStrip extends StatelessWidget {
  const _ProgressStrip({required this.ratio});

  final double ratio;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 3,
      color: Colors.black.withValues(alpha: 0.5),
      alignment: Alignment.centerLeft,
      child: FractionallySizedBox(
        widthFactor: ratio.clamp(0.0, 1.0),
        child: Container(color: Colors.white),
      ),
    );
  }
}

class _WatchedBadge extends StatelessWidget {
  const _WatchedBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        shape: BoxShape.circle,
      ),
      child: const Icon(Icons.check_rounded, size: 11, color: Colors.white),
    );
  }
}

/// 首页通栏主视觉。
///
/// 用 backdrop 大图打底，压一层自下而上的黑渐变保证文字可读——和海报卡不同，
/// 这里的文字是白字，不跟主题走，因为底下永远是一张图。
class EmbyHero extends StatelessWidget {
  const EmbyHero({
    super.key,
    required this.item,
    required this.imageUrl,
    required this.onPlay,
    this.onOpenDetail,
    this.headers,
    this.eyebrow,
  });

  final EmbyItem item;
  final String imageUrl;
  final VoidCallback onPlay;
  final VoidCallback? onOpenDetail;
  final Map<String, String>? headers;

  /// 左上角的小标签，例如「继续观看」。
  final String? eyebrow;

  @override
  Widget build(BuildContext context) {
    final bool desktop = embyIsDesktop(context);
    final double height = desktop ? 320 : 216;
    final double radius = embyRadius(context, base: RexRadius.hero);
    final double pad = embyPagePadding(context);

    return Padding(
      padding: EdgeInsets.fromLTRB(pad, RexSpace.xxs, pad, 0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: SizedBox(
          height: height,
          child: Stack(
            fit: StackFit.expand,
            children: [
              EmbyImage(url: imageUrl, headers: headers),
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
                left: desktop ? 26 : 18,
                right: desktop ? 26 : 18,
                bottom: desktop ? 24 : 18,
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
                            borderRadius: BorderRadius.circular(
                              RexRadius.badge,
                            ),
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
                      item.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: desktop ? 30 : 22,
                        fontWeight: FontWeight.w700,
                        height: 1.14,
                        letterSpacing: -0.6,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      _metaLine(item),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.68),
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        _HeroButton(
                          label: item.isInProgress ? '继续播放' : '播放',
                          icon: Icons.play_arrow_rounded,
                          filled: true,
                          onTap: onPlay,
                        ),
                        if (onOpenDetail != null) ...[
                          const SizedBox(width: 10),
                          _HeroButton(
                            label: '详情',
                            icon: Icons.info_outline_rounded,
                            filled: false,
                            onTap: onOpenDetail!,
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              if (item.watchedRatio > 0)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: _ProgressStrip(ratio: item.watchedRatio),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _metaLine(EmbyItem item) {
    final parts = <String>[
      if (item.productionYear != null) '${item.productionYear}',
      if (item.officialRating != null && item.officialRating!.isNotEmpty)
        item.officialRating!,
      if (item.genres.isNotEmpty) item.genres.take(3).join(' / '),
      if (item.communityRating != null)
        '${item.communityRating!.toStringAsFixed(1)} 分',
    ];
    return parts.join('  ·  ');
  }
}

/// 主视觉上的胶囊按钮：实心白 / 半透明描边。
class _HeroButton extends StatelessWidget {
  const _HeroButton({
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

/// 服务器切换胶囊。
class EmbyServerChip extends StatelessWidget {
  const EmbyServerChip({super.key, required this.server, required this.onTap});

  final EmbyServer server;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final RexPalette p = RexPalette.of(context);
    return RexPressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        decoration: BoxDecoration(
          color: p.surfaceSunken,
          borderRadius: BorderRadius.circular(RexRadius.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: p.accent,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 7),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 160),
              child: Text(
                server.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: RexText.label.copyWith(
                  color: p.inkPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 2),
            Icon(Icons.expand_more_rounded, size: 15, color: p.inkSecondary),
          ],
        ),
      ),
    );
  }
}

/// 「继续观看」宽卡：一行两张、时间码贴右下。
///
/// 照 Rex 的 ResumeCard：16:9 缩略图 + 右下角剩余/已看时间 + 下方两行字。
/// 之前用海报竖卡排「继续观看」，一屏只能看到两张还不知道剩多少，
/// 横卡才能把时间信息放进图里。
class EmbyResumeCard extends StatelessWidget {
  const EmbyResumeCard({
    super.key,
    required this.imageUrl,
    required this.headers,
    required this.title,
    required this.subtitle,
    required this.timeLabel,
    required this.onTap,
    this.progress = 0,
  });

  final String imageUrl;
  final Map<String, String>? headers;
  final String title;
  final String subtitle;
  final String timeLabel;
  final VoidCallback onTap;

  /// 0..1，画在缩略图最底部。
  final double progress;

  @override
  Widget build(BuildContext context) {
    final RexPalette p = RexPalette.of(context);
    final double radius = embyRadius(context);

    return GestureDetector(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(radius),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  EmbyImage(url: imageUrl, headers: headers),
                  Positioned(
                    right: 8,
                    bottom: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        timeLabel,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  if (progress > 0)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: _ProgressStrip(ratio: progress),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: RexText.caption.copyWith(
              color: p.inkPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: RexText.micro.copyWith(color: p.inkTertiary),
          ),
        ],
      ),
    );
  }
}

/// 「我的媒体」文件夹卡：媒体库名大字压在图正中，卡下再写一行名字。
///
/// Emby 服务端给媒体库生成的图是一张海报拼贴，字压在中间正好读得清；
/// 没图的库用主题色调占位，不会出现死灰。
class EmbyFolderCard extends StatelessWidget {
  const EmbyFolderCard({
    super.key,
    required this.name,
    required this.imageUrl,
    required this.headers,
    required this.onTap,
    this.fallbackColor,
    this.icon,
  });

  final String name;
  final String imageUrl;
  final Map<String, String>? headers;
  final VoidCallback onTap;

  /// 没有封面图时的占位底色。
  final Color? fallbackColor;

  /// 占位底上显示的图标。
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final RexPalette p = RexPalette.of(context);
    final double radius = embyRadius(context);

    return GestureDetector(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(radius),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (imageUrl.isEmpty)
                    ColoredBox(
                      color: fallbackColor ?? p.surfaceSunken,
                      child: Center(
                        child: Icon(
                          icon ?? Icons.folder_outlined,
                          size: 34,
                          color: p.inkTertiary,
                        ),
                      ),
                    )
                  else
                    EmbyImage(url: imageUrl, headers: headers),
                  // 压一层轻黑渐变，保证白字在任何封面上都读得清。
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0x26000000), Color(0x73000000)],
                      ),
                    ),
                  ),
                  Center(
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.3,
                        shadows: [
                          Shadow(
                            color: Color(0x88000000),
                            blurRadius: 10,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: RexText.caption.copyWith(
              color: p.inkPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
