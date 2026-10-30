import 'package:XL/modules/bangumi/bangumi_item.dart';
import 'package:XL/modules/emby/emby_models.dart';
import 'package:XL/pages/video/video_playback_args.dart';
import 'package:XL/plugins/plugins.dart';
import 'package:XL/services/emby/emby_service.dart';

/// 把 Emby 的条目翻译成播放链路能吃的参数。
///
/// 详情页和历史续播两条入口都要做同一件事：造一个假的 [BangumiItem]、
/// 一个假的 [Plugin]、再摊平成 [EmbyPlaybackEpisode] 列表。放在这里共用，
/// 免得两边各写一份然后慢慢长歪。

/// 播放器和历史都写死了 [BangumiItem]，没有它就进不了播放链路。
///
/// `id` 用 [embyBangumiId] 从 Emby 的 GUID 折出来，保证同一部剧每次都一样，
/// 历史才能命中；不同剧撞 id 的概率在 31 位空间里可以忽略。
BangumiItem embyBangumiItem(EmbyItem item, EmbyServer server) {
  final client = EmbyService.instance.clientFor(server);
  return BangumiItem(
    id: embyBangumiId(item.id),
    type: 2,
    name: item.name,
    nameCn: item.name,
    summary: item.overview ?? '',
    airDate: item.productionYear?.toString() ?? '',
    airWeekday: 0,
    rank: 0,
    images: {
      'large': client.imageUrl(
        item.id,
        maxHeight: 640,
        tag: item.primaryImageTag,
      ),
    },
    tags: const [],
    alias: const [],
    ratingScore: item.communityRating ?? 0,
    votes: 0,
    votesCount: const [],
    info: '',
  );
}

/// 播放器里若干处会读 `currentPlugin.name` / `.referer`（那是 `late Plugin`），
/// 给 Emby 一个只有名字和基址的"假插件"，省得在每个调用点加空判断。
///
/// 名字必须等于 [EmbyServer.adapterName]，历史分档靠的就是这个字符串。
Plugin embyPlugin(EmbyServer server) => Plugin.fromJson({
      'name': server.adapterName,
      'baseURL': server.url,
      'userAgent': '',
      'referer': '',
      'useWebview': false,
    });

List<EmbyPlaybackEpisode> embyPlaybackEpisodes(List<EmbyItem> items) => [
      for (var i = 0; i < items.length; i++)
        EmbyPlaybackEpisode(
          itemId: items[i].id,
          title: embyEpisodeLabel(items[i], i + 1),
          episodeNumber: items[i].indexNumber ?? (i + 1),
        ),
    ];

/// 选集按钮上的文字。
///
/// Emby 的剧集名经常已经带集号（「第 3 集 出发」），再套一层「第 N 集」
/// 会重复，所以只在名字里完全没有数字时才补前缀。
String embyEpisodeLabel(EmbyItem item, int fallbackNumber) {
  final number = item.indexNumber ?? fallbackNumber;
  final name = item.name.trim();
  if (name.isEmpty) return '第 $number 集';
  final hasNumber = RegExp(r'\d').hasMatch(name);
  return hasNumber ? name : '第 $number 集 · $name';
}
