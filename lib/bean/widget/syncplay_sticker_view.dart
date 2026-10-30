import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'package:XL/pages/syncplay/syncplay_sticker_packs.dart';

/// 渲染一张表情包贴图。
///
/// 内置包读 asset（SVG），网络包走 [CachedNetworkImage]；对方装了我没装的包时
/// 显示占位，而不是让整个聊天列表报错。
class SyncPlayStickerView extends StatelessWidget {
  const SyncPlayStickerView({super.key, required this.sticker, this.size = 96});

  final SyncPlaySticker? sticker;
  final double size;

  @override
  Widget build(BuildContext context) {
    final SyncPlaySticker? target = sticker;
    if (target == null) {
      return _Placeholder(size: size, label: '表情包未安装');
    }
    if (target.isAsset) {
      if (target.asset.endsWith('.svg')) {
        return SvgPicture.asset(
          target.asset,
          width: size,
          height: size,
          fit: BoxFit.contain,
        );
      }
      return Image.asset(target.asset, width: size, height: size);
    }
    return CachedNetworkImage(
      imageUrl: target.url,
      width: size,
      height: size,
      fit: BoxFit.contain,
      fadeInDuration: const Duration(milliseconds: 120),
      placeholder: (context, url) => _Placeholder(size: size, label: null),
      errorWidget: (context, url, error) =>
          _Placeholder(size: size, label: '加载失败'),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.size, required this.label});

  final double size;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
      ),
      child: label == null
          ? SizedBox(
              width: size * 0.28,
              height: size * 0.28,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: colors.onSurfaceVariant.withValues(alpha: 0.5),
              ),
            )
          : Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text(
                label!,
                textAlign: TextAlign.center,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colors.onSurfaceVariant,
                  fontSize: 10,
                ),
              ),
            ),
    );
  }
}
