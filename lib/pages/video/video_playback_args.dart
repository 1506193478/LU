import 'package:XL/modules/bangumi/bangumi_item.dart';
import 'package:XL/modules/download/download_module.dart';
import 'package:XL/modules/emby/emby_models.dart';
import 'package:XL/modules/roads/road_module.dart';
import 'package:XL/plugins/plugins.dart';

/// Route arguments for '/video/'. Entry points hand playback context over
/// through the route instead of pre-filling a shared controller, which lets
/// [VideoPageController] live and die with the route.
sealed class VideoPlaybackArgs {
  const VideoPlaybackArgs({
    required this.bangumiItem,
    this.syncPlayRoom,
    this.syncPlayUserName,
  });

  final BangumiItem bangumiItem;

  /// 非空时播放器启动后自动加入这个「一起看」房间。
  final String? syncPlayRoom;
  final String? syncPlayUserName;
}

class OnlineVideoPlaybackArgs extends VideoPlaybackArgs {
  const OnlineVideoPlaybackArgs({
    required super.bangumiItem,
    required this.plugin,
    required this.title,
    required this.src,
    required this.roads,
    super.syncPlayRoom,
    super.syncPlayUserName,
  });

  final Plugin plugin;
  final String title;
  final String src;
  final List<Road> roads;
}

class OfflineVideoPlaybackArgs extends VideoPlaybackArgs {
  const OfflineVideoPlaybackArgs({
    required super.bangumiItem,
    required this.pluginName,
    required this.episodeNumber,
    required this.road,
    required this.downloadedEpisodes,
    super.syncPlayRoom,
    super.syncPlayUserName,
  });

  final String pluginName;
  final int episodeNumber;
  final int road;
  final List<DownloadEpisode> downloadedEpisodes;
}

/// Emby 媒体库里的单集。
///
/// 只需要 [itemId] 就能拼出直连播放地址，标题和集号纯粹是给界面用的。
class EmbyPlaybackEpisode {
  const EmbyPlaybackEpisode({
    required this.itemId,
    required this.title,
    required this.episodeNumber,
  });

  final String itemId;
  final String title;

  /// 集号，同时用作 [PlaybackHistoryIdentity.episodeNumber]。
  /// 必须 > 0，否则历史不会落库。
  final int episodeNumber;
}

/// 从 Emby 媒体库直接起播。
///
/// 和在线链路最大的区别是：这里没有"解析"这一步。地址在本地就能拼出来，
/// 所以 [VideoPageController] 会跳过 WebView，直接构造 [PlaybackInitParams]。
class EmbyVideoPlaybackArgs extends VideoPlaybackArgs {
  const EmbyVideoPlaybackArgs({
    required super.bangumiItem,
    required this.server,
    required this.plugin,
    required this.seriesTitle,
    required this.episodes,
    this.seriesItemId = '',
    this.initialEpisode = 1,
    super.syncPlayRoom,
    super.syncPlayUserName,
  });

  /// 带 Token 的服务器配置。带上它而不是去读"当前服务器"，
  /// 是因为播放期间用户可能在别处切了服务器。
  final EmbyServer server;

  /// 合成的插件对象，只为了让播放器里那些 `currentPlugin.name` /
  /// `.referer` 的调用点有个合法值。
  final Plugin plugin;

  final String seriesTitle;
  final List<EmbyPlaybackEpisode> episodes;

  /// 这部剧在 Emby 上的 item id。
  ///
  /// 会存进 `History.lastSrc`：历史页要"继续播放"时必须能重新向服务器要一次
  /// 剧集列表，而 [bangumiItem] 的 id 是从 GUID 折出来的哈希，反推不回去。
  final String seriesItemId;

  /// 从第几集起播，1 起算，对应 [episodes] 的下标 + 1。
  ///
  /// 用户点了哪一集就播哪一集，不会被"上次看到第几集"拉回去；
  /// 该集自己的续播进度仍然生效（播放页会按集号去查历史）。
  final int initialEpisode;
}
