import 'package:XL/modules/emby/emby_models.dart';

/// 打开 Emby 播放器需要的全部上下文。
///
/// 用独立的路由参数而不是复用 `VideoPlaybackArgs`：Emby 播放器不认识
/// 番剧条目、插件和弹幕，硬塞一个假的 `BangumiItem` 进去只会让两边都别扭。
class EmbyPlaybackLaunch {
  const EmbyPlaybackLaunch({
    required this.server,
    required this.title,
    required this.episodes,
    this.initialIndex = 0,
    this.startAt,
  });

  final EmbyServer server;

  /// 标题，一般用剧名；电影就是片名。
  final String title;

  /// 可连续播放的条目，电影只有一条。
  final List<EmbyItem> episodes;

  /// 从第几条起播，0 起算。
  final int initialIndex;

  /// 起播位置。空 = 用条目自带的 `PlaybackPositionTicks`。
  ///
  /// 播放记录里的条目是本地缓存拼出来的（只有 id / 标题），没有 userData，
  /// 不带这个字段就永远从 0 开始——「点了播放记录却从头放」就是这么来的。
  final Duration? startAt;
}
