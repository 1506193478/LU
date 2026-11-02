import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:XL/bean/card/network_img_layer.dart';
import 'package:XL/bean/dialog/dialog_helper.dart';
import 'package:XL/bean/widget/clay_neu.dart' show isDesktopWideLayout;
import 'package:XL/pages/emby/emby_preview_style.dart';
import 'package:XL/bean/widget/collect_button.dart';
import 'package:XL/bean/widget/pressable.dart';
import 'package:XL/modules/bangumi/bangumi_item.dart';

// 视频卡片 - 垂直布局
class BangumiCardV extends StatelessWidget {
  const BangumiCardV({
    super.key,
    required this.bangumiItem,
    this.canTap = true,
    this.enableHero = true,
  });

  final BangumiItem bangumiItem;
  final bool canTap;
  final bool enableHero;

  @override
  Widget build(BuildContext context) {
    // 桌面端加一层「悬停浮起 + 快捷收藏」。手机没有指针，整套都不启用。
    return _HoverCard(
      enabled: isDesktopWideLayout(context),
      builder: (BuildContext context, bool hovered) {
        // Pv 全铺之后只剩一种外观，密度仍然按 [isDesktopWideLayout] 分。
        return _buildCard(context, hovered: hovered);
      },
    );
  }

  /// Pv 海报卡：白底圆角 + 封面 + 标题 + 评分/放送日。
  ///
  /// 手机端三列并排，卡片只有 ~120px 宽，内边距、圆角、字号都收紧，
  /// 否则一圈厚边把封面压得只剩一小块。
  Widget _buildCard(BuildContext context, {required bool hovered}) {
    final ThemeData theme = Theme.of(context);
    final BangumiItem item = bangumiItem;
    final bool wide = isDesktopWideLayout(context);
    final double pad = wide ? 12 : 7;
    final double radius = wide ? 16 : 18;

    return Pressable(
      pressedScale: 0.97,
      onTap: () {
        if (!canTap) {
          KazumiDialog.showToast(message: '编辑模式');
          return;
        }
        context.pushNamed('/info/', arguments: bangumiItem);
      },
      child: Container(
        padding: EdgeInsets.all(pad),
        decoration: BoxDecoration(
          color: PvColors.card(context),
          borderRadius: BorderRadius.circular(radius),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(wide ? 12 : 12),
                child: LayoutBuilder(
                  builder: (BuildContext context, BoxConstraints boxConstraints) {
                    final double maxWidth = boxConstraints.maxWidth;
                    final double maxHeight = boxConstraints.maxHeight;
                    return Stack(
                      fit: StackFit.expand,
                      children: <Widget>[
                        if (enableHero)
                          Hero(
                            transitionOnUserGestures: true,
                            flightShuttleBuilder:
                                NetworkImgLayer.heroFlightShuttleBuilder,
                            tag: bangumiItem.id,
                            child: NetworkImgLayer(
                              src: bangumiItem.images['large'] ?? '',
                              width: maxWidth,
                              height: maxHeight,
                            ),
                          )
                        else
                          NetworkImgLayer(
                            src: bangumiItem.images['large'] ?? '',
                            width: maxWidth,
                            height: maxHeight,
                          ),
                        if (hovered) _quickCollectOverlay(bangumiItem),
                      ],
                    );
                  },
                ),
              ),
            ),
            SizedBox(height: wide ? 12 : 7),
            Text(
              item.nameCn.isNotEmpty ? item.nameCn : item.name,
              maxLines: wide ? 1 : 2,
              overflow: TextOverflow.ellipsis,
              style: (wide
                      ? theme.textTheme.titleSmall
                      : theme.textTheme.labelMedium)
                  ?.copyWith(
                      fontWeight: FontWeight.w600,
                      height: 1.25,
                      color: PvColors.ink(context)),
            ),
            SizedBox(height: wide ? 4 : 3),
            Row(
              children: <Widget>[
                if (item.ratingScore > 0) ...<Widget>[
                  Icon(
                    Icons.star_rounded,
                    size: wide ? 13 : 11,
                    color: Colors.amber,
                  ),
                  const SizedBox(width: 2),
                  Text(
                    item.ratingScore.toStringAsFixed(1),
                    style: (wide
                            ? theme.textTheme.labelSmall
                            : theme.textTheme.labelSmall)
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(width: 6),
                ],
                Expanded(
                  child: Text(
                    item.airDate.isNotEmpty ? item.airDate : '—',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class BangumiContent extends StatelessWidget {
  const BangumiContent({super.key, required this.bangumiItem});

  final BangumiItem bangumiItem;

  @override
  Widget build(BuildContext context) {
    final ts = MediaQuery.textScalerOf(context);

    return Expanded(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(5, 3, 5, 1),
        child: LayoutBuilder(builder: (context, constraints) {
          final style = DefaultTextStyle.of(context).style.copyWith(
                fontWeight: FontWeight.w500,
                letterSpacing: 0.3,
              );
          final textScaler = ts.clamp(maxScaleFactor: 1.1);
          final painter = TextPainter(
            text: TextSpan(text: bangumiItem.nameCn, style: style),
            textDirection: Directionality.of(context),
            textScaler: textScaler,
          );
          final lines = (constraints.maxHeight / painter.preferredLineHeight)
              .floor()
              .clamp(1, 3);
          painter.dispose();
          return Text(
            bangumiItem.nameCn,
            textAlign: TextAlign.start,
            style: style,
            textScaler: textScaler,
            maxLines: lines,
            overflow: TextOverflow.ellipsis,
          );
        }),
      ),
    );
  }
}

/// 桌面端悬停时给卡片加的一点点「浮起来」的手感。
///
/// 只在宽屏桌面启用：手机上没有指针，`MouseRegion` 永远不会触发，
/// 白白多一层 widget。
class _HoverCard extends StatefulWidget {
  const _HoverCard({required this.enabled, required this.builder});

  final bool enabled;
  final Widget Function(BuildContext context, bool hovered) builder;

  @override
  State<_HoverCard> createState() => _HoverCardState();
}

class _HoverCardState extends State<_HoverCard> {
  static const Duration _duration = Duration(milliseconds: 160);

  bool _hovered = false;

  void _setHovered(bool value) {
    if (!widget.enabled || _hovered == value) return;
    setState(() => _hovered = value);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) {
      return widget.builder(context, false);
    }
    final bool dark = Theme.of(context).brightness == Brightness.dark;
    return MouseRegion(
      onEnter: (_) => _setHovered(true),
      onExit: (_) => _setHovered(false),
      child: AnimatedScale(
        scale: _hovered ? 1.022 : 1.0,
        duration: _duration,
        curve: Curves.easeOutCubic,
        child: AnimatedContainer(
          duration: _duration,
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(26),
            // 浮起来靠的是「影子变深变大」，不是放大 —— 放大只是辅助，
            // 单靠缩放会显得像在抖。
            boxShadow: _hovered
                ? <BoxShadow>[
                    BoxShadow(
                      color: Colors.black.withValues(alpha: dark ? 0.45 : 0.18),
                      blurRadius: 22,
                      offset: const Offset(0, 10),
                    ),
                  ]
                : const <BoxShadow>[],
          ),
          child: widget.builder(context, _hovered),
        ),
      ),
    );
  }
}

/// 悬停时浮在封面右上角的快捷收藏。点开就是原来那套「追番类型」菜单。
Positioned _quickCollectOverlay(BangumiItem item) {
  return Positioned(
    top: 2,
    right: 2,
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.42),
        shape: BoxShape.circle,
      ),
      child: Transform.scale(
        scale: 0.78,
        child: CollectButton(bangumiItem: item, color: Colors.white),
      ),
    ),
  );
}
